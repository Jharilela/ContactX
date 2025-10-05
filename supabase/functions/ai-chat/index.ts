// Supabase Edge Function: ai-chat
// AI-powered chat about contacts with context

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
    const { message, contactId } = await req.json()

    if (!message) {
      return new Response(JSON.stringify({ error: 'Message is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Build context
    let context: any = {}

    if (contactId) {
      // Get contact details
      const { data: contact } = await supabase
        .from('contacts')
        .select('*')
        .eq('id', contactId)
        .eq('user_id', userId)
        .single()

      if (contact) {
        context.contact = contact

        // Get recent interactions
        const { data: interactions } = await supabase
          .from('app_interactions')
          .select('*')
          .eq('contact_id', contactId)
          .order('occurred_at', { ascending: false })
          .limit(5)

        context.interactions = interactions

        // Get recent notes
        const { data: notes } = await supabase
          .from('notes')
          .select('*')
          .eq('contact_id', contactId)
          .order('created_at', { ascending: false })
          .limit(3)

        context.notes = notes
      }
    } else {
      // Get general stats
      const { data: stats } = await supabase.rpc('get_dashboard_stats', {
        p_user_id: userId,
      })

      context.stats = stats
    }

    // Get recent conversation history for context
    const { data: history } = await supabase
      .from('ai_conversation_history')
      .select('user_message, ai_response')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(5)

    // Build AI prompt
    const systemPrompt = `You are a helpful AI assistant for ContactX, a personal CRM app.
Help the user manage and understand their contacts and relationships.
Be concise, actionable, and friendly.
${contactId ? `You are discussing ${context.contact?.first_name} ${context.contact?.last_name || ''}.` : 'You are discussing the user\'s overall contact management.'}`

    const messages = [
      { role: 'system', content: systemPrompt },
      ...(history?.reverse().flatMap((h) => [
        { role: 'user', content: h.user_message },
        { role: 'assistant', content: h.ai_response },
      ]) || []),
      {
        role: 'user',
        content: `Context: ${JSON.stringify(context)}\n\nUser question: ${message}`,
      },
    ]

    // Call OpenAI
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: 'gpt-4',
        messages,
        temperature: 0.7,
        max_tokens: 300,
      }),
    })

    if (!response.ok) {
      throw new Error(`OpenAI API error: ${response.statusText}`)
    }

    const data = await response.json()
    const aiResponse = data.choices[0].message.content
    const tokensUsed = data.usage.total_tokens

    // Save conversation to history
    await supabase.from('ai_conversation_history').insert({
      user_id: userId,
      contact_id: contactId || null,
      user_message: message,
      ai_response: aiResponse,
      context_used: context,
      tokens_used: tokensUsed,
      model_version: 'gpt-4',
    })

    return new Response(
      JSON.stringify({
        success: true,
        response: aiResponse,
        tokensUsed,
      }),
      {
        headers: { 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('AI chat error:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    )
  }
})
