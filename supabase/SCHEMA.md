# ContactX Database Schema

Complete database schema documentation for ContactX - a mobile-first personal CRM.

---

## Overview

The database is organized into 4 migration phases:

1. **Phase 1 (MVP)**: Core tables for contacts, tags, notes, and reminders
2. **Phase 2 (Intelligence)**: Interaction tracking and extended metadata
3. **Phase 3 (AI)**: AI insights and semantic search capabilities
4. **Phase 4 (Security)**: Row Level Security policies

---

## Database Tables

### Phase 1: Core Tables

#### `profiles`
Extends Supabase `auth.users` with application-specific user data.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY, FK → auth.users(id) | User ID from Supabase Auth |
| `email` | TEXT | | User email |
| `full_name` | TEXT | | User's full name |
| `avatar_url` | TEXT | | Profile picture URL |
| `subscription_tier` | subscription_tier | NOT NULL, DEFAULT 'free' | Subscription level (free/pro) |
| `subscription_expires_at` | TIMESTAMPTZ | | Pro subscription expiry |
| `onboarding_completed` | BOOLEAN | DEFAULT FALSE | Onboarding status |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Last update timestamp |

**Indexes:**
- `idx_profiles_subscription` on `(subscription_tier, subscription_expires_at)`

---

#### `contacts`
Core contact information with relationship tracking.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY | Contact ID |
| `user_id` | UUID | NOT NULL, FK → profiles(id) | Owner of this contact |
| `first_name` | TEXT | NOT NULL | First name (required) |
| `last_name` | TEXT | | Last name |
| `phone_number` | TEXT | | Phone number |
| `email` | TEXT | | Email address |
| `company` | TEXT | | Company name |
| `job_title` | TEXT | | Job title |
| `avatar_url` | TEXT | | Contact photo URL |
| `how_we_met` | TEXT | | Context of how you met |
| `relationship_priority` | relationship_priority | DEFAULT 'medium' | Priority level (low/medium/high/critical) |
| `is_favorite` | BOOLEAN | DEFAULT FALSE | Favorite flag |
| `last_contacted_at` | TIMESTAMPTZ | | Last interaction timestamp |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Last update timestamp |
| `deleted_at` | TIMESTAMPTZ | | Soft delete timestamp |

**Indexes:**
- `idx_contacts_user_id` on `(user_id)` WHERE `deleted_at IS NULL`
- `idx_contacts_user_id_last_contacted` on `(user_id, last_contacted_at DESC)` WHERE `deleted_at IS NULL`
- `idx_contacts_user_id_favorite` on `(user_id, is_favorite)` WHERE `deleted_at IS NULL AND is_favorite = TRUE`
- `idx_contacts_user_id_priority` on `(user_id, relationship_priority)` WHERE `deleted_at IS NULL`
- `idx_contacts_email` on `(email)` WHERE `email IS NOT NULL AND deleted_at IS NULL`
- `idx_contacts_phone` on `(phone_number)` WHERE `phone_number IS NOT NULL AND deleted_at IS NULL`

**Constraints:**
- `contact_has_name`: First name must not be empty

---

#### `tags`
User-defined tags for contact organization.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY | Tag ID |
| `user_id` | UUID | NOT NULL, FK → profiles(id) | Tag owner |
| `name` | TEXT | NOT NULL | Tag name |
| `color` | TEXT | DEFAULT '#3B82F6' | Tag color (hex) |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |

**Indexes:**
- `idx_tags_user_id` on `(user_id)`

**Constraints:**
- `unique_tag_per_user`: Unique `(user_id, name)`
- `tag_name_not_empty`: Name must not be empty

---

#### `contact_tags`
Many-to-many relationship between contacts and tags.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY | Relationship ID |
| `contact_id` | UUID | NOT NULL, FK → contacts(id) | Contact reference |
| `tag_id` | UUID | NOT NULL, FK → tags(id) | Tag reference |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |

**Indexes:**
- `idx_contact_tags_contact_id` on `(contact_id)`
- `idx_contact_tags_tag_id` on `(tag_id)`

**Constraints:**
- `unique_contact_tag`: Unique `(contact_id, tag_id)`

---

#### `notes`
Rich contextual notes for each contact.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY | Note ID |
| `contact_id` | UUID | NOT NULL, FK → contacts(id) | Associated contact |
| `user_id` | UUID | NOT NULL, FK → profiles(id) | Note author |
| `content` | TEXT | NOT NULL | Note content |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Last update timestamp |

**Indexes:**
- `idx_notes_contact_id` on `(contact_id, created_at DESC)`
- `idx_notes_user_id` on `(user_id, created_at DESC)`

**Constraints:**
- `note_not_empty`: Content must not be empty

---

#### `reminders`
Smart reminders for follow-ups and check-ins.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY | Reminder ID |
| `contact_id` | UUID | NOT NULL, FK → contacts(id) | Associated contact |
| `user_id` | UUID | NOT NULL, FK → profiles(id) | Reminder owner |
| `title` | TEXT | NOT NULL | Reminder title |
| `description` | TEXT | | Additional details |
| `remind_at` | TIMESTAMPTZ | NOT NULL | When to trigger reminder |
| `is_completed` | BOOLEAN | DEFAULT FALSE | Completion status |
| `completed_at` | TIMESTAMPTZ | | Completion timestamp |
| `is_ai_generated` | BOOLEAN | DEFAULT FALSE | AI-generated flag |
| `recurrence_rule` | TEXT | | RRULE format for recurring |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Last update timestamp |

**Indexes:**
- `idx_reminders_user_id_upcoming` on `(user_id, remind_at)` WHERE `is_completed = FALSE`
- `idx_reminders_contact_id` on `(contact_id)` WHERE `is_completed = FALSE`
- `idx_reminders_ai_generated` on `(user_id, is_ai_generated)` WHERE `is_ai_generated = TRUE AND is_completed = FALSE`

**Constraints:**
- `reminder_title_not_empty`: Title must not be empty
- `completed_at_requires_is_completed`: Completion timestamp logic

---

### Phase 2: Intelligence Tables

#### `app_interactions`
Tracks all interactions/touch points with contacts, including contact sharing.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY | Interaction ID |
| `contact_id` | UUID | NOT NULL, FK → contacts(id) | Associated contact |
| `user_id` | UUID | NOT NULL, FK → profiles(id) | User who logged interaction |
| `interaction_type` | interaction_type | NOT NULL | Type of interaction |
| `channel` | TEXT | | Platform (WhatsApp, LinkedIn, etc.) |
| `notes` | TEXT | | Interaction notes |
| `shared_with_user_id` | UUID | FK → profiles(id) | User ID when sharing contact |
| `share_message` | TEXT | | Message when sharing contact |
| `occurred_at` | TIMESTAMPTZ | NOT NULL | When interaction occurred |
| `duration_minutes` | INTEGER | | Call/meeting duration |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |

**Indexes:**
- `idx_app_interactions_contact_id` on `(contact_id, occurred_at DESC)`
- `idx_app_interactions_user_id` on `(user_id, occurred_at DESC)`
- `idx_app_interactions_occurred_at` on `(occurred_at DESC)`
- `idx_app_interactions_type` on `(interaction_type, occurred_at DESC)`
- `idx_app_interactions_shared_with` on `(shared_with_user_id)` WHERE `shared_with_user_id IS NOT NULL`

**Constraints:**
- `duration_positive`: Duration must be > 0 if set
- `share_requires_recipient`: Contact sharing requires recipient user ID

---

#### `contact_metadata`
Extended metadata and social information for contacts.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY | Metadata ID |
| `contact_id` | UUID | NOT NULL, UNIQUE, FK → contacts(id) | Associated contact |
| `linkedin_url` | TEXT | | LinkedIn profile URL |
| `twitter_handle` | TEXT | | Twitter/X handle |
| `instagram_handle` | TEXT | | Instagram handle |
| `facebook_url` | TEXT | | Facebook profile URL |
| `location` | TEXT | | Location/city |
| `birthday` | DATE | | Birthday |
| `timezone` | TEXT | | Timezone (e.g., America/Los_Angeles) |
| `interests` | TEXT[] | | Array of interests |
| `custom_fields` | JSONB | DEFAULT '{}' | Flexible JSONB storage |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Last update timestamp |

**Indexes:**
- `idx_contact_metadata_contact_id` on `(contact_id)`
- `idx_contact_metadata_birthday` on `(birthday)` WHERE `birthday IS NOT NULL`
- `idx_contact_metadata_location` on `(location)` WHERE `location IS NOT NULL`

**Constraints:**
- `valid_twitter_handle`: Twitter handle format validation
- `valid_instagram_handle`: Instagram handle format validation

---

### Phase 3: AI Tables

#### `ai_insights`
AI-generated insights and suggestions for relationship management.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY | Insight ID |
| `contact_id` | UUID | NOT NULL, FK → contacts(id) | Associated contact |
| `user_id` | UUID | NOT NULL, FK → profiles(id) | Insight recipient |
| `insight_type` | insight_type | NOT NULL | Type of insight |
| `title` | TEXT | NOT NULL | Insight title |
| `content` | TEXT | NOT NULL | Insight content |
| `action_url` | TEXT | | Deep link to action |
| `confidence_score` | NUMERIC(5,2) | CHECK 0-100 | AI confidence (0-100) |
| `model_version` | TEXT | | AI model version |
| `is_dismissed` | BOOLEAN | DEFAULT FALSE | User dismissed flag |
| `is_acted_upon` | BOOLEAN | DEFAULT FALSE | User acted flag |
| `acted_upon_at` | TIMESTAMPTZ | | Action timestamp |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |
| `expires_at` | TIMESTAMPTZ | | Expiry for time-sensitive insights |

**Indexes:**
- `idx_ai_insights_user_id` on `(user_id, created_at DESC)`
- `idx_ai_insights_contact_id` on `(contact_id, created_at DESC)`
- `idx_ai_insights_active` on `(user_id, insight_type)` WHERE active
- `idx_ai_insights_type` on `(insight_type, created_at DESC)`
- `idx_ai_insights_expires_at` on `(expires_at)` WHERE `expires_at IS NOT NULL`

**Constraints:**
- `valid_confidence_score`: Score 0-100
- `title_not_empty`: Title required
- `content_not_empty`: Content required

---

#### `contact_embeddings`
Vector embeddings for semantic search across contacts (requires pgvector extension).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY | Embedding ID |
| `contact_id` | UUID | NOT NULL, UNIQUE, FK → contacts(id) | Associated contact |
| `user_id` | UUID | NOT NULL, FK → profiles(id) | Embedding owner |
| `embedding` | vector(1536) | | 1536-dim vector (OpenAI ada-002) |
| `content_hash` | TEXT | NOT NULL | Hash to detect changes |
| `source_text` | TEXT | | Source text (for debugging) |
| `model_version` | TEXT | DEFAULT 'text-embedding-ada-002' | Embedding model version |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Last update timestamp |

**Indexes:**
- `idx_contact_embeddings_vector` using `ivfflat (embedding vector_cosine_ops)` with lists=100
- `idx_contact_embeddings_user_id` on `(user_id)`
- `idx_contact_embeddings_content_hash` on `(content_hash)`

**Constraints:**
- `content_hash_not_empty`: Content hash required

---

#### `ai_conversation_history`
History of AI interactions for context and personalization.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY | Conversation ID |
| `user_id` | UUID | NOT NULL, FK → profiles(id) | User in conversation |
| `contact_id` | UUID | FK → contacts(id) | Associated contact (nullable) |
| `user_message` | TEXT | NOT NULL | User's message |
| `ai_response` | TEXT | NOT NULL | AI's response |
| `context_used` | JSONB | | Context provided to AI |
| `tokens_used` | INTEGER | | Token count |
| `model_version` | TEXT | | AI model version |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |

**Indexes:**
- `idx_ai_conversation_user_id` on `(user_id, created_at DESC)`
- `idx_ai_conversation_contact_id` on `(contact_id, created_at DESC)` WHERE `contact_id IS NOT NULL`

**Constraints:**
- `user_message_not_empty`: User message required
- `ai_response_not_empty`: AI response required

---

## Enums

### `subscription_tier`
```sql
CREATE TYPE subscription_tier AS ENUM ('free', 'pro');
```

### `relationship_priority`
```sql
CREATE TYPE relationship_priority AS ENUM ('low', 'medium', 'high', 'critical');
```

### `interaction_type`
```sql
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
```

### `insight_type`
```sql
CREATE TYPE insight_type AS ENUM (
    'follow_up_suggestion',
    'relationship_warning',
    'opportunity',
    'memory',
    'birthday_reminder',
    'networking_suggestion',
    'engagement_alert'
);
```

---

## Functions

### `update_updated_at_column()`
Trigger function that automatically updates the `updated_at` timestamp on row updates.

**Used by:** profiles, contacts, notes, reminders, contact_metadata, contact_embeddings

---

### `update_last_contacted_on_reminder_complete()`
Updates `contacts.last_contacted_at` when a reminder is marked as completed.

**Trigger:** `update_contact_last_contacted` on `reminders`

---

### `update_last_contacted_on_interaction()`
Updates `contacts.last_contacted_at` when a new interaction is logged.

**Trigger:** `update_contact_on_interaction` on `app_interactions`

---

### `get_contact_interaction_stats(p_contact_id UUID)`
Computes interaction statistics for a contact on demand.

**Returns:**
```sql
TABLE (
    total_interactions BIGINT,
    last_interaction_at TIMESTAMPTZ,
    first_interaction_at TIMESTAMPTZ,
    interactions_last_30_days BIGINT,
    interactions_last_90_days BIGINT,
    avg_days_between_interactions NUMERIC
)
```

**Usage:**
```sql
SELECT * FROM get_contact_interaction_stats('contact-uuid-here');
```

---

### `find_similar_contacts(p_user_id, p_query_embedding, p_limit, p_similarity_threshold)`
Vector similarity search to find contacts matching a query embedding.

**Parameters:**
- `p_user_id` UUID - User ID
- `p_query_embedding` vector(1536) - Query embedding vector
- `p_limit` INTEGER - Max results (default 10)
- `p_similarity_threshold` NUMERIC - Min similarity score (default 0.7)

**Returns:**
```sql
TABLE (
    contact_id UUID,
    similarity NUMERIC,
    first_name TEXT,
    last_name TEXT,
    company TEXT,
    job_title TEXT
)
```

---

### `generate_embedding_content(p_contact_id UUID)`
Generates searchable text content for a contact by combining contact info, recent notes, and tags.

**Returns:** TEXT

**Used for:** Creating embeddings for semantic search

---

### `cleanup_expired_insights()`
Deletes expired AI insights that haven't been acted upon (older than 30 days past expiry).

**Returns:** INTEGER (count of deleted insights)

**Usage:** Call periodically via cron job

---

### `user_has_contact_access(p_user_id UUID, p_contact_id UUID)`
Checks if a user has access to a contact (own or shared).

**Returns:** BOOLEAN

**Security:** SECURITY DEFINER

---

## Views

### `active_ai_insights`
Shows all active (non-dismissed, non-expired) AI insights with contact details.

**Columns:**
- All columns from `ai_insights`
- `first_name`, `last_name`, `company` from `contacts`

**Filter:** Only non-deleted contacts, non-dismissed insights, non-expired insights

---

## Row Level Security (RLS)

All tables have RLS enabled. Key policies:

### Profiles
- ✅ Users can view/update/insert their own profile

### Contacts
- ✅ Users can fully manage their own contacts
- ✅ Users can view contacts shared with them (via `app_interactions` with `interaction_type = 'contact_shared'`)

### Tags, Notes, Reminders
- ✅ Users can fully manage their own data

### App Interactions
- ✅ Users can manage their own interactions
- ✅ Users can view contact shares sent to them

### Contact Metadata
- ✅ Users can manage metadata for their own contacts

### AI Tables
- ✅ Users can view their own AI insights
- ✅ Users can update (dismiss/act upon) their own insights
- ✅ System can insert AI insights for users
- ✅ Users can view/manage their own embeddings and conversation history

---

## Extensions Required

### pgvector
Required for semantic search functionality with contact embeddings.

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

---

## Migration Files

1. **001_core_tables.sql** - Phase 1 MVP tables
2. **002_intelligence_tables.sql** - Phase 2 interaction tracking
3. **003_ai_tables.sql** - Phase 3 AI features
4. **004_rls_policies.sql** - Security policies

---

## Schema Design Notes

### Soft Deletes
- `contacts` table uses soft deletes (`deleted_at` column) to allow recovery
- Indexes exclude soft-deleted records for performance

### Contact Sharing
- Contact sharing is implemented via `app_interactions` table with `interaction_type = 'contact_shared'`
- Shared contacts are viewable by recipients via RLS policies

### Performance Optimizations
- Partial indexes for frequently queried subsets (active contacts, upcoming reminders, etc.)
- Vector index (ivfflat) for fast semantic search
- Automatic timestamp updates via triggers

### Extensibility
- `contact_metadata.custom_fields` (JSONB) allows flexible user-defined fields
- `ai_conversation_history.context_used` (JSONB) supports evolving AI context needs

---

**Last Updated:** 2025-10-05
**Database Version:** PostgreSQL 14+ with pgvector extension
