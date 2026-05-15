import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { email, password, otp } = await req.json()

    if (!email || !password || !otp) {
      throw new Error('Missing required fields')
    }

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const supabase = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY!)

    // 1. Verify OTP
    const { data: isValid, error: verifyError } = await supabase.rpc('rpc_verify_custom_otp', {
      p_email: email,
      p_code: otp
    })

    if (verifyError) throw new Error(`Verification error: ${verifyError.message}`)
    if (!isValid) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired verification code' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // 2. Find user by email (more efficient than listUsers)
    // In newer Supabase JS versions, we can use admin.listUsers with a filter or search
    // But listUsers is fine for small/medium apps. Let's try to find efficiently.
    const { data: { users }, error: listError } = await supabase.auth.admin.listUsers()
    
    if (listError) throw listError

    const user = users.find(u => u.email?.toLowerCase() === email.toLowerCase())
    
    if (!user) {
      return new Response(
        JSON.stringify({ error: 'No account found with this email' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      )
    }

    // 3. Update password
    const { error: updateError } = await supabase.auth.admin.updateUserById(user.id, {
      password: password,
    })

    if (updateError) throw updateError

    // 4. Cleanup
    await supabase.from('auth_otps').delete().match({ email: email, code: otp })

    return new Response(
      JSON.stringify({ success: true }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    console.error('Reset password error:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'An unexpected error occurred' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})
