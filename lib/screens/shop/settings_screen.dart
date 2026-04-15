import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/permissions.dart';
import '../../core/auth_provider.dart';
import '../../core/shop_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.currentRole;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                _buildItem(
                  context,
                  icon: LucideIcons.user,
                  label: 'Profile',
                  color: Colors.blue,
                  onTap: () => context.push('/profile'),
                ),
                if (auth.currentRole == 'Owner')
                  _buildNotificationToggle(context),
                if (auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.manageRoles))
                  _buildItem(
                    context,
                    icon: LucideIcons.fileText,
                    label: 'Invoice Settings',
                    color: Colors.teal,
                    onTap: () => context.push('/invoice-settings'),
                  ),
                if (auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.manageEmployees))
                  _buildItem(
                    context,
                    icon: LucideIcons.users,
                    label: 'Employees',
                    color: Colors.amber,
                    onTap: () => context.push('/employees'),
                  ),
                if (auth.currentRole == 'Owner')
                  _buildItem(
                    context,
                    icon: LucideIcons.checkSquare,
                    label: 'Approvals',
                    color: Colors.orange,
                    onTap: () => context.push('/approvals'),
                  ),
                const Divider(),
                if (auth.currentRole == 'Owner')
                  _buildItem(
                    context,
                    icon: LucideIcons.trash2,
                    label: 'Delete Shop',
                    color: Colors.red,
                    onTap: () => _showDeleteShopDialog(context),
                  ),
                _buildItem(
                  context,
                  icon: LucideIcons.logOut,
                  label: 'Log Out',
                  color: Colors.grey,
                  onTap: () => _handleLogout(context),
                ),
              ],
            ),
          ),
          _buildVersionFooter(),
        ],
      ),
    );
  }

  Widget _buildVersionFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Version: 1.0.7',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              children: [
                const TextSpan(text: 'Develop by '),
                WidgetSpan(
                  child: GestureDetector(
                    onTap: () async {
                      final url = Uri.parse('https://arnob.pro.bd');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url);
                      } else {
                        debugPrint('Could not launch $url');
                      }
                    },
                    child: Text(
                      'arnobx86',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteShopDialog(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final shop = context.read<ShopProvider>().currentShop;
    if (shop == null || auth.user?.email == null) return;

    final TextEditingController otpController = TextEditingController();
    bool otpSent = false;
    bool isVerifying = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Delete Shop', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⚠️ WARNING: This action is IRREVERSIBLE.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Every single record (Sales, Stock, Team, etc.) will be permanently erased from our servers.'),
              const SizedBox(height: 16),
              if (!otpSent) ...[
                const Text('To proceed, we need to verify your identity. A code will be sent to:'),
                Text(auth.user!.email!, style: const TextStyle(fontWeight: FontWeight.bold)),
              ] else ...[
                const Text('Enter the 6-digit code sent to your email:'),
                const SizedBox(height: 8),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '000000', border: OutlineInputBorder()),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            if (!otpSent)
              ElevatedButton(
                onPressed: isVerifying ? null : () async {
                  setState(() => isVerifying = true);
                  try {
                    await auth.sendCustomOTPForDeletion(auth.user!.email!);
                    setState(() {
                      otpSent = true;
                      isVerifying = false;
                    });
                  } catch (e) {
                    setState(() => isVerifying = false);
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                },
                child: Text(isVerifying ? 'Sending...' : 'Send Verification Code'),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: isVerifying ? null : () async {
                  setState(() => isVerifying = true);
                  try {
                    final valid = await auth.verifyCustomOTP(auth.user!.email!, otpController.text.trim());
                    if (valid) {
                      if (context.mounted) {
                        Navigator.pop(context);
                        _performFinalDelete(context);
                      }
                    } else {
                      setState(() => isVerifying = false);
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid code'), backgroundColor: Colors.red));
                    }
                  } catch (e) {
                    setState(() => isVerifying = false);
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                },
                child: Text(isVerifying ? 'Verifying...' : 'DELETE SHOP'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _performFinalDelete(BuildContext context) async {
    final shopProvider = context.read<ShopProvider>();
    final shopId = shopProvider.currentShop?.id;
    if (shopId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await Supabase.instance.client.rpc('delete_shop_cascade', params: {'p_shop_id': shopId});
      
      // Clear the current shop state before navigating
      await shopProvider.setCurrentShop(null);
      await shopProvider.fetchShops(context.read<AuthProvider>().user?.id);
      
      if (context.mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shop successfully deleted!'), backgroundColor: Colors.green)
        );
        context.go('/shop-select');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete Error: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  Widget _buildItem(BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: const Icon(LucideIcons.chevronRight, size: 16, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildNotificationToggle(BuildContext context) {
    return FutureBuilder<bool>(
      future: _getNotificationPreference(),
      builder: (context, snapshot) {
        final isEnabled = snapshot.data ?? true;
        return SwitchListTile(
          secondary: const Icon(LucideIcons.bell, color: Colors.purple, size: 22),
          title: const Text('Activity Notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: const Text('Get notified when employees make sales/purchases', style: TextStyle(fontSize: 12)),
          value: isEnabled,
          onChanged: (value) => _toggleNotifications(context, value),
        );
      },
    );
  }

  Future<bool> _getNotificationPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('activity_notifications_enabled') ?? true;
    } catch (e) {
      return true;
    }
  }

  Future<void> _toggleNotifications(BuildContext context, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('activity_notifications_enabled', value);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'Notifications enabled' : 'Notifications disabled'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log Out', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      if (context.mounted) {
        await context.read<AuthProvider>().signOut();
        // GoRouter will redirect to /login due to refreshListenable
      }
    }
  }
}
