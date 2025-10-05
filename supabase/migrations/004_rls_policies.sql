-- Migration 005: Row Level Security (RLS) Policies
-- Implements security policies for all tables

-- ============================================================================
-- ENABLE RLS ON ALL TABLES
-- ============================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_interactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_metadata ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_embeddings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_conversation_history ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- PROFILES
-- ============================================================================

-- Users can view and update their own profile
CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

-- ============================================================================
-- CONTACTS
-- ============================================================================

-- Users can manage their own contacts
CREATE POLICY "Users can view own contacts"
    ON public.contacts FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own contacts"
    ON public.contacts FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own contacts"
    ON public.contacts FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own contacts"
    ON public.contacts FOR DELETE
    USING (auth.uid() = user_id);

-- Users can view contacts shared with them (via app_interactions)
CREATE POLICY "Users can view shared contacts"
    ON public.contacts FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.app_interactions
            WHERE contact_id = contacts.id
                AND shared_with_user_id = auth.uid()
                AND interaction_type = 'contact_shared'
        )
    );

-- ============================================================================
-- TAGS
-- ============================================================================

CREATE POLICY "Users can manage own tags"
    ON public.tags FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- CONTACT_TAGS
-- ============================================================================

CREATE POLICY "Users can manage own contact tags"
    ON public.contact_tags FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.contacts
            WHERE id = contact_tags.contact_id AND user_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.contacts
            WHERE id = contact_tags.contact_id AND user_id = auth.uid()
        )
    );

-- ============================================================================
-- NOTES
-- ============================================================================

CREATE POLICY "Users can manage own notes"
    ON public.notes FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- REMINDERS
-- ============================================================================

CREATE POLICY "Users can manage own reminders"
    ON public.reminders FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- APP_INTERACTIONS
-- ============================================================================

CREATE POLICY "Users can manage own interactions"
    ON public.app_interactions FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can view interactions where contacts were shared with them
CREATE POLICY "Users can view received contact shares"
    ON public.app_interactions FOR SELECT
    USING (
        shared_with_user_id = auth.uid()
        AND interaction_type = 'contact_shared'
    );

-- ============================================================================
-- CONTACT_METADATA
-- ============================================================================

CREATE POLICY "Users can manage own contact metadata"
    ON public.contact_metadata FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.contacts
            WHERE id = contact_metadata.contact_id AND user_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.contacts
            WHERE id = contact_metadata.contact_id AND user_id = auth.uid()
        )
    );

-- ============================================================================
-- AI_INSIGHTS
-- ============================================================================

CREATE POLICY "Users can view own AI insights"
    ON public.ai_insights FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update own AI insights"
    ON public.ai_insights FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "System can insert AI insights"
    ON public.ai_insights FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- CONTACT_EMBEDDINGS
-- ============================================================================

CREATE POLICY "Users can view own contact embeddings"
    ON public.contact_embeddings FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "System can manage contact embeddings"
    ON public.contact_embeddings FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- AI_CONVERSATION_HISTORY
-- ============================================================================

CREATE POLICY "Users can view own AI conversations"
    ON public.ai_conversation_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert AI conversations"
    ON public.ai_conversation_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- HELPER FUNCTIONS FOR RLS
-- ============================================================================

-- Check if user has access to contact (own or shared)
CREATE OR REPLACE FUNCTION user_has_contact_access(p_user_id UUID, p_contact_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        -- Own contact
        SELECT 1 FROM public.contacts
        WHERE id = p_contact_id AND user_id = p_user_id
    ) OR EXISTS (
        -- Shared contact (via app_interactions)
        SELECT 1 FROM public.app_interactions
        WHERE contact_id = p_contact_id
            AND shared_with_user_id = p_user_id
            AND interaction_type = 'contact_shared'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON POLICY "Users can view own profile" ON public.profiles IS 'Users can only see their own profile';
COMMENT ON POLICY "Users can view own contacts" ON public.contacts IS 'Users can view contacts they created';
COMMENT ON POLICY "Users can view shared contacts" ON public.contacts IS 'Users can view contacts shared with them via app_interactions';
