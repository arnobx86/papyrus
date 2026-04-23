import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/shop_provider.dart';
import '../../core/auth_provider.dart';
import '../../core/permissions.dart';
import '../../core/data_refresh_notifier.dart';
import '../../core/version_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  double _todaySales = 0;
  double _todayPurchases = 0;
  double _todayExpense = 0;
  double _currentStock = 0;
  RealtimeChannel? _mainChannel;

  @override
  void initState() {
    super.initState();
    _fetchSummary();
    _setupRealtime();
    // Listen for data changes from other screens
    context.read<DataRefreshNotifier>().addListener(_onDataRefresh);
    
    // Check for updates from the Papyrus website API
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VersionService.checkForUpdates(context);
    });
  }

  void _onDataRefresh() {
    final notifier = context.read<DataRefreshNotifier>();
    if (notifier.shouldRefreshAny({DataChannel.sales, DataChannel.purchases, DataChannel.transactions, DataChannel.products, DataChannel.wallets, DataChannel.activity})) {
      _fetchSummary();
    }
  }

  @override
  void dispose() {
    context.read<DataRefreshNotifier>().removeListener(_onDataRefresh);
    _mainChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtime() {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    final supabase = Supabase.instance.client;
    
    // Use ONE channel for ALL shop-related tables
    _mainChannel = supabase.channel('shop_updates_$shopId');

    // Sales
    _mainChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'sales',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'shop_id', value: shopId),
      callback: (payload) => _fetchSummary(),
    );

    // Purchases
    _mainChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'purchases',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'shop_id', value: shopId),
      callback: (payload) => _fetchSummary(),
    );

    // Transactions
    _mainChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'transactions',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'shop_id', value: shopId),
      callback: (payload) => _fetchSummary(),
    );

    // Products
    _mainChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'products',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'shop_id', value: shopId),
      callback: (payload) => _fetchSummary(),
    );

    _mainChannel!.subscribe();
  }

  Future<void> _fetchSummary() async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final today = DateTime.now().toIso8601String().split('T')[0];

      final results = await Future.wait([
        // Today's Total Sales (Revenue)
        supabase.from('sales').select('total_amount').eq('shop_id', shopId).gte('created_at', today),
        // Today's Total Purchases
        supabase.from('purchases').select('total_amount').eq('shop_id', shopId).gte('created_at', today),
        // Today's Total Expenses (using transaction_date for accuracy)
        supabase.from('transactions').select('amount').eq('shop_id', shopId).eq('type', 'expense').eq('transaction_date', today),
        supabase.from('products').select('stock').eq('shop_id', shopId),
      ]);

      if (mounted) {
        setState(() {
          _todaySales = (results[0] as List).fold(0.0, (s, i) => s + (double.tryParse(i['total_amount'].toString()) ?? 0));
          _todayPurchases = (results[1] as List).fold(0.0, (s, i) => s + (double.tryParse(i['total_amount'].toString()) ?? 0));
          _todayExpense = (results[2] as List).fold(0.0, (s, i) => s + (double.tryParse(i['amount'].toString()) ?? 0));
          _currentStock = (results[3] as List).fold(0.0, (s, i) => s + (double.tryParse(i['stock'].toString()) ?? 0));
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching summary: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = context.watch<ShopProvider>().currentShop;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9), // Very light green-grey background
      body: RefreshIndicator(
        onRefresh: _fetchSummary,
        color: const Color(0xFF154834),
        child: CustomScrollView(
          slivers: [
            _buildAppBar(context, shop),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    _buildPremiumWelcomeCard(context),
                    const SizedBox(height: 32),
                    
                    if (context.watch<AuthProvider>().currentRole == 'Owner' || Permissions.hasPermission(context.watch<AuthProvider>().currentPermissions, AppPermission.viewReports)) ...[
                      _buildSectionHeader('Key Performance', LucideIcons.barChart2),
                      const SizedBox(height: 16),
                      _buildPremiumStatsGrid(),
                      const SizedBox(height: 32),
                    ],
                    _buildSectionHeader('Business Modules', LucideIcons.layoutGrid),
                    const SizedBox(height: 16),
                    _buildFeaturedModules(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Recent Activity', LucideIcons.history, onViewAll: () => context.push('/activity-history')),
                    const SizedBox(height: 16),
                    _buildActivityTimeline(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, dynamic shop) {
    return SliverAppBar(
      expandedHeight: 0,
      floating: true,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF154834).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.home, color: const Color(0xFF154834), size: 20),
          ),
          const SizedBox(width: 12),
          Text(shop?.name ?? 'Papyrus', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF154834))),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () => context.push('/notifications'),
          icon: const Icon(LucideIcons.bell, color: Colors.grey),
        ),
        IconButton(
          onPressed: () => context.push('/settings'), 
          icon: const Icon(LucideIcons.settings, color: Colors.grey),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {VoidCallback? onViewAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF154834).withOpacity(0.5)),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B2C24))),
          ],
        ),
        if (onViewAll != null)
          GestureDetector(
            onTap: onViewAll,
            child: const Text(
              'View All',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF154834),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPremiumWelcomeCard(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canCreateSale = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.createSale);
    final canManageProducts = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.manageProducts);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF154834), Color(0xFF2E6B4F)],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF154834).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Icon(LucideIcons.circle, size: 120, color: Colors.white.withOpacity(0.05)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Welcome Back!', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 4),
              const Text('Let\'s grow your business today.', 
                         style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, height: 1.2)),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (canCreateSale) ...[
                    _buildQuickActionButton(LucideIcons.plus, 'Sale', () => context.push('/new-sale')),
                    const SizedBox(width: 12),
                  ],
                  if (canManageProducts) ...[
                    _buildQuickActionButton(LucideIcons.box, 'Stock', () => context.push('/products')),
                    const SizedBox(width: 12),
                  ],
                  _buildQuickActionButton(LucideIcons.barChart2, 'Report', () => context.push('/daily-report')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumStatsGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.3,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      children: [
        _buildAnimatedStatCard('Today Sales', '৳${_todaySales.toStringAsFixed(0)}', const Color(0xFFE4F3EC), const Color(0xFF154834), LucideIcons.trendingUp),
        _buildAnimatedStatCard('Expense', '৳${_todayExpense.toStringAsFixed(0)}', const Color(0xFFFDECEC), const Color(0xFFD32F2F), LucideIcons.trendingDown),
        _buildAnimatedStatCard('Total Stock', _currentStock.toStringAsFixed(0), const Color(0xFFFFF7EA), const Color(0xFFF57C00), LucideIcons.package),
        _buildAnimatedStatCard('Today Cash', '৳${(_todaySales - _todayExpense).toStringAsFixed(0)}', const Color(0xFFECF4FD), const Color(0xFF1976D2), LucideIcons.wallet),
      ],
    );
  }

  Widget _buildAnimatedStatCard(String title, String value, Color bgColor, Color accentColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withOpacity(0.1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 18),
          ),
          const Spacer(),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: accentColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedModules() {
    final auth = context.read<AuthProvider>();
    final canViewReports = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.viewReports);

    return Column(
      children: [
        _buildPremiumModuleItem(
          title: 'কেনা বেচা (Kena Beca)',
          subtitle: 'Sales, Purchases & Stock Control',
          icon: LucideIcons.shoppingBag,
          color: const Color(0xFF154834),
          onTap: () => context.go('/kena-becha'),
        ),
        const SizedBox(height: 12),
        _buildPremiumModuleItem(
          title: 'লেন দেন (Len Den)',
          subtitle: 'Customer & Supplier Ledgers',
          icon: LucideIcons.users,
          color: const Color(0xFF1976D2),
          onTap: () => context.go('/len-den'),
        ),
        const SizedBox(height: 12),
        if (canViewReports) ...[
          _buildPremiumModuleItem(
            title: 'আয় ব্যয় (Ay Bay)',
            subtitle: 'Cash Book & Expense Tracking',
            icon: LucideIcons.landmark,
            color: const Color(0xFFF57C00),
            onTap: () => context.go('/ay-bay'),
          ),
          _buildPremiumModuleItem(
            title: 'Activity History',
            subtitle: 'Real-time actions log',
            icon: LucideIcons.activity,
            color: Colors.indigo,
            onTap: () => context.go('/activity'),
          ),
        ],
      ],
    );
  }

  Widget _buildPremiumModuleItem({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.1), width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B2C24))),
                  Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
            Icon(LucideIcons.arrowRight, color: color.withOpacity(0.3), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTimeline() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: context.read<ShopProvider>().getRecentActivity(limit: 5),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Activity timeline error: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Icon(LucideIcons.alertCircle, color: Colors.red, size: 32),
                  const SizedBox(height: 8),
                  Text('Error loading activity', style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Text('${snapshot.error}', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ],
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No activity yet', style: TextStyle(color: Colors.grey))));
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: snapshot.data!.map((activity) => _buildTimelineItem(activity)).toList(),
          ),
        );
      },
    );
  }

  // Helper method to get invoice number from sales or purchases table
  Future<String?> _getInvoiceNumber(String? action, String referenceId) async {
    try {
      if (action == null) return null;
      
      final supabase = Supabase.instance.client;
      String? table;
      
      // Determine table based on action type
      if (action.toLowerCase().contains('sale')) {
        table = 'sales';
      } else if (action.toLowerCase().contains('purchase')) {
        table = 'purchases';
      }
      
      if (table == null) return null;
      
      final response = await supabase
          .from(table)
          .select('invoice_number')
          .eq('id', referenceId)
          .single();
      return response['invoice_number']?.toString();
    } catch (e) {
      debugPrint('Error fetching invoice number: $e');
      return null;
    }
  }

  Widget _buildTimelineItem(Map<String, dynamic> activity) {
    final action = activity['action'].toString();
    final userEmail = activity['user_email']?.toString();
    String userDisplay;
    
    if (userEmail != null && userEmail.isNotEmpty) {
      // Extract username from email (part before @)
      userDisplay = userEmail.split('@')[0];
    } else if (activity['user_id'] != null) {
      // If we have user_id but no email, show a shortened version
      final userId = activity['user_id'].toString();
      userDisplay = 'User ${userId.substring(0, 8)}...';
    } else {
      // No user info at all
      userDisplay = 'System';
    }
    
    final time = DateTime.parse(activity['created_at'].toString()).toLocal();
    
    // Extract details
    final details = activity['details'] as Map<String, dynamic>?;
    final invoiceNumber = details?['invoice_number'];
    final referenceId = details?['entity_id'] ?? details?['reference_id'] ?? details?['invoice_id'];
    
    Color accentColor = Colors.grey;
    if (action.contains('Sale')) accentColor = Colors.green;
    else if (action.contains('Purchase')) accentColor = Colors.blue;
    else if (action.contains('Update')) accentColor = Colors.orange;
    else if (action.contains('Delete')) accentColor = Colors.red;
    else if (action.contains('Add')) accentColor = Colors.purple;
    else if (action.contains('Transaction')) accentColor = Colors.deepPurple;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor.withOpacity(0.2), width: 4),
                ),
              ),
              Container(
                width: 2,
                height: 40,
                color: Colors.grey.withOpacity(0.1),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(activity['details']['message'] ?? action,
                     style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                // Show invoice number from details if available (for deletions)
                if (invoiceNumber != null)
                  Text(
                    'Invoice Number: $invoiceNumber',
                    style: const TextStyle(color: Colors.deepPurple, fontSize: 11, fontWeight: FontWeight.w500),
                  )
                // Otherwise try to fetch from database for non-deletion activities
                else if (referenceId != null && !action.toLowerCase().contains('delete'))
                  FutureBuilder<String?>(
                    future: _getInvoiceNumber(action, referenceId.toString()),
                    builder: (context, snapshot) {
                      final fetchedInvoiceNumber = snapshot.data;
                      if (fetchedInvoiceNumber != null) {
                        return Text(
                          'Invoice Number: $fetchedInvoiceNumber',
                          style: const TextStyle(color: Colors.deepPurple, fontSize: 11, fontWeight: FontWeight.w500),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                const SizedBox(height: 2),
                Text('by $userDisplay • ${_formatTimeAgo(time)}',
                     style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
