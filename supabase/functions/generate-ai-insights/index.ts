// Supabase Edge Function: generate-ai-insights
// Analyzes contacts and generates AI-powered relationship insights

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface Contact {
  id: string
  first_name: string
  last_name: string
  company: string
  job_title: string
  relationship_priority: string
  last_contacted_at: string | null
  how_we_met: string
}

serve(async (req) => {
  try {
    // Only allow POST requests
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Get user from auth header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Create Supabase client
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: {
        persistSession: false,
      },
    })

    // Get user from JWT
    const jwt = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt)

    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const userId = user.id

    // Parse request body
    const { contactId, insightTypes = ['follow_up_suggestion', 'relationship_warning'] } = await req.json()

    // Get contact details with interaction stats
    const { data: contact, error: contactError } = await supabase
      .from('contacts')
      .select(`
        id,
        first_name,
        last_name,
        company,
        job_title,
        relationship_priority,
        last_contacted_at,
        how_we_met
      `)
      .eq('id', contactId)
      .eq('user_id', userId)
      .is('deleted_at', null)
      .single()

    if (contactError || !contact) {
      return new Response(JSON.stringify({ error: 'Contact not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Get interaction stats
    const { data: stats } = await supabase.rpc('get_contact_interaction_stats', {
      p_contact_id: contactId,
    })

    // Get recent notes
    const { data: notes } = await supabase
      .from('notes')
      .select('content, created_at')
      .eq('contact_id', contactId)
      .order('created_at', { ascending: false })
      .limit(3)

    // Generate AI insights using OpenAI
    const insights = await generateInsights(contact, stats?.[0], notes || [], insightTypes)

    // Store insights in database
    const insertedInsights = []
    for (const insight of insights) {
      const { data, error } = await supabase
        .from('ai_insights')
        .insert({
          contact_id: contactId,
          user_id: userId,
          insight_type: insight.type,
          title: insight.title,
          content: insight.content,
          confidence_score: insight.confidence,
          model_version: 'gpt-4',
        })
        .select()
        .single()

      if (!error && data) {
        insertedInsights.push(data)
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        insights: insertedInsights,
      }),
      {
        headers: { 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('Error generating insights:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    )
  }
})

async function generateInsights(
  contact: Contact,
  stats: any,
  notes: any[],
  insightTypes: string[]
): Promise<Array<{ type: string; title: string; content: string; confidence: number }>> {
  const daysSinceContact = contact.last_contacted_at
    ? Math.floor((Date.now() - new Date(contact.last_contacted_at).getTime()) / (1000 * 60 * 60 * 24))
    : null

  const prompt = `You are an AI relationship manager assistant. Analyze this contact and provide actionable insights.

Contact Information:
- Name: ${contact.first_name} ${contact.last_name || ''}
- Company: ${contact.company || 'Unknown'}
- Title: ${contact.job_title || 'Unknown'}
- Priority: ${contact.relationship_priority}
- Days since last contact: ${daysSinceContact ?? 'Never contacted'}
- Total interactions: ${stats?.total_interactions || 0}
- How we met: ${contact.how_we_met || 'Not specified'}

Recent Notes:
${notes.map((n, i) => `${i + 1}. ${n.content}`).join('\n') || 'No recent notes'}

Generate ${insightTypes.length} insight(s) from these types: ${insightTypes.join(', ')}

For each insight, provide:
1. A clear, actionable title (max 60 chars)
2. Specific content explaining why and what action to take (2-3 sentences)
3. Confidence score (0-100)

Return as JSON array with format:
[{"type": "follow_up_suggestion", "title": "...", "content": "...", "confidence": 85}]`

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: 'gpt-4',
      messages: [{ role: 'user', content: prompt }],
      temperature: 0.7,
      max_tokens: 500,
    }),
  })

  if (!response.ok) {
    throw new Error(`OpenAI API error: ${response.statusText}`)
  }

  const data = await response.json()
  const content = data.choices[0].message.content

  // Parse JSON from response
  const jsonMatch = content.match(/\[[\s\S]*\]/)
  if (jsonMatch) {
    return JSON.parse(jsonMatch[0])
  }

  // Fallback if JSON parsing fails
  return []
}
