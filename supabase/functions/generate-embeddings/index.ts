// Supabase Edge Function: generate-embeddings
// Batch generates or updates embeddings for contacts

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// Helper function to generate content hash using Web Crypto API
async function generateHash(content: string): Promise<string> {
  const encoder = new TextEncoder()
  const data = encoder.encode(content)
  const hashBuffer = await crypto.subtle.digest('SHA-256', data)
  const hashArray = Array.from(new Uint8Array(hashBuffer))
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('')
  return hashHex
}

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
    const { contactId, batchSize = 50 } = await req.json()

    let contactIds: string[] = []

    if (contactId) {
      // Single contact
      contactIds = [contactId]
    } else {
      // Batch: Get contacts that need embedding updates
      const { data: contacts } = await supabase
        .from('contacts')
        .select('id')
        .eq('user_id', userId)
        .is('deleted_at', null)
        .limit(batchSize)

      contactIds = contacts?.map((c) => c.id) || []
    }

    const results = {
      processed: 0,
      created: 0,
      updated: 0,
      skipped: 0,
      errors: [] as string[],
    }

    // Process each contact
    for (const cid of contactIds) {
      try {
        // Generate embedding content
        const { data: content } = await supabase.rpc('generate_embedding_content', {
          p_contact_id: cid,
        })

        if (!content) {
          results.skipped++
          continue
        }

        // Generate hash of content
        const contentHash = await generateHash(content)

        // Check if embedding already exists with same hash
        const { data: existing } = await supabase
          .from('contact_embeddings')
          .select('id, content_hash')
          .eq('contact_id', cid)
          .single()

        if (existing && existing.content_hash === contentHash) {
          results.skipped++
          continue
        }

        // Generate embedding
        const embedding = await generateEmbedding(content)

        // Upsert embedding
        const { error: upsertError } = await supabase
          .from('contact_embeddings')
          .upsert({
            contact_id: cid,
            user_id: userId,
            embedding,
            content_hash: contentHash,
            source_text: content.substring(0, 500), // Store first 500 chars
          })

        if (upsertError) {
          results.errors.push(`${cid}: ${upsertError.message}`)
        } else {
          if (existing) {
            results.updated++
          } else {
            results.created++
          }
          results.processed++
        }
      } catch (error) {
        results.errors.push(`${cid}: ${error.message}`)
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        results,
      }),
      {
        headers: { 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('Generate embeddings error:', error)
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
