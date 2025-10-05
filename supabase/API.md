# ContactX API Documentation

Complete API reference for integrating with ContactX backend services.

**Base URL:** `https://draafcdyzitljnztrcff.supabase.co`

---

## Table of Contents

1. [Authentication](#authentication)
2. [RPC Functions](#rpc-functions)
3. [Edge Functions](#edge-functions)
4. [Direct Table Access](#direct-table-access)
5. [Error Handling](#error-handling)
6. [Rate Limits](#rate-limits)

---

## Authentication

All API requests require authentication using Supabase Auth JWT tokens.

### Getting an Auth Token

```typescript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://draafcdyzitljnztrcff.supabase.co',
  'YOUR_ANON_KEY'
)

// Sign in
const { data, error } = await supabase.auth.signInWithPassword({
  email: 'user@example.com',
  password: 'password'
})

const accessToken = data.session?.access_token
```

### Using the Token

**For RPC Functions:**
```typescript
const { data, error } = await supabase.rpc('function_name', {
  // parameters
})
```

**For Edge Functions:**
```typescript
const response = await fetch(
  'https://draafcdyzitljnztrcff.supabase.co/functions/v1/function-name',
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ /* data */ })
  }
)
```

---

## RPC Functions

Call via: `supabase.rpc('function_name', { params })`

### 1. Search Contacts

**Function:** `search_contacts`

**Description:** Full-text search across contacts with advanced filtering.

**Parameters:**
```typescript
{
  p_user_id: string           // Required: User UUID
  p_query?: string            // Optional: Search text
  p_tags?: string[]           // Optional: Filter by tag UUIDs
  p_priority?: string[]       // Optional: ['low','medium','high','critical']
  p_favorites_only?: boolean  // Optional: Default false
  p_limit?: number            // Optional: Default 50
  p_offset?: number           // Optional: Default 0
}
```

**Response:**
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

**Example:**
```typescript
const { data: contacts, error } = await supabase.rpc('search_contacts', {
  p_user_id: userId,
  p_query: 'john',
  p_priority: ['high', 'critical'],
  p_limit: 20
})
```

---

### 2. Get Contacts Needing Follow-up

**Function:** `get_contacts_needing_followup`

**Description:** Returns high-priority contacts that haven't been contacted recently.

**Parameters:**
```typescript
{
  p_user_id: string         // Required: User UUID
  p_days_threshold?: number // Optional: Days since contact (default: 30)
  p_limit?: number          // Optional: Default 20
}
```

**Response:**
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

**Example:**
```typescript
const { data, error } = await supabase.rpc('get_contacts_needing_followup', {
  p_user_id: userId,
  p_days_threshold: 45,
  p_limit: 10
})
```

---

### 3. Get Contact Timeline

**Function:** `get_contact_timeline`

**Description:** Retrieves complete timeline of interactions and notes for a specific contact.

**Parameters:**
```typescript
{
  p_user_id: string    // Required: User UUID
  p_contact_id: string // Required: Contact UUID
  p_limit?: number     // Optional: Default 50
}
```

**Response:**
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

**Example:**
```typescript
const { data, error } = await supabase.rpc('get_contact_timeline', {
  p_user_id: userId,
  p_contact_id: contactId,
  p_limit: 100
})
```

---

### 4. Get Dashboard Stats

**Function:** `get_dashboard_stats`

**Description:** Returns user's contact statistics for dashboard overview.

**Parameters:**
```typescript
{
  p_user_id: string // Required: User UUID
}
```

**Response:**
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

**Example:**
```typescript
const { data, error } = await supabase.rpc('get_dashboard_stats', {
  p_user_id: userId
})
```

---

### 5. Share Contact With User

**Function:** `share_contact_with_user`

**Description:** Share a contact with another user via email.

**Parameters:**
```typescript
{
  p_user_id: string         // Required: Your user UUID
  p_contact_id: string      // Required: Contact UUID to share
  p_recipient_email: string // Required: Recipient's email
  p_message?: string        // Optional: Share message
}
```

**Response:**
```typescript
string // Interaction UUID
```

**Example:**
```typescript
const { data: interactionId, error } = await supabase.rpc('share_contact_with_user', {
  p_user_id: userId,
  p_contact_id: contactId,
  p_recipient_email: 'friend@example.com',
  p_message: 'Great person to connect with!'
})
```

**Errors:**
- "Contact not found or access denied"
- "Recipient user not found with email: {email}"
- "Cannot share contact with yourself"

---

### 6. Bulk Import Contacts

**Function:** `bulk_import_contacts`

**Description:** Import multiple contacts at once.

**Parameters:**
```typescript
{
  p_user_id: string  // Required: User UUID
  p_contacts: {      // Required: Array of contacts
    first_name: string
    last_name?: string
    phone_number?: string
    email?: string
    company?: string
    job_title?: string
  }[]
}
```

**Response:**
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

**Example:**
```typescript
const { data, error } = await supabase.rpc('bulk_import_contacts', {
  p_user_id: userId,
  p_contacts: [
    {
      first_name: 'John',
      last_name: 'Doe',
      email: 'john@example.com',
      company: 'Acme Inc'
    },
    {
      first_name: 'Jane',
      phone_number: '+1234567890'
    }
  ]
})

console.log(`Imported: ${data.imported_count}, Skipped: ${data.skipped_count}`)
```

**Note:** Automatically skips duplicates based on phone or email matching.

---

### 7. Get Upcoming Reminders

**Function:** `get_upcoming_reminders`

**Description:** Get upcoming reminders for the next N days.

**Parameters:**
```typescript
{
  p_user_id: string    // Required: User UUID
  p_days_ahead?: number // Optional: Days to look ahead (default: 7)
  p_limit?: number     // Optional: Default 50
}
```

**Response:**
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

**Example:**
```typescript
const { data, error } = await supabase.rpc('get_upcoming_reminders', {
  p_user_id: userId,
  p_days_ahead: 14
})
```

---

### 8. Get Contact Interaction Stats

**Function:** `get_contact_interaction_stats`

**Description:** Get detailed interaction statistics for a contact.

**Parameters:**
```typescript
{
  p_contact_id: string // Required: Contact UUID
}
```

**Response:**
```typescript
{
  total_interactions: number
  last_interaction_at: string
  first_interaction_at: string
  interactions_last_30_days: number
  interactions_last_90_days: number
  avg_days_between_interactions: number
}
```

**Example:**
```typescript
const { data, error } = await supabase.rpc('get_contact_interaction_stats', {
  p_contact_id: contactId
})
```

---

## Edge Functions

Base URL: `https://draafcdyzitljnztrcff.supabase.co/functions/v1`

### Authentication Header

All Edge Functions require:
```typescript
headers: {
  'Authorization': `Bearer ${accessToken}`,
  'Content-Type': 'application/json'
}
```

---

### 1. Generate AI Insights

**Endpoint:** `POST /functions/v1/generate-ai-insights`

**Description:** Analyzes a contact and generates AI-powered relationship insights.

**Request Body:**
```typescript
{
  contactId: string           // Required: Contact UUID
  insightTypes?: string[]     // Optional: Default ['follow_up_suggestion', 'relationship_warning']
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

**Example:**
```typescript
const response = await fetch(
  'https://draafcdyzitljnztrcff.supabase.co/functions/v1/generate-ai-insights',
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      contactId: 'uuid-here',
      insightTypes: ['follow_up_suggestion', 'opportunity']
    })
  }
)

const { insights } = await response.json()
```

---

### 2. Semantic Search

**Endpoint:** `POST /functions/v1/semantic-search`

**Description:** Natural language semantic search across contacts.

**Request Body:**
```typescript
{
  query: string                // Required: Natural language query
  limit?: number               // Optional: Default 10
  similarityThreshold?: number // Optional: 0-1, Default 0.7
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

**Example:**
```typescript
const response = await fetch(
  'https://draafcdyzitljnztrcff.supabase.co/functions/v1/semantic-search',
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      query: 'software engineers in San Francisco who like AI',
      limit: 5
    })
  }
)

const { results } = await response.json()
```

**Example Queries:**
- "investors in fintech"
- "designers I met at conferences"
- "people interested in blockchain"
- "contacts in New York who work in marketing"

---

### 3. Generate Embeddings

**Endpoint:** `POST /functions/v1/generate-embeddings`

**Description:** Generate or update vector embeddings for semantic search.

**Request Body:**
```typescript
{
  contactId?: string  // Optional: Single contact UUID
  batchSize?: number  // Optional: Batch size if no contactId (default: 50)
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

**Example - Single Contact:**
```typescript
const response = await fetch(
  'https://draafcdyzitljnztrcff.supabase.co/functions/v1/generate-embeddings',
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      contactId: 'uuid-here'
    })
  }
)
```

**Example - Batch:**
```typescript
const response = await fetch(
  'https://draafcdyzitljnztrcff.supabase.co/functions/v1/generate-embeddings',
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      batchSize: 100
    })
  }
)
```

---

### 4. AI Chat

**Endpoint:** `POST /functions/v1/ai-chat`

**Description:** Conversational AI about contacts with context.

**Request Body:**
```typescript
{
  message: string      // Required: User's message
  contactId?: string   // Optional: Specific contact context
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

**Example - General:**
```typescript
const response = await fetch(
  'https://draafcdyzitljnztrcff.supabase.co/functions/v1/ai-chat',
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: 'Who should I follow up with this week?'
    })
  }
)

const { response: aiResponse } = await response.json()
```

**Example - Contact-Specific:**
```typescript
const response = await fetch(
  'https://draafcdyzitljnztrcff.supabase.co/functions/v1/ai-chat',
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: 'What should I talk to them about?',
      contactId: 'contact-uuid'
    })
  }
)
```

---

## Direct Table Access

Access tables directly using Supabase client. RLS policies enforce security.

### Example - Get Contacts

```typescript
const { data: contacts, error } = await supabase
  .from('contacts')
  .select('*')
  .eq('user_id', userId)
  .is('deleted_at', null)
  .order('created_at', { ascending: false })
```

### Example - Create Contact

```typescript
const { data, error } = await supabase
  .from('contacts')
  .insert({
    user_id: userId,
    first_name: 'John',
    last_name: 'Doe',
    email: 'john@example.com',
    company: 'Acme Inc'
  })
  .select()
  .single()
```

### Example - Update Contact

```typescript
const { data, error } = await supabase
  .from('contacts')
  .update({
    relationship_priority: 'high',
    is_favorite: true
  })
  .eq('id', contactId)
  .select()
```

### Example - Add Note

```typescript
const { data, error } = await supabase
  .from('notes')
  .insert({
    user_id: userId,
    contact_id: contactId,
    content: 'Great conversation about AI startups'
  })
```

### Example - Log Interaction

```typescript
const { data, error } = await supabase
  .from('app_interactions')
  .insert({
    user_id: userId,
    contact_id: contactId,
    interaction_type: 'coffee',
    channel: 'In-person',
    notes: 'Discussed collaboration opportunities',
    occurred_at: new Date().toISOString(),
    duration_minutes: 60
  })
```

---

## Error Handling

### Error Response Format

```typescript
{
  error: string  // Error message
}
```

### HTTP Status Codes

- `200` - Success
- `400` - Bad Request (invalid parameters)
- `401` - Unauthorized (missing/invalid JWT)
- `403` - Forbidden (RLS policy violation)
- `404` - Not Found (resource doesn't exist)
- `405` - Method Not Allowed (use POST)
- `500` - Internal Server Error

### Example Error Handling

```typescript
const response = await fetch(endpoint, options)

if (!response.ok) {
  const { error } = await response.json()
  console.error('API Error:', error)
  throw new Error(error)
}

const data = await response.json()
```

---

## Rate Limits

### Current Limits

- **RPC Functions:** No hard limit (database connection pool limited)
- **Edge Functions:** 500 requests/minute per user
- **OpenAI API:** Subject to your OpenAI account limits

### Best Practices

1. **Cache results** when possible (especially `get_dashboard_stats`)
2. **Use pagination** for large datasets
3. **Batch operations** instead of individual calls
4. **Implement retry logic** with exponential backoff
5. **Call AI functions asynchronously** (don't block UI)

---

## SDK Setup

### TypeScript/JavaScript

```bash
npm install @supabase/supabase-js
```

```typescript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://draafcdyzitljnztrcff.supabase.co',
  'YOUR_ANON_KEY'
)
```

### React Native

```bash
npm install @supabase/supabase-js
npm install react-native-url-polyfill
```

```typescript
import 'react-native-url-polyfill/auto'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://draafcdyzitljnztrcff.supabase.co',
  'YOUR_ANON_KEY'
)
```

---

## Environment Variables

Required for Edge Functions (set in Supabase dashboard):

```bash
OPENAI_API_KEY=sk-...          # Your OpenAI API key
SUPABASE_URL=https://...       # Auto-provided
SUPABASE_SERVICE_ROLE_KEY=...  # Auto-provided
```

---

## Support

For issues or questions:
- Check [SCHEMA.md](./SCHEMA.md) for database schema
- Check [FUNCTIONS.md](./FUNCTIONS.md) for detailed function docs
- GitHub Issues: https://github.com/yourusername/contactx/issues

---

**API Version:** 1.0
**Last Updated:** 2025-10-05
**Base URL:** `https://draafcdyzitljnztrcff.supabase.co`
