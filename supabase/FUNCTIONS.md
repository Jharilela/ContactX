# ContactX Functions Documentation

Complete documentation for RPC Functions and Edge Functions in ContactX.

---

## RPC Functions (Database Functions)

RPC functions are called directly from the frontend via `supabase.rpc()`. They run in the database and respect Row Level Security (RLS) policies.

### 1. `search_contacts`

Full-text search contacts with multiple filters.

**Parameters:**
```typescript
{
  p_user_id: string          // User ID (required)
  p_query?: string           // Search text (searches name, email, company, job title)
  p_tags?: string[]          // Filter by tag IDs
  p_priority?: string[]      // Filter by priority ('low'|'medium'|'high'|'critical')
  p_favorites_only?: boolean // Show only favorites (default: false)
  p_limit?: number           // Results limit (default: 50)
  p_offset?: number          // Pagination offset (default: 0)
}
```

**Returns:**
```typescript
{
  id: string
  first_name: string
  last_name: string
  email: string
  phone_number: string
  company: string
  job_title: string
  avatar_url: string
  relationship_priority: 'low' | 'medium' | 'high' | 'critical'
  is_favorite: boolean
  last_contacted_at: string
  created_at: string
  interaction_count: number
}[]
```

**Usage:**
```typescript
const { data, error } = await supabase.rpc('search_contacts', {
  p_user_id: userId,
  p_query: 'john',
  p_favorites_only: true,
  p_limit: 20
})
```

---

### 2. `get_contacts_needing_followup`

Get high-priority contacts that haven't been contacted recently.

**Parameters:**
```typescript
{
  p_user_id: string         // User ID (required)
  p_days_threshold?: number // Days since last contact (default: 30)
  p_limit?: number          // Results limit (default: 20)
}
```

**Returns:**
```typescript
{
  id: string
  first_name: string
  last_name: string
  company: string
  avatar_url: string
  relationship_priority: 'high' | 'critical'
  last_contacted_at: string | null
  days_since_contact: number
  total_interactions: number
}[]
```

**Usage:**
```typescript
const { data, error } = await supabase.rpc('get_contacts_needing_followup', {
  p_user_id: userId,
  p_days_threshold: 45
})
```

---

### 3. `get_contact_timeline`

Get complete timeline of interactions and notes for a contact.

**Parameters:**
```typescript
{
  p_user_id: string    // User ID (required)
  p_contact_id: string // Contact ID (required)
  p_limit?: number     // Results limit (default: 50)
}
```

**Returns:**
```typescript
{
  id: string
  type: 'interaction' | 'note'
  content: string
  interaction_type?: 'call' | 'message' | 'email' | 'meeting' | 'social' | 'coffee' | 'contact_shared' | 'other'
  channel?: string
  duration_minutes?: number
  occurred_at: string
  created_at: string
}[]
```

**Usage:**
```typescript
const { data, error } = await supabase.rpc('get_contact_timeline', {
  p_user_id: userId,
  p_contact_id: contactId
})
```

---

### 4. `get_dashboard_stats`

Get user's contact statistics for dashboard overview.

**Parameters:**
```typescript
{
  p_user_id: string // User ID (required)
}
```

**Returns:**
```typescript
{
  total_contacts: number
  contacts_added_this_month: number
  critical_priority_count: number
  high_priority_count: number
  favorites_count: number
  needs_followup_count: number
  total_interactions_this_month: number
  active_reminders_count: number
}
```

**Usage:**
```typescript
const { data, error } = await supabase.rpc('get_dashboard_stats', {
  p_user_id: userId
})
```

---

### 5. `share_contact_with_user`

Share a contact with another user by email.

**Parameters:**
```typescript
{
  p_user_id: string        // User ID (required)
  p_contact_id: string     // Contact to share (required)
  p_recipient_email: string // Recipient's email (required)
  p_message?: string       // Optional message
}
```

**Returns:**
```typescript
string // Interaction ID
```

**Usage:**
```typescript
const { data, error } = await supabase.rpc('share_contact_with_user', {
  p_user_id: userId,
  p_contact_id: contactId,
  p_recipient_email: 'friend@example.com',
  p_message: 'You should meet this person!'
})
```

**Errors:**
- "Contact not found or access denied"
- "Recipient user not found with email: {email}"
- "Cannot share contact with yourself"

---

### 6. `bulk_import_contacts`

Bulk import contacts from JSON array.

**Parameters:**
```typescript
{
  p_user_id: string  // User ID (required)
  p_contacts: {      // Array of contacts (required)
    first_name: string
    last_name?: string
    phone_number?: string
    email?: string
    company?: string
    job_title?: string
  }[]
}
```

**Returns:**
```typescript
{
  success: boolean
  imported_count: number
  skipped_count: number
  errors: {
    contact: object
    error: string
  }[]
}
```

**Usage:**
```typescript
const { data, error } = await supabase.rpc('bulk_import_contacts', {
  p_user_id: userId,
  p_contacts: [
    { first_name: 'John', last_name: 'Doe', email: 'john@example.com' },
    { first_name: 'Jane', phone_number: '+1234567890' }
  ]
})
```

**Note:** Automatically skips duplicates based on phone or email.

---

### 7. `get_upcoming_reminders`

Get upcoming reminders for the next N days.

**Parameters:**
```typescript
{
  p_user_id: string   // User ID (required)
  p_days_ahead?: number // Days to look ahead (default: 7)
  p_limit?: number    // Results limit (default: 50)
}
```

**Returns:**
```typescript
{
  id: string
  contact_id: string
  contact_name: string
  contact_avatar_url: string
  title: string
  description: string
  remind_at: string
  is_ai_generated: boolean
  created_at: string
}[]
```

**Usage:**
```typescript
const { data, error } = await supabase.rpc('get_upcoming_reminders', {
  p_user_id: userId,
  p_days_ahead: 14
})
```

---

## Edge Functions

Edge Functions are serverless functions for complex operations. Called via HTTP POST with JWT authentication.

### Authentication

All Edge Functions require authorization:

```typescript
const { data: { session } } = await supabase.auth.getSession()

const response = await fetch(`${SUPABASE_URL}/functions/v1/{function-name}`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${session.access_token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({ /* params */ })
})
```

---

### 1. `generate-ai-insights`

Analyzes a contact and generates AI-powered relationship insights.

**Endpoint:** `POST /functions/v1/generate-ai-insights`

**Request Body:**
```typescript
{
  contactId: string           // Contact to analyze (required)
  insightTypes?: string[]     // Types to generate (default: ['follow_up_suggestion', 'relationship_warning'])
}
```

**Response:**
```typescript
{
  success: boolean
  insights: {
    id: string
    contact_id: string
    user_id: string
    insight_type: string
    title: string
    content: string
    confidence_score: number
    model_version: string
    created_at: string
  }[]
}
```

**Insight Types:**
- `follow_up_suggestion` - When and why to reach out
- `relationship_warning` - Relationships at risk
- `opportunity` - Networking opportunities
- `memory` - Important details to remember
- `birthday_reminder` - Birthday notifications
- `networking_suggestion` - Introduction suggestions
- `engagement_alert` - Engagement level alerts

**Usage:**
```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/generate-ai-insights`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${session.access_token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    contactId: 'uuid-here',
    insightTypes: ['follow_up_suggestion', 'opportunity']
  })
})

const { insights } = await response.json()
```

**Environment Variables Required:**
- `OPENAI_API_KEY`

---

### 2. `semantic-search`

Performs semantic search across contacts using natural language.

**Endpoint:** `POST /functions/v1/semantic-search`

**Request Body:**
```typescript
{
  query: string               // Natural language query (required)
  limit?: number              // Max results (default: 10)
  similarityThreshold?: number // Min similarity 0-1 (default: 0.7)
}
```

**Response:**
```typescript
{
  success: boolean
  query: string
  results: {
    contact_id: string
    similarity: number
    first_name: string
    last_name: string
    company: string
    job_title: string
  }[]
  count: number
}
```

**Usage:**
```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/semantic-search`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${session.access_token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    query: 'software engineers in San Francisco who like AI',
    limit: 5
  })
})

const { results } = await response.json()
```

**Example Queries:**
- "investors in fintech"
- "designers I met at conferences"
- "people interested in blockchain"
- "contacts in New York who work in marketing"

**Environment Variables Required:**
- `OPENAI_API_KEY`

---

### 3. `generate-embeddings`

Batch generates or updates vector embeddings for contacts.

**Endpoint:** `POST /functions/v1/generate-embeddings`

**Request Body:**
```typescript
{
  contactId?: string  // Single contact (optional)
  batchSize?: number  // Batch size if no contactId (default: 50)
}
```

**Response:**
```typescript
{
  success: boolean
  results: {
    processed: number
    created: number
    updated: number
    skipped: number
    errors: string[]
  }
}
```

**Usage:**

Single contact:
```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/generate-embeddings`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${session.access_token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    contactId: 'uuid-here'
  })
})
```

Batch processing:
```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/generate-embeddings`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${session.access_token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    batchSize: 100
  })
})
```

**When to call:**
- After creating a new contact
- After updating contact info, notes, or tags
- Periodically via cron job for batch updates

**Environment Variables Required:**
- `OPENAI_API_KEY`

---

### 4. `ai-chat`

AI-powered chat about contacts with context-aware responses.

**Endpoint:** `POST /functions/v1/ai-chat`

**Request Body:**
```typescript
{
  message: string      // User's message (required)
  contactId?: string   // Specific contact context (optional)
}
```

**Response:**
```typescript
{
  success: boolean
  response: string
  tokensUsed: number
}
```

**Usage:**

General questions:
```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/ai-chat`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${session.access_token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    message: 'Who should I follow up with this week?'
  })
})

const { response: aiResponse } = await response.json()
```

Contact-specific questions:
```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/ai-chat`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${session.access_token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    message: 'What should I talk to them about?',
    contactId: 'uuid-here'
  })
})
```

**Example Questions:**
- "Who are my most important contacts?"
- "When did I last talk to John?"
- "Suggest someone to introduce me to investors"
- "What do I know about Sarah?"
- "Who needs a follow-up this week?"

**Features:**
- Maintains conversation history (last 5 messages)
- Context-aware based on contact data
- Saves all conversations to `ai_conversation_history`

**Environment Variables Required:**
- `OPENAI_API_KEY`

---

## Environment Variables

Set these in your Supabase project settings:

```bash
OPENAI_API_KEY=sk-...          # OpenAI API key for AI features
SUPABASE_URL=https://...       # Auto-provided
SUPABASE_SERVICE_ROLE_KEY=...  # Auto-provided
```

---

## Error Handling

All functions return errors in this format:

```typescript
{
  error: string  // Error message
}
```

Common HTTP status codes:
- `400` - Bad request (missing/invalid parameters)
- `401` - Unauthorized (invalid/missing JWT)
- `404` - Not found (contact doesn't exist)
- `405` - Method not allowed (use POST)
- `500` - Server error

---

## Performance Notes

**RPC Functions:**
- Run in-database (very fast)
- Respect RLS policies
- Use for: CRUD, queries, aggregations

**Edge Functions:**
- Cold start: ~100-500ms
- Warm: ~50-100ms
- Use for: AI operations, external APIs, heavy processing

**Best Practices:**
1. Use RPC for data operations
2. Use Edge Functions for AI/external APIs
3. Call `generate-embeddings` asynchronously (don't block UI)
4. Cache `get_dashboard_stats` results client-side
5. Implement pagination for large result sets

---

**Last Updated:** 2025-10-05
