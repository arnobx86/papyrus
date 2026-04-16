import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/shop_provider.dart';
import '../../core/data_refresh_notifier.dart';
import '../../core/auth_provider.dart';
import '../../core/permissions.dart';

class KenaBecaScreen extends StatefulWidget {
  const KenaBecaScreen({super.key});

  @override
  State<KenaBecaScreen> createState() => _KenaBecaScreenState();
}

class _KenaBecaScreenState extends State<KenaBecaScreen> {
  String _activeTab = 'today';
  bool _isLoading = true;
  
  // Dashboard data
  List<dynamic> _purchases = [];
  List<dynamic> _sales = [];
  List<dynamic> _returns = [];
  List<dynamic> _products = [];

  // Real-time subscriptions
  RealtimeChannel? _purchasesChannel;
  RealtimeChannel? _salesChannel;
  RealtimeChannel? _returnsChannel;

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupRealtimeSubscriptions();
    });
    // Listen for data changes from other screens
    context.read<DataRefreshNotifier>().addListener(_onDataRefresh);
  }

  void _onDataRefresh() {
    final notifier = context.read<DataRefreshNotifier>();
    if (notifier.shouldRefreshAny({DataChannel.sales, DataChannel.purchases, DataChannel.products, DataChannel.returns})) {
      _fetchDashboardData();
    }
  }

  @override
  void dispose() {
    context.read<DataRefreshNotifier>().removeListener(_onDataRefresh);
    _purchasesChannel?.unsubscribe();
    _salesChannel?.unsubscribe();
    _returnsChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtimeSubscriptions() {
    try {
      final shopId = context.read<ShopProvider>().currentShop?.id;
      if (shopId == null) {
        debugPrint('KenaBecaScreen: No shop ID, skipping real-time subscriptions');
        return;
      }

      final supabase = Supabase.instance.client;
      debugPrint('KenaBecaScreen: Setting up real-time subscriptions for shop $shopId');
      
      // Purchases subscription
      _purchasesChannel = supabase
        .channel('purchases')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'purchases',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'shop_id',
            value: shopId,
          ),
          callback: (payload) {
            debugPrint('KenaBecaScreen: Real-time purchase event: ${payload.eventType} for purchase ${payload.newRecord?['id'] ?? payload.oldRecord?['id']}');
            _handlePurchaseChange(payload);
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            debugPrint('KenaBecaScreen: Purchases subscription error: $error');
          } else {
            debugPrint('KenaBecaScreen: Purchases subscription status: $status');
          }
        });

      // Sales subscription
      _salesChannel = supabase
        .channel('sales')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sales',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'shop_id',
            value: shopId,
          ),
          callback: (payload) {
            debugPrint('KenaBecaScreen: Real-time sale event: ${payload.eventType} for sale ${payload.newRecord?['id'] ?? payload.oldRecord?['id']}');
            _handleSaleChange(payload);
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            debugPrint('KenaBecaScreen: Sales subscription error: $error');
          } else {
            debugPrint('KenaBecaScreen: Sales subscription status: $status');
          }
        });

      // Returns subscription (only if table exists)
      try {
        _returnsChannel = supabase
          .channel('returns')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'returns',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'shop_id',
              value: shopId,
            ),
            callback: (payload) {
              debugPrint('KenaBecaScreen: Real-time return event: ${payload.eventType} for return ${payload.newRecord?['id'] ?? payload.oldRecord?['id']}');
              _handleReturnChange(payload);
            },
          )
          .subscribe((status, error) {
            if (error != null) {
              debugPrint('KenaBecaScreen: Returns subscription error: $error');
            } else {
              debugPrint('KenaBecaScreen: Returns subscription status: $status');
            }
          });
        debugPrint('KenaBecaScreen: Returns subscription set up');
      } catch (e) {
        debugPrint('KenaBecaScreen: Returns table may not exist, skipping returns subscription: $e');
        _returnsChannel = null;
      }
    } catch (e) {
      debugPrint('KenaBecaScreen: Error setting up real-time subscriptions: $e');
    }
  }

  void _handlePurchaseChange(PostgresChangePayload payload) {
    try {
      final newRecord = payload.newRecord;
      final oldRecord = payload.oldRecord;
      final eventType = payload.eventType;

      debugPrint('KenaBecaScreen: Handling purchase $eventType for ${newRecord?['id'] ?? oldRecord?['id']}');

      setState(() {
        if (eventType == 'UPDATE' && newRecord != null) {
          final purchaseId = newRecord['id'];
          final index = _purchases.indexWhere((p) => p['id'] == purchaseId);
          if (index != -1) {
            _purchases[index] = newRecord;
            debugPrint('KenaBecaScreen: Updated purchase $purchaseId');
          } else {
            _purchases.add(newRecord);
            _purchases.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
            debugPrint('KenaBecaScreen: Added missing purchase $purchaseId');
          }
        } else if (eventType == 'INSERT' && newRecord != null) {
          _purchases.add(newRecord);
          _purchases.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
          debugPrint('KenaBecaScreen: Inserted new purchase ${newRecord['id']}');
        } else if (eventType == 'DELETE' && oldRecord != null) {
          final purchaseId = oldRecord['id'];
          _purchases.removeWhere((p) => p['id'] == purchaseId);
          debugPrint('KenaBecaScreen: Deleted purchase $purchaseId');
        }
      });
    } catch (e) {
      debugPrint('KenaBecaScreen: Error in _handlePurchaseChange: $e');
    }
  }

  void _handleSaleChange(PostgresChangePayload payload) {
    try {
      final newRecord = payload.newRecord;
      final oldRecord = payload.oldRecord;
      final eventType = payload.eventType;

      debugPrint('KenaBecaScreen: Handling sale $eventType for ${newRecord?['id'] ?? oldRecord?['id']}');

      setState(() {
        if (eventType == 'UPDATE' && newRecord != null) {
          final saleId = newRecord['id'];
          final index = _sales.indexWhere((s) => s['id'] == saleId);
          if (index != -1) {
            _sales[index] = newRecord;
            debugPrint('KenaBecaScreen: Updated sale $saleId');
          } else {
            _sales.add(newRecord);
            _sales.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
            debugPrint('KenaBecaScreen: Added missing sale $saleId');
          }
        } else if (eventType == 'INSERT' && newRecord != null) {
          _sales.add(newRecord);
          _sales.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
          debugPrint('KenaBecaScreen: Inserted new sale ${newRecord['id']}');
        } else if (eventType == 'DELETE' && oldRecord != null) {
          final saleId = oldRecord['id'];
          _sales.removeWhere((s) => s['id'] == saleId);
          debugPrint('KenaBecaScreen: Deleted sale $saleId');
        }
      });
    } catch (e) {
      debugPrint('KenaBecaScreen: Error in _handleSaleChange: $e');
    }
  }

  void _handleReturnChange(PostgresChangePayload payload) {
    try {
      final newRecord = payload.newRecord;
      final oldRecord = payload.oldRecord;
      final eventType = payload.eventType;

      debugPrint('KenaBecaScreen: Handling return $eventType for ${newRecord?['id'] ?? oldRecord?['id']}');

      setState(() {
        if (eventType == 'UPDATE' && newRecord != null) {
          final returnId = newRecord['id'];
          final index = _returns.indexWhere((r) => r['id'] == returnId);
          if (index != -1) {
            _returns[index] = newRecord;
            debugPrint('KenaBecaScreen: Updated return $returnId');
          } else {
            _returns.add(newRecord);
            debugPrint('KenaBecaScreen: Added missing return $returnId');
          }
        } else if (eventType == 'INSERT' && newRecord != null) {
          _returns.add(newRecord);
          debugPrint('KenaBecaScreen: Inserted new return ${newRecord['id']}');
        } else if (eventType == 'DELETE' && oldRecord != null) {
          final returnId = oldRecord['id'];
          _returns.removeWhere((r) => r['id'] == returnId);
          debugPrint('KenaBecaScreen: Deleted return $returnId');
        }
      });
    } catch (e) {
      debugPrint('KenaBecaScreen: Error in _handleReturnChange: $e');
    }
  }

  Future<void> _fetchDashboardData() async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) {
      debugPrint('KenaBecaScreen: No shop ID');
      return;
    }

    debugPrint('KenaBecaScreen: Fetching dashboard data for shop $shopId');
    setState(() => _isLoading = true);
    
    try {
      final supabase = Supabase.instance.client;
      
      // Fetch each table separately to handle missing tables gracefully
      List<dynamic> purchases = [];
      List<dynamic> sales = [];
      List<dynamic> returns = [];
      List<dynamic> products = [];
      
      try {
        purchases = await supabase.from('purchases').select().eq('shop_id', shopId).order('created_at', ascending: false);
        debugPrint('KenaBecaScreen: Fetched ${purchases.length} purchases');
      } catch (e) {
        debugPrint('KenaBecaScreen: Error fetching purchases: $e');
      }
      
      try {
        sales = await supabase.from('sales').select().eq('shop_id', shopId).order('created_at', ascending: false);
        debugPrint('KenaBecaScreen: Fetched ${sales.length} sales');
      } catch (e) {
        debugPrint('KenaBecaScreen: Error fetching sales: $e');
      }
      
      try {
        returns = await supabase.from('returns').select().eq('shop_id', shopId);
        debugPrint('KenaBecaScreen: Fetched ${returns.length} returns');
      } catch (e) {
        debugPrint('KenaBecaScreen: Error fetching returns (table may not exist): $e');
        // Initialize empty returns list if table doesn't exist
        returns = [];
      }
      
      try {
        products = await supabase.from('products').select().eq('shop_id', shopId);
        debugPrint('KenaBecaScreen: Fetched ${products.length} products');
      } catch (e) {
        debugPrint('KenaBecaScreen: Error fetching products: $e');
      }

      if (mounted) {
        setState(() {
          _purchases = purchases;
          _sales = sales;
          _returns = returns;
          _products = products;
          _isLoading = false;
        });
        debugPrint('KenaBecaScreen: Data loaded successfully (purchases: ${_purchases.length}, sales: ${_sales.length}, returns: ${_returns.length}, products: ${_products.length})');
      }
    } catch (e) {
      debugPrint('KenaBecaScreen: Error in _fetchDashboardData: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Calculations (Simplified - matching web app logic)
    bool isWithinRange(String createdAt) {
      if (_activeTab == 'total') return true;
      
      try {
        // Parse the UTC timestamp and convert to local time
        final date = DateTime.parse(createdAt).toLocal();
        final now = DateTime.now().toLocal();
        
        if (_activeTab == 'today') {
          final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
          if (!isToday) {
            debugPrint('KenaBecaScreen: Date $createdAt (local: $date) is not today (now: $now)');
          }
          return isToday;
        }
        if (_activeTab == 'monthly') {
          final isThisMonth = date.year == now.year && date.month == now.month;
          if (!isThisMonth) {
            debugPrint('KenaBecaScreen: Date $createdAt (local: $date) is not this month (now: $now)');
          }
          return isThisMonth;
        }
      } catch (e) {
        debugPrint('KenaBecaScreen: Error parsing date $createdAt: $e');
      }
      return true;
    }

    debugPrint('KenaBecaScreen: Before filtering - purchases: ${_purchases.length}, sales: ${_sales.length}, returns: ${_returns.length}');
    
    final filteredPurchases = _purchases.where((p) => isWithinRange(p['created_at'])).toList();
    final filteredSales = _sales.where((s) => isWithinRange(s['created_at'])).toList();
    final filteredReturns = _returns.where((r) => isWithinRange(r['created_at'])).toList();
    
    debugPrint('KenaBecaScreen: After filtering ($_activeTab) - purchases: ${filteredPurchases.length}, sales: ${filteredSales.length}, returns: ${filteredReturns.length}');
    
    // Log sample dates for debugging
    if (_purchases.isNotEmpty && filteredPurchases.isEmpty) {
      debugPrint('KenaBecaScreen: Sample purchase date: ${_purchases.first['created_at']}');
    }
    if (_sales.isNotEmpty && filteredSales.isEmpty) {
      debugPrint('KenaBecaScreen: Sample sale date: ${_sales.first['created_at']}');
    }

    final totalPurchase = filteredPurchases.fold(0.0, (s, p) => s + (double.tryParse(p['total_amount'].toString()) ?? 0));
    final totalSale = filteredSales.fold(0.0, (s, p) => s + (double.tryParse(p['total_amount'].toString()) ?? 0));
    final purchaseDue = filteredPurchases.fold(0.0, (s, p) => s + (double.tryParse(p['due_amount'].toString()) ?? 0));
    final saleDue = filteredSales.fold(0.0, (s, p) => s + (double.tryParse(p['due_amount'].toString()) ?? 0));
    
    final purchaseReturns = filteredReturns.where((r) => r['type'] == 'purchase').fold(0.0, (s, r) => s + (double.tryParse(r['amount'].toString()) ?? 0));
    final saleReturns = filteredReturns.where((r) => r['type'] == 'sale').fold(0.0, (s, r) => s + (double.tryParse(r['amount'].toString()) ?? 0));
    
    final currentStock = _products.fold(0.0, (s, p) => s + (double.tryParse(p['stock'].toString()) ?? 0));
    final netProfit = filteredSales.fold(0.0, (s, p) => s + (double.tryParse(p['profit'].toString()) ?? 0));
    
    final purchaseVat = filteredPurchases.fold(0.0, (s, p) => s + (double.tryParse(p['vat_amount'].toString()) ?? 0));
    final saleVat = filteredSales.fold(0.0, (s, p) => s + (double.tryParse(p['vat_amount'].toString()) ?? 0));

    final lowStockProducts = _products.where((p) {
      final stock = double.tryParse(p['stock'].toString()) ?? 0;
      final minStock = double.tryParse(p['min_stock'].toString()) ?? 0;
      return stock <= minStock;
    }).toList();

    final isOwner = context.read<ShopProvider>().currentShop?.ownerUserId == Supabase.instance.client.auth.currentUser?.id;
    final auth = context.watch<AuthProvider>();
    final canCreatePurchase = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.createPurchase);
    final canCreateSale = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.createSale);
    final canManageProducts = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.manageProducts);
    final canManageCustomers = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.manageCustomers);
    final canManageSuppliers = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.manageSuppliers);
    final canManageParties = canManageCustomers || canManageSuppliers;
    final canViewReports = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.viewReports);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('কেনা বেচা', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.home),
            onPressed: () => context.go('/shop-home'),
          ),
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDashboardData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Quick Actions
            if (canCreatePurchase || canCreateSale) ...[
              Row(
                children: [
                  if (canCreatePurchase) ...[
                    Expanded(
                      child: _buildActionButton(
                        label: 'New Purchase',
                        icon: LucideIcons.plus,
                        color: Colors.blue,
                        onTap: () async {
                          await context.push('/new-purchase');
                          _fetchDashboardData();
                        },
                        isPrimary: false,
                      ),
                    ),
                    if (canCreateSale) const SizedBox(width: 12),
                  ],
                  if (canCreateSale)
                    Expanded(
                      child: _buildActionButton(
                        label: 'New Sale',
                        icon: LucideIcons.plus,
                        color: Theme.of(context).colorScheme.primary,
                        onTap: () async {
                          await context.push('/new-sale');
                          _fetchDashboardData();
                        },
                        isPrimary: true,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: _buildSecondaryActionButton(
                    label: 'Purchase',
                    icon: LucideIcons.shoppingCart,
                    iconColor: Colors.amber,
                    onTap: () => context.push('/all-purchases'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSecondaryActionButton(
                    label: 'Sale',
                    icon: LucideIcons.store,
                    iconColor: Colors.blue,
                    onTap: () => context.push('/all-sales'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Third row of smaller buttons
            Row(
              children: [
                if (canManageProducts) ...[
                  Expanded(
                    child: _buildSmallActionButton(
                      label: 'Products',
                      icon: LucideIcons.package,
                      color: Colors.red,
                      onTap: () => context.push('/products'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (canManageParties) ...[
                  Expanded(
                    child: _buildSmallActionButton(
                      label: 'Parties',
                      icon: LucideIcons.users,
                      color: Colors.blue,
                      onTap: () => context.push('/parties'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _buildSmallActionButton(
                    label: 'Returns',
                    icon: LucideIcons.rotateCcw,
                    color: Colors.purple,
                    onTap: () => context.push('/returns'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Low Stock Alert
            if (lowStockProducts.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Low Stock Alert', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  TextButton(onPressed: () => context.push('/products'), child: const Text('View All')),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.red.withOpacity(0.05),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < lowStockProducts.take(3).length; i++) ...[
                      if (i > 0) Divider(height: 1, color: Colors.red.withOpacity(0.1)),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.withOpacity(0.1),
                          child: const Icon(LucideIcons.package, color: Colors.red, size: 20),
                        ),
                        title: Text(lowStockProducts[i]['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('Stock: ${lowStockProducts[i]['stock']} ${lowStockProducts[i]['unit']}', style: const TextStyle(color: Colors.red, fontSize: 12)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                          child: const Text('Low Stock', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Metrics Card (Today/Monthly/Total filter)
            if (canViewReports) ...[
              _buildMetricsSection(
                totalPurchase, 
                totalSale, 
                purchaseDue, 
                saleDue, 
                filteredPurchases, 
                filteredSales, 
                purchaseReturns, 
                saleReturns, 
                currentStock, 
                netProfit, 
                purchaseVat, 
                saleVat,
                isOwner,
              ),
              const SizedBox(height: 24),
            ],

            // Recent Purchases
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent Purchases', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton(onPressed: () => context.push('/all-purchases'), child: const Text('View All')),
              ],
            ),
            if (_purchases.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(child: Text('No purchases yet', style: TextStyle(color: Colors.grey))),
              )
            else
              ..._purchases.take(3).map((p) => _buildTransactionItem(
                name: p['supplier_name'],
                amount: p['total_amount'].toString(),
                isIncome: false,
              )),
            
            const SizedBox(height: 24),

            // Recent Sales
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent Sales', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton(onPressed: () => context.push('/all-sales'), child: const Text('View All')),
              ],
            ),
            if (_sales.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(child: Text('No sales yet', style: TextStyle(color: Colors.grey))),
              )
            else
              ..._sales.take(3).map((s) => _buildTransactionItem(
                name: s['customer_name'],
                amount: s['total_amount'].toString(),
                isIncome: true,
              )),
            
            const SizedBox(height: 100), // Bottom padding for nav
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required String label, required IconData icon, required Color color, required VoidCallback onTap, required bool isPrimary}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: isPrimary ? null : Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isPrimary ? Colors.white : color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isPrimary ? Colors.white : color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryActionButton({required String label, required IconData icon, required Color iconColor, required VoidCallback onTap}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Theme.of(context).dividerColor)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallActionButton({required String label, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Theme.of(context).dividerColor)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsSection(
    double purchase, 
    double sale, 
    double pDue, 
    double sDue, 
    List filteredPurchases, 
    List filteredSales, 
    double purchaseReturns, 
    double saleReturns, 
    double currentStock, 
    double netProfit, 
    double purchaseVat, 
    double saleVat,
    bool isOwner,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['today', 'monthly', 'total'].map((t) {
            final active = _activeTab == t;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeTab = t),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? Theme.of(context).colorScheme.primary : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  child: Text(
                    t == 'today' ? 'Today' : t == 'monthly' ? 'This Month' : 'Total',
                    style: TextStyle(
                      color: active ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 2.5,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              if (isOwner) _buildMetricItem('Purchase', '৳${purchase.toStringAsFixed(0)}', Colors.amber, LucideIcons.shoppingCart),
              _buildMetricItem('Sale', '৳${sale.toStringAsFixed(0)}', Colors.blue, LucideIcons.store),
              if (isOwner) _buildMetricItem('Purchase Due', '৳${pDue.toStringAsFixed(0)}', Colors.red, LucideIcons.trendingDown),
              _buildMetricItem('Sale Due', '৳${sDue.toStringAsFixed(0)}', Colors.blueAccent, LucideIcons.trendingDown),
              if (isOwner) _buildMetricItem('Purchased', '${filteredPurchases.length} txn', Colors.orange, LucideIcons.package),
              _buildMetricItem('Sold', '${filteredSales.length} txn', Colors.green, LucideIcons.package),
              if (isOwner) _buildMetricItem('Purchase Returns', '৳${purchaseReturns.toStringAsFixed(0)}', Colors.amber, LucideIcons.rotateCcw),
              _buildMetricItem('Sale Returns', '৳${saleReturns.toStringAsFixed(0)}', Colors.red, LucideIcons.rotateCcw),
              _buildMetricItem('Current Stock', '${currentStock.toStringAsFixed(0)} item', Colors.teal, LucideIcons.box),
              if (isOwner) _buildMetricItem('Net Profit', '৳${netProfit.toStringAsFixed(0)}', Colors.green, LucideIcons.dollarSign),
              if (isOwner) _buildMetricItem('Purchase VAT', '৳${purchaseVat.toStringAsFixed(0)}', Colors.red, LucideIcons.percent),
              _buildMetricItem('Sale VAT', '৳${saleVat.toStringAsFixed(0)}', Colors.blue, LucideIcons.percent),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricItem(String label, String value, Color color, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10), maxLines: 1),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionItem({required String name, required String amount, required bool isIncome}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isIncome ? Colors.blue : Colors.red).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isIncome ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft,
                  size: 16,
                  color: isIncome ? Colors.blue : Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
          Text(
            '${isIncome ? "+" : "-"}৳$amount',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isIncome ? Colors.blue : Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}
