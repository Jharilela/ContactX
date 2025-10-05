-- Migration 006: RPC Functions
-- Creates database functions callable from the frontend via Supabase RPC

-- ============================================================================
-- SEARCH & DISCOVERY
-- ============================================================================

-- Full-text search contacts with filters
CREATE OR REPLACE FUNCTION search_contacts(
    p_user_id UUID,
    p_query TEXT DEFAULT NULL,
    p_tags UUID[] DEFAULT NULL,
    p_priority relationship_priority[] DEFAULT NULL,
    p_favorites_only BOOLEAN DEFAULT FALSE,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone_number TEXT,
    company TEXT,
    job_title TEXT,
    avatar_url TEXT,
    relationship_priority relationship_priority,
    is_favorite BOOLEAN,
    last_contacted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    interaction_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.first_name,
        c.last_name,
        c.email,
        c.phone_number,
        c.company,
        c.job_title,
        c.avatar_url,
        c.relationship_priority,
        c.is_favorite,
        c.last_contacted_at,
        c.created_at,
        COUNT(ai.id) as interaction_count
    FROM public.contacts c
    LEFT JOIN public.app_interactions ai ON c.id = ai.contact_id
    WHERE c.user_id = p_user_id
        AND c.deleted_at IS NULL
        -- Search filter
        AND (
            p_query IS NULL
            OR c.first_name ILIKE '%' || p_query || '%'
            OR c.last_name ILIKE '%' || p_query || '%'
            OR c.email ILIKE '%' || p_query || '%'
            OR c.company ILIKE '%' || p_query || '%'
            OR c.job_title ILIKE '%' || p_query || '%'
        )
        -- Tag filter
        AND (
            p_tags IS NULL
            OR EXISTS (
                SELECT 1 FROM public.contact_tags ct
                WHERE ct.contact_id = c.id AND ct.tag_id = ANY(p_tags)
            )
        )
        -- Priority filter
        AND (p_priority IS NULL OR c.relationship_priority = ANY(p_priority))
        -- Favorites filter
        AND (p_favorites_only = FALSE OR c.is_favorite = TRUE)
    GROUP BY c.id
    ORDER BY
        c.is_favorite DESC,
        c.last_contacted_at DESC NULLS LAST,
        c.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- CONTACT INTELLIGENCE
-- ============================================================================

-- Get contacts that need follow-up
CREATE OR REPLACE FUNCTION get_contacts_needing_followup(
    p_user_id UUID,
    p_days_threshold INTEGER DEFAULT 30,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    first_name TEXT,
    last_name TEXT,
    company TEXT,
    avatar_url TEXT,
    relationship_priority relationship_priority,
    last_contacted_at TIMESTAMPTZ,
    days_since_contact INTEGER,
    total_interactions BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.first_name,
        c.last_name,
        c.company,
        c.avatar_url,
        c.relationship_priority,
        c.last_contacted_at,
        EXTRACT(DAY FROM NOW() - c.last_contacted_at)::INTEGER as days_since_contact,
        COUNT(ai.id) as total_interactions
    FROM public.contacts c
    LEFT JOIN public.app_interactions ai ON c.id = ai.contact_id
    WHERE c.user_id = p_user_id
        AND c.deleted_at IS NULL
        AND (
            c.last_contacted_at IS NULL
            OR c.last_contacted_at < NOW() - (p_days_threshold || ' days')::INTERVAL
        )
        AND c.relationship_priority IN ('high', 'critical')
    GROUP BY c.id
    ORDER BY
        c.relationship_priority DESC,
        c.last_contacted_at ASC NULLS FIRST
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- CONTACT TIMELINE
-- ============================================================================

-- Get complete timeline for a contact (interactions + notes)
CREATE OR REPLACE FUNCTION get_contact_timeline(
    p_user_id UUID,
    p_contact_id UUID,
    p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    type TEXT,
    content TEXT,
    interaction_type interaction_type,
    channel TEXT,
    duration_minutes INTEGER,
    occurred_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    -- Verify user has access to this contact
    IF NOT user_has_contact_access(p_user_id, p_contact_id) THEN
        RAISE EXCEPTION 'Access denied to contact';
    END IF;

    RETURN QUERY
    SELECT * FROM (
        -- Interactions
        SELECT
            ai.id,
            'interaction'::TEXT as type,
            ai.notes as content,
            ai.interaction_type,
            ai.channel,
            ai.duration_minutes,
            ai.occurred_at,
            ai.created_at
        FROM public.app_interactions ai
        WHERE ai.contact_id = p_contact_id

        UNION ALL

        -- Notes
        SELECT
            n.id,
            'note'::TEXT as type,
            n.content,
            NULL::interaction_type,
            NULL::TEXT,
            NULL::INTEGER,
            n.created_at as occurred_at,
            n.created_at
        FROM public.notes n
        WHERE n.contact_id = p_contact_id
    ) timeline
    ORDER BY occurred_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- DASHBOARD STATS
-- ============================================================================

-- Get user's contact statistics for dashboard
CREATE OR REPLACE FUNCTION get_dashboard_stats(p_user_id UUID)
RETURNS TABLE (
    total_contacts BIGINT,
    contacts_added_this_month BIGINT,
    critical_priority_count BIGINT,
    high_priority_count BIGINT,
    favorites_count BIGINT,
    needs_followup_count BIGINT,
    total_interactions_this_month BIGINT,
    active_reminders_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        -- Total contacts
        (SELECT COUNT(*) FROM public.contacts
         WHERE user_id = p_user_id AND deleted_at IS NULL),

        -- Contacts added this month
        (SELECT COUNT(*) FROM public.contacts
         WHERE user_id = p_user_id
         AND deleted_at IS NULL
         AND created_at >= date_trunc('month', NOW())),

        -- Critical priority
        (SELECT COUNT(*) FROM public.contacts
         WHERE user_id = p_user_id
         AND deleted_at IS NULL
         AND relationship_priority = 'critical'),

        -- High priority
        (SELECT COUNT(*) FROM public.contacts
         WHERE user_id = p_user_id
         AND deleted_at IS NULL
         AND relationship_priority = 'high'),

        -- Favorites
        (SELECT COUNT(*) FROM public.contacts
         WHERE user_id = p_user_id
         AND deleted_at IS NULL
         AND is_favorite = TRUE),

        -- Needs follow-up (30+ days)
        (SELECT COUNT(*) FROM public.contacts
         WHERE user_id = p_user_id
         AND deleted_at IS NULL
         AND relationship_priority IN ('high', 'critical')
         AND (last_contacted_at IS NULL OR last_contacted_at < NOW() - INTERVAL '30 days')),

        -- Total interactions this month
        (SELECT COUNT(*) FROM public.app_interactions
         WHERE user_id = p_user_id
         AND occurred_at >= date_trunc('month', NOW())),

        -- Active reminders
        (SELECT COUNT(*) FROM public.reminders
         WHERE user_id = p_user_id
         AND is_completed = FALSE
         AND remind_at > NOW());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- CONTACT SHARING
-- ============================================================================

-- Share contact with another user
CREATE OR REPLACE FUNCTION share_contact_with_user(
    p_user_id UUID,
    p_contact_id UUID,
    p_recipient_email TEXT,
    p_message TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_recipient_id UUID;
    v_interaction_id UUID;
BEGIN
    -- Verify user owns this contact
    IF NOT EXISTS (
        SELECT 1 FROM public.contacts
        WHERE id = p_contact_id AND user_id = p_user_id
    ) THEN
        RAISE EXCEPTION 'Contact not found or access denied';
    END IF;

    -- Find recipient user by email
    SELECT id INTO v_recipient_id
    FROM public.profiles
    WHERE email = p_recipient_email;

    IF v_recipient_id IS NULL THEN
        RAISE EXCEPTION 'Recipient user not found with email: %', p_recipient_email;
    END IF;

    IF v_recipient_id = p_user_id THEN
        RAISE EXCEPTION 'Cannot share contact with yourself';
    END IF;

    -- Create contact share interaction
    INSERT INTO public.app_interactions (
        contact_id,
        user_id,
        interaction_type,
        shared_with_user_id,
        share_message,
        occurred_at
    ) VALUES (
        p_contact_id,
        p_user_id,
        'contact_shared',
        v_recipient_id,
        p_message,
        NOW()
    )
    RETURNING id INTO v_interaction_id;

    RETURN v_interaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- BULK OPERATIONS
-- ============================================================================

-- Bulk import contacts
CREATE OR REPLACE FUNCTION bulk_import_contacts(
    p_user_id UUID,
    p_contacts JSONB
)
RETURNS TABLE (
    success BOOLEAN,
    imported_count INTEGER,
    skipped_count INTEGER,
    errors JSONB
) AS $$
DECLARE
    v_contact JSONB;
    v_imported INTEGER := 0;
    v_skipped INTEGER := 0;
    v_errors JSONB := '[]'::JSONB;
    v_contact_id UUID;
BEGIN
    -- Loop through contacts array
    FOR v_contact IN SELECT * FROM jsonb_array_elements(p_contacts)
    LOOP
        BEGIN
            -- Skip if contact already exists (by phone or email)
            IF EXISTS (
                SELECT 1 FROM public.contacts
                WHERE user_id = p_user_id
                AND deleted_at IS NULL
                AND (
                    (phone_number IS NOT NULL AND phone_number = v_contact->>'phone_number')
                    OR (email IS NOT NULL AND email = v_contact->>'email')
                )
            ) THEN
                v_skipped := v_skipped + 1;
                CONTINUE;
            END IF;

            -- Insert contact
            INSERT INTO public.contacts (
                user_id,
                first_name,
                last_name,
                phone_number,
                email,
                company,
                job_title
            ) VALUES (
                p_user_id,
                v_contact->>'first_name',
                v_contact->>'last_name',
                v_contact->>'phone_number',
                v_contact->>'email',
                v_contact->>'company',
                v_contact->>'job_title'
            )
            RETURNING id INTO v_contact_id;

            v_imported := v_imported + 1;

        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors || jsonb_build_object(
                'contact', v_contact,
                'error', SQLERRM
            );
        END;
    END LOOP;

    RETURN QUERY SELECT
        TRUE,
        v_imported,
        v_skipped,
        v_errors;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- REMINDERS
-- ============================================================================

-- Get upcoming reminders
CREATE OR REPLACE FUNCTION get_upcoming_reminders(
    p_user_id UUID,
    p_days_ahead INTEGER DEFAULT 7,
    p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    contact_id UUID,
    contact_name TEXT,
    contact_avatar_url TEXT,
    title TEXT,
    description TEXT,
    remind_at TIMESTAMPTZ,
    is_ai_generated BOOLEAN,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.id,
        r.contact_id,
        c.first_name || ' ' || COALESCE(c.last_name, '') as contact_name,
        c.avatar_url as contact_avatar_url,
        r.title,
        r.description,
        r.remind_at,
        r.is_ai_generated,
        r.created_at
    FROM public.reminders r
    JOIN public.contacts c ON r.contact_id = c.id
    WHERE r.user_id = p_user_id
        AND r.is_completed = FALSE
        AND r.remind_at BETWEEN NOW() AND (NOW() + (p_days_ahead || ' days')::INTERVAL)
    ORDER BY r.remind_at ASC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON FUNCTION search_contacts IS 'Full-text search contacts with filters (tags, priority, favorites)';
COMMENT ON FUNCTION get_contacts_needing_followup IS 'Get high-priority contacts that haven''t been contacted recently';
COMMENT ON FUNCTION get_contact_timeline IS 'Get complete timeline of interactions and notes for a contact';
COMMENT ON FUNCTION get_dashboard_stats IS 'Get user statistics for dashboard overview';
COMMENT ON FUNCTION share_contact_with_user IS 'Share a contact with another user by email';
COMMENT ON FUNCTION bulk_import_contacts IS 'Bulk import contacts from JSON array';
COMMENT ON FUNCTION get_upcoming_reminders IS 'Get upcoming reminders for the next N days';
