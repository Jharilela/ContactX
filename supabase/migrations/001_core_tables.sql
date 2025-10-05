-- Migration 001: Core Tables (Phase 1 - MVP)
-- Creates fundamental tables for contacts, tags, notes, and reminders

-- ============================================================================
-- ENUMS
-- ============================================================================

CREATE TYPE subscription_tier AS ENUM ('free', 'pro');
CREATE TYPE relationship_priority AS ENUM ('low', 'medium', 'high', 'critical');

-- ============================================================================
-- USERS / PROFILES
-- ============================================================================

-- Extend Supabase auth.users with profile information
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    full_name TEXT,
    avatar_url TEXT,
    subscription_tier subscription_tier DEFAULT 'free' NOT NULL,
    subscription_expires_at TIMESTAMPTZ,
    onboarding_completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================================
-- CONTACTS
-- ============================================================================

CREATE TABLE public.contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

    -- Basic Information
    first_name TEXT NOT NULL,
    last_name TEXT,
    phone_number TEXT,
    email TEXT,
    company TEXT,
    job_title TEXT,
    avatar_url TEXT,

    -- Context & Relationship
    how_we_met TEXT,
    relationship_priority relationship_priority DEFAULT 'medium',
    is_favorite BOOLEAN DEFAULT FALSE,

    -- Tracking
    last_contacted_at TIMESTAMPTZ,

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    deleted_at TIMESTAMPTZ, -- Soft delete

    -- Constraints
    CONSTRAINT contact_has_name CHECK (first_name IS NOT NULL AND length(trim(first_name)) > 0)
);

-- ============================================================================
-- TAGS
-- ============================================================================

CREATE TABLE public.tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT DEFAULT '#3B82F6', -- Default blue color
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Constraints
    CONSTRAINT unique_tag_per_user UNIQUE (user_id, name),
    CONSTRAINT tag_name_not_empty CHECK (length(trim(name)) > 0)
);

-- ============================================================================
-- CONTACT_TAGS (Many-to-Many)
-- ============================================================================

CREATE TABLE public.contact_tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id UUID NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES public.tags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Constraints
    CONSTRAINT unique_contact_tag UNIQUE (contact_id, tag_id)
);

-- ============================================================================
-- NOTES
-- ============================================================================

CREATE TABLE public.notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id UUID NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Constraints
    CONSTRAINT note_not_empty CHECK (length(trim(content)) > 0)
);

-- ============================================================================
-- REMINDERS
-- ============================================================================

CREATE TABLE public.reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id UUID NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

    title TEXT NOT NULL,
    description TEXT,
    remind_at TIMESTAMPTZ NOT NULL,

    -- Status
    is_completed BOOLEAN DEFAULT FALSE,
    completed_at TIMESTAMPTZ,

    -- AI & Recurrence
    is_ai_generated BOOLEAN DEFAULT FALSE,
    recurrence_rule TEXT, -- RRULE format for recurring reminders

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Constraints
    CONSTRAINT reminder_title_not_empty CHECK (length(trim(title)) > 0),
    CONSTRAINT completed_at_requires_is_completed CHECK (
        (is_completed = TRUE AND completed_at IS NOT NULL) OR
        (is_completed = FALSE AND completed_at IS NULL)
    )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Profiles
CREATE INDEX idx_profiles_subscription ON public.profiles(subscription_tier, subscription_expires_at);

-- Contacts
CREATE INDEX idx_contacts_user_id ON public.contacts(user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_contacts_user_id_last_contacted ON public.contacts(user_id, last_contacted_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_contacts_user_id_favorite ON public.contacts(user_id, is_favorite) WHERE deleted_at IS NULL AND is_favorite = TRUE;
CREATE INDEX idx_contacts_user_id_priority ON public.contacts(user_id, relationship_priority) WHERE deleted_at IS NULL;
CREATE INDEX idx_contacts_email ON public.contacts(email) WHERE email IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX idx_contacts_phone ON public.contacts(phone_number) WHERE phone_number IS NOT NULL AND deleted_at IS NULL;

-- Tags
CREATE INDEX idx_tags_user_id ON public.tags(user_id);

-- Contact Tags
CREATE INDEX idx_contact_tags_contact_id ON public.contact_tags(contact_id);
CREATE INDEX idx_contact_tags_tag_id ON public.contact_tags(tag_id);

-- Notes
CREATE INDEX idx_notes_contact_id ON public.notes(contact_id, created_at DESC);
CREATE INDEX idx_notes_user_id ON public.notes(user_id, created_at DESC);

-- Reminders
CREATE INDEX idx_reminders_user_id_upcoming ON public.reminders(user_id, remind_at) WHERE is_completed = FALSE;
CREATE INDEX idx_reminders_contact_id ON public.reminders(contact_id) WHERE is_completed = FALSE;
CREATE INDEX idx_reminders_ai_generated ON public.reminders(user_id, is_ai_generated) WHERE is_ai_generated = TRUE AND is_completed = FALSE;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-update updated_at for profiles
CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Auto-update updated_at for contacts
CREATE TRIGGER update_contacts_updated_at
    BEFORE UPDATE ON public.contacts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Auto-update updated_at for notes
CREATE TRIGGER update_notes_updated_at
    BEFORE UPDATE ON public.notes
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Auto-update updated_at for reminders
CREATE TRIGGER update_reminders_updated_at
    BEFORE UPDATE ON public.reminders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Auto-update last_contacted_at when reminder is completed
CREATE OR REPLACE FUNCTION update_last_contacted_on_reminder_complete()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_completed = TRUE AND OLD.is_completed = FALSE THEN
        UPDATE public.contacts
        SET last_contacted_at = NEW.completed_at
        WHERE id = NEW.contact_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_contact_last_contacted
    AFTER UPDATE ON public.reminders
    FOR EACH ROW
    WHEN (NEW.is_completed = TRUE AND OLD.is_completed = FALSE)
    EXECUTE FUNCTION update_last_contacted_on_reminder_complete();

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE public.profiles IS 'User profiles extending Supabase auth.users';
COMMENT ON TABLE public.contacts IS 'Core contact information with relationship context';
COMMENT ON TABLE public.tags IS 'User-defined tags for organizing contacts';
COMMENT ON TABLE public.contact_tags IS 'Many-to-many relationship between contacts and tags';
COMMENT ON TABLE public.notes IS 'Rich contextual notes for each contact';
COMMENT ON TABLE public.reminders IS 'Smart reminders for follow-ups and check-ins';

COMMENT ON COLUMN public.contacts.deleted_at IS 'Soft delete timestamp - allows recovery';
COMMENT ON COLUMN public.contacts.last_contacted_at IS 'Last meaningful interaction with this contact';
COMMENT ON COLUMN public.reminders.recurrence_rule IS 'RRULE format for recurring reminders (e.g., weekly check-ins)';
COMMENT ON COLUMN public.reminders.is_ai_generated IS 'TRUE if this reminder was suggested by AI';
