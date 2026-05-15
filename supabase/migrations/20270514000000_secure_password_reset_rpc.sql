-- Enable pgcrypto for password hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- RPC to reset password using custom OTP
-- This bypasses Edge Function 401 errors by running directly in the database.
CREATE OR REPLACE FUNCTION rpc_reset_password_secure(
    p_email TEXT,
    p_otp TEXT,
    p_new_password TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_is_valid BOOLEAN;
BEGIN
    -- 1. Verify OTP
    SELECT EXISTS (
        SELECT 1 FROM auth_otps 
        WHERE email = p_email 
        AND code = p_otp 
        AND expires_at > NOW()
    ) INTO v_is_valid;

    IF NOT v_is_valid THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired verification code');
    END IF;

    -- 2. Find the user
    SELECT id INTO v_user_id FROM auth.users WHERE email = p_email;
    
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'User not found');
    END IF;

    -- 3. Update the password in auth.users
    -- Supabase Auth uses bcrypt (bf) for password hashing
    UPDATE auth.users 
    SET encrypted_password = crypt(p_new_password, gen_salt('bf'))
    WHERE id = v_user_id;

    -- 4. Cleanup: Delete the OTP
    DELETE FROM auth_otps WHERE email = p_email AND code = p_otp;

    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant access to anon and authenticated roles
GRANT EXECUTE ON FUNCTION rpc_reset_password_secure TO anon;
GRANT EXECUTE ON FUNCTION rpc_reset_password_secure TO authenticated;
