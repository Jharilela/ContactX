// Supabase Edge Function: semantic-search
// Performs semantic search across contacts using vector embeddings

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    })

    const jwt = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt)

    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const userId = user.id
    const { query, limit = 10, similarityThreshold = 0.7 } = await req.json()

    if (!query || typeof query !== 'string') {
      return new Response(JSON.stringify({ error: 'Query is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Generate embedding for query using OpenAI
    const embedding = await generateEmbedding(query)

    // Perform vector similarity search
    const { data: results, error: searchError } = await supabase.rpc('find_similar_contacts', {
      p_user_id: userId,
      p_query_embedding: embedding,
      p_limit: limit,
      p_similarity_threshold: similarityThreshold,
    })

    if (searchError) {
      throw new Error(`Search error: ${searchError.message}`)
    }

    return new Response(
      JSON.stringify({
        success: true,
        query,
        results: results || [],
        count: results?.length || 0,
      }),
      {
        headers: { 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('Semantic search error:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    )
  }
})

async function generateEmbedding(text: string): Promise<number[]> {
  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: 'text-embedding-ada-002',
      input: text,
    }),
  })

  if (!response.ok) {
    throw new Error(`OpenAI API error: ${response.statusText}`)
  }

  const data = await response.json()
  return data.data[0].embedding
}
