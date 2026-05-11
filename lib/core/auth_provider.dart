import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  User? _user;
  Session? _session;
  bool _loading = true;

  User? get user => _user;
  Session? get session => _session;
  bool get loading => _loading;
  String? _currentRole;
  Map<String, dynamic>? _currentPermissions; // Added field

  String? get currentRole => _currentRole;
  Map<String, dynamic>? get currentPermissions => _currentPermissions; // Added getter

  void setCurrentRole(String? role, {Map<String, dynamic>? permissions}) { // Modified signature
    _currentRole = role;
    _currentPermissions = permissions; // Set permissions
    notifyListeners();
  }

  Future<void> fetchAndSetRole(String shopId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Check if user is shop owner
      final shopRes = await _supabase
          .from('shops')
          .select('owner_user_id')
          .eq('id', shopId)
          .maybeSingle();

      if (shopRes != null && shopRes['owner_user_id'] == user.id) {
        // Owner gets full permissions bypass or we fetch the Owner role permissions
        final ownerRoleRes = await _supabase
            .from('roles')
            .select('permissions')
            .eq('name', 'Owner')
            .maybeSingle();
        
        setCurrentRole('Owner', permissions: ownerRoleRes?['permissions']); // Modified call
        return;
      }

      // 2. Check shop_members for assigned role
      final memberRes = await _supabase
          .from('shop_members')
          .select('roles(name, permissions)') // Modified select
          .eq('shop_id', shopId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (memberRes != null && memberRes['roles'] != null) {
        final roleData = memberRes['roles'] as Map<String, dynamic>; // Extract role data
        setCurrentRole(roleData['name'], permissions: roleData['permissions']); // Modified call
      } else {
        setCurrentRole(null); // This will also clear permissions
      }
    } catch (e) {
      debugPrint('Error fetching role: $e');
      setCurrentRole(null); // This will also clear permissions
    }
  }

  AuthProvider() {
    _initializeAuth();
  }

  void _initializeAuth() {
    _session = _supabase.auth.currentSession;
    _user = _session?.user;
    _loading = false;
    notifyListeners();

    _supabase.auth.onAuthStateChange.listen((data) {
      _session = data.session;
      _user = data.session?.user;
      notifyListeners();
    });
  }

  Future<AuthResponse> signUp(String email, String password) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
    );
  }

  Future<void> sendCustomOTP(String email, {bool isSignup = true}) async {
    await _supabase.rpc(
      'rpc_send_custom_otp',
      params: {
        'p_email': email,
        'p_type': isSignup ? 'otp-signup' : 'otp-reset',
      },
    );
  }

  Future<void> sendCustomOTPForDeletion(String email) async {
    await _supabase.rpc(
      'rpc_send_custom_otp',
      params: {
        'p_email': email,
        'p_type': 'otp-delete-shop',
      },
    );
  }

  Future<void> sendOwnershipTransferOTP(String email) async {
    await _supabase.rpc(
      'rpc_send_custom_otp',
      params: {
        'p_email': email,
        'p_type': 'otp-ownership-transfer',
      },
    );
  }

  Future<Map<String, dynamic>> transferShopOwnership(String shopId, String currentOwnerId, String newOwnerId, String otpCode) async {
    final response = await _supabase.rpc(
      'rpc_transfer_shop_ownership',
      params: {
        'p_shop_id': shopId,
        'p_current_owner_id': currentOwnerId,
        'p_new_owner_id': newOwnerId,
        'p_otp_code': otpCode,
      },
    );
    
    return Map<String, dynamic>.from(response as Map);
  }

  Future<bool> verifyCustomOTP(String email, String code) async {
    final response = await _supabase.rpc(
      'rpc_verify_custom_otp',
      params: {
        'p_email': email,
        'p_code': code,
      },
    );
    
    return response as bool;
  }

  Future<bool> checkUserExists(String email) async {
    final response = await _supabase.rpc(
      'rpc_check_user_exists',
      params: {'p_email': email},
    );
    return response as bool;
  }

  Future<AuthResponse> finalizeSignup(String email, String password) async {
    // Since we've already verified the OTP via our custom flow,
    // we use the standard signUp method. 
    // NOTE: For this to be seamless, 'Confirm Email' should be 
    // DISABLED in the Supabase Dashboard (Auth -> Providers -> Email).
    return await _supabase.auth.signUp(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signIn(String email, String password) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> finalizePasswordReset(String newPassword) async {
    // This requires the user to be signed in or have a recovery session
    final response = await _supabase.auth.updateUser(
      UserAttributes(password: newPassword),
    );

    if (response.user == null) {
       throw Exception('Failed to update password');
    }
  }

  Future<void> resetPassword(String email) async {
    // Use custom OTP flow instead of standard Supabase link-based recovery
    await sendCustomOTP(email, isSignup: false);
  }

  Future<void> resetPasswordWithEdgeFunction(String email, String newPassword) async {
    final response = await _supabase.functions.invoke(
      'reset-password',
      body: {'email': email, 'password': newPassword},
    );

    if (response.status != 200) {
      final error = response.data['error'] ?? 'Failed to reset password';
      throw Exception(error);
    }
  }

  Future<AuthResponse> verifyOTP(String email, String token, {required OtpType type}) async {
    return await _supabase.auth.verifyOTP(
      email: email,
      token: token,
      type: type,
    );
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
