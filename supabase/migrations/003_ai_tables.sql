-- Migration 003: AI & Enhancement Tables (Phase 3)
-- Adds AI insights and vector embeddings for semantic search

-- ============================================================================
-- EXTENSIONS
-- ============================================================================

-- Enable pgvector for semantic search
CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================================================
-- ENUMS
-- ============================================================================

CREATE TYPE insight_type AS ENUM (
    'follow_up_suggestion',
    'relationship_warning',
    'opportunity',
    'memory',
    'birthday_reminder',
    'networking_suggestion',
    'engagement_alert'
);

-- ============================================================================
-- AI_INSIGHTS
-- ============================================================================

CREATE TABLE public.ai_insights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id UUID NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

    -- Insight Details
    insight_type insight_type NOT NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    action_url TEXT, -- Deep link to relevant screen/action

    -- AI Metadata
    confidence_score NUMERIC(5, 2), -- 0-100, how confident the AI is
    model_version TEXT, -- e.g., 'gpt-4-2024-01', for tracking

    -- Status
    is_dismissed BOOLEAN DEFAULT FALSE,
    is_acted_upon BOOLEAN DEFAULT FALSE,
    acted_upon_at TIMESTAMPTZ,

    -- Lifecycle
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    expires_at TIMESTAMPTZ, -- Some insights are time-sensitive

    -- Constraints
    CONSTRAINT valid_confidence_score CHECK (
        confidence_score IS NULL OR
        (confidence_score >= 0 AND confidence_score <= 100)
    ),
    CONSTRAINT title_not_empty CHECK (length(trim(title)) > 0),
    CONSTRAINT content_not_empty CHECK (length(trim(content)) > 0)
);

-- ============================================================================
-- CONTACT_EMBEDDINGS
-- ============================================================================

CREATE TABLE public.contact_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id UUID NOT NULL UNIQUE REFERENCES public.contacts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

    -- Vector Embedding (1536 dimensions for OpenAI text-embedding-ada-002)
    embedding vector(1536),

    -- Metadata
    content_hash TEXT NOT NULL, -- Hash of source content to detect changes
    source_text TEXT, -- The text that was embedded (for debugging)
    model_version TEXT DEFAULT 'text-embedding-ada-002',

    -- Lifecycle
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Constraints
    CONSTRAINT content_hash_not_empty CHECK (length(trim(content_hash)) > 0)
);

-- ============================================================================
-- AI_CONVERSATION_HISTORY
-- ============================================================================

-- Tracks AI conversation context for better personalization
CREATE TABLE public.ai_conversation_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES public.contacts(id) ON DELETE CASCADE, -- NULL for general queries

    -- Conversation
    user_message TEXT NOT NULL,
    ai_response TEXT NOT NULL,

    -- Context
    context_used JSONB, -- What context was provided to AI
    tokens_used INTEGER,
    model_version TEXT,

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Constraints
    CONSTRAINT user_message_not_empty CHECK (length(trim(user_message)) > 0),
    CONSTRAINT ai_response_not_empty CHECK (length(trim(ai_response)) > 0)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- AI Insights
CREATE INDEX idx_ai_insights_user_id ON public.ai_insights(user_id, created_at DESC);
CREATE INDEX idx_ai_insights_contact_id ON public.ai_insights(contact_id, created_at DESC);
CREATE INDEX idx_ai_insights_not_dismissed ON public.ai_insights(user_id, insight_type)
    WHERE is_dismissed = FALSE;
CREATE INDEX idx_ai_insights_type ON public.ai_insights(insight_type, created_at DESC);
CREATE INDEX idx_ai_insights_expires_at ON public.ai_insights(expires_at) WHERE expires_at IS NOT NULL;

-- Contact Embeddings (Vector Index for similarity search)
CREATE INDEX idx_contact_embeddings_vector ON public.contact_embeddings
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100); -- Adjust lists based on dataset size

CREATE INDEX idx_contact_embeddings_user_id ON public.contact_embeddings(user_id);
CREATE INDEX idx_contact_embeddings_content_hash ON public.contact_embeddings(content_hash);

-- AI Conversation History
CREATE INDEX idx_ai_conversation_user_id ON public.ai_conversation_history(user_id, created_at DESC);
CREATE INDEX idx_ai_conversation_contact_id ON public.ai_conversation_history(contact_id, created_at DESC)
    WHERE contact_id IS NOT NULL;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Auto-update updated_at for contact_embeddings
CREATE TRIGGER update_contact_embeddings_updated_at
    BEFORE UPDATE ON public.contact_embeddings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function to find similar contacts using vector search
CREATE OR REPLACE FUNCTION find_similar_contacts(
    p_user_id UUID,
    p_query_embedding vector(1536),
    p_limit INTEGER DEFAULT 10,
    p_similarity_threshold NUMERIC DEFAULT 0.7
)
RETURNS TABLE (
    contact_id UUID,
    similarity NUMERIC,
    first_name TEXT,
    last_name TEXT,
    company TEXT,
    job_title TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        1 - (ce.embedding <=> p_query_embedding) AS similarity,
        c.first_name,
        c.last_name,
        c.company,
        c.job_title
    FROM public.contact_embeddings ce
    JOIN public.contacts c ON ce.contact_id = c.id
    WHERE ce.user_id = p_user_id
        AND c.deleted_at IS NULL
        AND 1 - (ce.embedding <=> p_query_embedding) >= p_similarity_threshold
    ORDER BY ce.embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Function to generate content hash for embeddings
CREATE OR REPLACE FUNCTION generate_embedding_content(p_contact_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_content TEXT;
    v_notes TEXT;
    v_tags TEXT;
BEGIN
    -- Combine contact info, notes, and tags into searchable content
    SELECT
        CONCAT_WS(' ',
            c.first_name,
            c.last_name,
            c.company,
            c.job_title,
            c.how_we_met,
            cm.location,
            cm.interests::TEXT
        )
    INTO v_content
    FROM public.contacts c
    LEFT JOIN public.contact_metadata cm ON cm.contact_id = c.id
    WHERE c.id = p_contact_id;

    -- Append recent notes
    SELECT string_agg(content, ' ')
    INTO v_notes
    FROM (
        SELECT content
        FROM public.notes
        WHERE contact_id = p_contact_id
        ORDER BY created_at DESC
        LIMIT 5
    ) recent_notes;

    -- Append tags
    SELECT string_agg(t.name, ' ')
    INTO v_tags
    FROM public.contact_tags ct
    JOIN public.tags t ON ct.tag_id = t.id
    WHERE ct.contact_id = p_contact_id;

    RETURN CONCAT_WS(' ', v_content, v_notes, v_tags);
END;
$$ LANGUAGE plpgsql;

-- Function to clean up expired insights (call this periodically)
CREATE OR REPLACE FUNCTION cleanup_expired_insights()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM public.ai_insights
    WHERE expires_at IS NOT NULL
        AND expires_at < NOW() - INTERVAL '30 days'
        AND is_acted_upon = FALSE;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Active AI insights view (commonly queried)
CREATE OR REPLACE VIEW active_ai_insights AS
SELECT
    ai.*,
    c.first_name,
    c.last_name,
    c.company
FROM public.ai_insights ai
JOIN public.contacts c ON ai.contact_id = c.id
WHERE ai.is_dismissed = FALSE
    AND (ai.expires_at IS NULL OR ai.expires_at > NOW())
    AND c.deleted_at IS NULL
ORDER BY ai.created_at DESC;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE public.ai_insights IS 'AI-generated insights and suggestions for relationship management';
COMMENT ON TABLE public.contact_embeddings IS 'Vector embeddings for semantic search across contacts';
COMMENT ON TABLE public.ai_conversation_history IS 'History of AI interactions for context and personalization';

COMMENT ON COLUMN public.ai_insights.confidence_score IS 'AI confidence level (0-100) for this insight';
COMMENT ON COLUMN public.ai_insights.expires_at IS 'When this insight becomes irrelevant (e.g., event-based suggestions)';
COMMENT ON COLUMN public.contact_embeddings.embedding IS '1536-dimensional vector from OpenAI text-embedding-ada-002';
COMMENT ON COLUMN public.contact_embeddings.content_hash IS 'Hash to detect when re-embedding is needed';
COMMENT ON FUNCTION find_similar_contacts IS 'Vector similarity search to find contacts matching a query embedding';
