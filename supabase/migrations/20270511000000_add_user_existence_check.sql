-- RPC to check if a user exists in auth.users
-- This is used for validation during signup and forgot password flows.

CREATE OR REPLACE FUNCTION rpc_check_user_exists(p_email TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (SELECT 1 FROM auth.users WHERE email = p_email);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to both authenticated and anon users (for signup/forgot password)
GRANT EXECUTE ON FUNCTION rpc_check_user_exists TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_check_user_exists TO anon;
