-- Migration 002: Intelligence Tables (Phase 2)
-- Adds interaction tracking and contact metadata

-- ============================================================================
-- ENUMS
-- ============================================================================

CREATE TYPE interaction_type AS ENUM (
    'call',
    'message',
    'email',
    'meeting',
    'social',
    'coffee',
    'contact_shared',
    'other'
);

-- ============================================================================
-- APP_INTERACTIONS
-- ============================================================================

CREATE TABLE public.app_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id UUID NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

    -- Interaction Details
    interaction_type interaction_type NOT NULL,
    channel TEXT, -- e.g., 'WhatsApp', 'LinkedIn', 'Phone', 'Zoom'
    notes TEXT,

    -- Contact Sharing (when interaction_type = 'contact_shared')
    shared_with_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    share_message TEXT,

    -- Timing
    occurred_at TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER, -- Optional: track meeting/call duration

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Constraints
    CONSTRAINT duration_positive CHECK (duration_minutes IS NULL OR duration_minutes > 0),
    CONSTRAINT share_requires_recipient CHECK (
        (interaction_type = 'contact_shared' AND shared_with_user_id IS NOT NULL) OR
        (interaction_type != 'contact_shared' AND shared_with_user_id IS NULL)
    )
);

-- ============================================================================
-- CONTACT_METADATA
-- ============================================================================

CREATE TABLE public.contact_metadata (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id UUID NOT NULL UNIQUE REFERENCES public.contacts(id) ON DELETE CASCADE,

    -- Social Links
    linkedin_url TEXT,
    twitter_handle TEXT,
    instagram_handle TEXT,
    facebook_url TEXT,

    -- Additional Context
    location TEXT,
    birthday DATE,
    timezone TEXT, -- e.g., 'America/Los_Angeles'
    interests TEXT[], -- Array of interests

    -- Custom Fields (flexible JSONB storage)
    custom_fields JSONB DEFAULT '{}'::JSONB,

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Constraints
    CONSTRAINT valid_twitter_handle CHECK (
        twitter_handle IS NULL OR
        twitter_handle ~ '^@?[A-Za-z0-9_]{1,15}$'
    ),
    CONSTRAINT valid_instagram_handle CHECK (
        instagram_handle IS NULL OR
        instagram_handle ~ '^@?[A-Za-z0-9_.]{1,30}$'
    )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- App Interactions
CREATE INDEX idx_app_interactions_contact_id ON public.app_interactions(contact_id, occurred_at DESC);
CREATE INDEX idx_app_interactions_user_id ON public.app_interactions(user_id, occurred_at DESC);
CREATE INDEX idx_app_interactions_occurred_at ON public.app_interactions(occurred_at DESC);
CREATE INDEX idx_app_interactions_type ON public.app_interactions(interaction_type, occurred_at DESC);
CREATE INDEX idx_app_interactions_shared_with ON public.app_interactions(shared_with_user_id) WHERE shared_with_user_id IS NOT NULL;

-- Contact Metadata
CREATE INDEX idx_contact_metadata_contact_id ON public.contact_metadata(contact_id);
CREATE INDEX idx_contact_metadata_birthday ON public.contact_metadata(birthday) WHERE birthday IS NOT NULL;
CREATE INDEX idx_contact_metadata_location ON public.contact_metadata(location) WHERE location IS NOT NULL;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Auto-update updated_at for contact_metadata
CREATE TRIGGER update_contact_metadata_updated_at
    BEFORE UPDATE ON public.contact_metadata
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function to update last_contacted_at when interaction is created
CREATE OR REPLACE FUNCTION update_last_contacted_on_interaction()
RETURNS TRIGGER AS $$
BEGIN
    -- Update last_contacted_at on contact
    UPDATE public.contacts
    SET last_contacted_at = NEW.occurred_at
    WHERE id = NEW.contact_id
        AND (last_contacted_at IS NULL OR last_contacted_at < NEW.occurred_at);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_contact_on_interaction
    AFTER INSERT ON public.app_interactions
    FOR EACH ROW
    EXECUTE FUNCTION update_last_contacted_on_interaction();

-- Function to get interaction stats for a contact (computed on demand)
CREATE OR REPLACE FUNCTION get_contact_interaction_stats(p_contact_id UUID)
RETURNS TABLE (
    total_interactions BIGINT,
    last_interaction_at TIMESTAMPTZ,
    first_interaction_at TIMESTAMPTZ,
    interactions_last_30_days BIGINT,
    interactions_last_90_days BIGINT,
    avg_days_between_interactions NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) AS total_interactions,
        MAX(occurred_at) AS last_interaction_at,
        MIN(occurred_at) AS first_interaction_at,
        COUNT(*) FILTER (WHERE occurred_at >= NOW() - INTERVAL '30 days') AS interactions_last_30_days,
        COUNT(*) FILTER (WHERE occurred_at >= NOW() - INTERVAL '90 days') AS interactions_last_90_days,
        CASE
            WHEN COUNT(*) > 1 THEN
                EXTRACT(DAY FROM (MAX(occurred_at) - MIN(occurred_at))) / NULLIF(COUNT(*) - 1, 0)
            ELSE NULL
        END AS avg_days_between_interactions
    FROM public.app_interactions
    WHERE contact_id = p_contact_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE public.app_interactions IS 'Tracks all interactions/touch points with contacts, including contact sharing';
COMMENT ON TABLE public.contact_metadata IS 'Extended metadata and social information for contacts';

COMMENT ON COLUMN public.app_interactions.channel IS 'Communication platform used (WhatsApp, LinkedIn, Phone, etc.)';
COMMENT ON COLUMN public.app_interactions.duration_minutes IS 'Duration of meeting or call in minutes';
COMMENT ON COLUMN public.app_interactions.shared_with_user_id IS 'User ID when contact is shared (interaction_type = contact_shared)';
COMMENT ON COLUMN public.contact_metadata.custom_fields IS 'Flexible JSONB storage for user-defined fields';
COMMENT ON FUNCTION get_contact_interaction_stats IS 'Computes interaction statistics for a contact on demand';
