import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_provider.dart';
import '../../core/shop_provider.dart';
import '../../models/shop.dart';

enum ShopView { main, create, join }

class ShopSelectScreen extends StatefulWidget {
  const ShopSelectScreen({super.key});

  @override
  State<ShopSelectScreen> createState() => _ShopSelectScreenState();
}

class _ShopSelectScreenState extends State<ShopSelectScreen> {
  ShopView _view = ShopView.main;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isProcessing = false;
  List<Map<String, dynamic>> _invitations = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authProvider = context.read<AuthProvider>();
      final shopProvider = context.read<ShopProvider>();
      final userId = authProvider.user?.id;
      final email = authProvider.user?.email;
      
      await shopProvider.fetchShops(userId);
      if (shopProvider.currentShop != null) {
        await authProvider.fetchAndSetRole(shopProvider.currentShop!.id);
      }
      
      if (email != null) {
        _fetchInvitations(email);
      }
    });
  }

  Future<void> _fetchInvitations(String email) async {
    final invites = await context.read<ShopProvider>().fetchInvitations(email);
    if (mounted) {
      setState(() {
        _invitations = invites;
      });
    }
  }

  Future<void> _handleCreateShop() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;

    setState(() => _isProcessing = true);
    try {
      final newShop = await context.read<ShopProvider>().createShop(
            name,
            _phoneController.text.trim(),
            _addressController.text.trim(),
            userId,
          );
      if (newShop != null && mounted) {
        context.read<AuthProvider>().setCurrentRole('Owner');
        context.go('/shop-home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleAcceptInvitation(Map<String, dynamic> invite) async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;

    setState(() => _isProcessing = true);
    try {
      await context.read<ShopProvider>().acceptInvitation(invite, userId);
      if (mounted) {
        await context.read<AuthProvider>().fetchAndSetRole(invite['shop_id']);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined ${invite['shops']?['name'] ?? 'the shop'}'), backgroundColor: Colors.green),
        );
        final email = context.read<AuthProvider>().user?.email;
        if (email != null) _fetchInvitations(email);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleDeclineInvitation(String id) async {
    try {
      await context.read<ShopProvider>().declineInvitation(id);
      final email = context.read<AuthProvider>().user?.email;
      if (email != null) _fetchInvitations(email);
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shopProvider = context.watch<ShopProvider>();
    final authProvider = context.watch<AuthProvider>();

    if (shopProvider.loading && shopProvider.shops.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Image.asset('assets/images/logo_wordmark.png', height: 28),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => authProvider.signOut(),
            icon: const Icon(LucideIcons.logOut, size: 18),
            label: const Text('Logout'),
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
          ),
          IconButton(
            onPressed: () => context.push('/profile'),
            icon: const Icon(LucideIcons.userCircle),
            color: const Color(0xFF154834),
            tooltip: 'Profile',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (shopProvider.shops.isNotEmpty) ...[
                Text('Your Shops', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 12),
                ...shopProvider.shops.map((shop) => _buildShopCard(shop, authProvider.user?.id)),
                const SizedBox(height: 24),
              ],
              if (_view == ShopView.main) _buildMainOptions() else if (_view == ShopView.create) _buildCreateForm() else if (_view == ShopView.join) _buildJoinView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShopCard(Shop shop, String? userId) {
    final isOwner = shop.ownerUserId == userId;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          setState(() => _isProcessing = true);
          try {
            // Group state updates
            await context.read<AuthProvider>().fetchAndSetRole(shop.id);
            if (!mounted) return;
            await context.read<ShopProvider>().setCurrentShop(shop);
            
            // Navigation is now automatically handled by GoRouter's redirect logic 
            // when ShopProvider.currentShop is set.
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error switching shop: $e'), backgroundColor: Colors.red),
              );
            }
          } finally {
            if (mounted) setState(() => _isProcessing = false);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.store, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shop.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (shop.address != null) Text(shop.address!, style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (isOwner)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Owner', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainOptions() {
    final hasNoShops = context.read<ShopProvider>().shops.isEmpty;
    return Column(
      children: [
        if (hasNoShops) ...[
          const Text('Welcome to Papyrus', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Create your shop or join an existing one', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 32),
        ],
        _buildOptionCard(
          icon: LucideIcons.building,
          title: 'Create a Shop',
          subtitle: 'Start your own business on Papyrus',
          onTap: () => setState(() => _view = ShopView.create),
        ),
        const SizedBox(height: 12),
        _buildOptionCard(
          icon: LucideIcons.users,
          title: 'Join as an Employee',
          subtitle: 'Accept shop invitations to join a team',
          onTap: () => setState(() => _view = ShopView.join),
          badgeCount: _invitations.length,
        ),
      ],
    );
  }

  Widget _buildOptionCard({required IconData icon, required String title, required String subtitle, required VoidCallback onTap, int badgeCount = 0}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text(badgeCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('New Shop', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                TextButton(onPressed: () => setState(() => _view = ShopView.main), child: const Text('Back')),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Shop Name *', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(controller: _nameController, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'My Shop')),
            const SizedBox(height: 16),
            const Text('Phone', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(controller: _phoneController, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '01XXXXXXXXX')),
            const SizedBox(height: 16),
            const Text('Address', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(controller: _addressController, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Shop address')),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => setState(() => _view = ShopView.main), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _handleCreateShop,
                    icon: const Icon(LucideIcons.check, size: 18),
                    label: Text(_isProcessing ? 'Creating...' : 'Create'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _view = ShopView.main),
              icon: const Icon(LucideIcons.arrowLeft, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            const Text('Shop Invitations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        const SizedBox(height: 24),
        if (_invitations.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(LucideIcons.users, color: Colors.grey, size: 32),
                  ),
                  const SizedBox(height: 16),
                  const Text('No pending invitations', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else
          ..._invitations.map((invite) => _buildInviteCard(invite)),
      ],
    );
  }

  Widget _buildInviteCard(Map<String, dynamic> invite) {
    final shopName = invite['shops']?['name'] ?? 'Unknown Shop';
    final roleName = invite['roles']?['name'] ?? 'Unknown Role';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
      ),
      color: Theme.of(context).colorScheme.primary.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.store, color: Theme.of(context).colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Text('You were invited as: $roleName', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _handleDeclineInvitation(invite['id']),
                    icon: const Icon(LucideIcons.xCircle, size: 18),
                    label: const Text('Decline'),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600, padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _handleAcceptInvitation(invite),
                    icon: const Icon(LucideIcons.checkCircle, size: 18),
                    label: Text(_isProcessing ? 'Joining...' : 'Accept'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
