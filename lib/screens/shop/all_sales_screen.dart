import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/shop_provider.dart';
import '../../core/notification_service.dart';
import '../../core/data_refresh_notifier.dart';
import '../../core/auth_provider.dart';
import '../../core/permissions.dart';
import '../../core/connectivity_service.dart';
import '../../core/local_cache_service.dart';

class AllSalesScreen extends StatefulWidget {
  const AllSalesScreen({super.key});

  @override
  State<AllSalesScreen> createState() => _AllSalesScreenState();
}

class _AllSalesScreenState extends State<AllSalesScreen> {
  bool _isLoading = true;
  List<dynamic> _sales = [];
  String _searchQuery = '';
  RealtimeChannel? _salesChannel;

  @override
  void initState() {
    super.initState();
    _fetchSales();
    _setupRealtime();
  }

  @override
  void dispose() {
    _salesChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtime() {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    final supabase = Supabase.instance.client;
    
    // Subscribe to sales changes
    _salesChannel = supabase
        .channel('all_sales')
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
            debugPrint('All sales change detected: ${payload.eventType}');
            if (mounted) {
              _fetchSales();
            }
          },
        )
        .subscribe((status, error) {
          debugPrint('All sales subscription status: $status');
        });
  }

  Future<void> _fetchSales() async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    final isOnline = context.read<ConnectivityService>().isOnline;

    if (!isOnline) {
      debugPrint('AllSalesScreen: Offline, loading from cache');
      final cached = await LocalCacheService.getSales();
      if (mounted) {
        setState(() {
          _sales = cached;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('sales')
          .select()
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);
      
      final salesList = response as List;
      await LocalCacheService.saveSales(salesList);

      if (mounted) {
        // Client-side sort to ensure most recent first
        salesList.sort((a, b) {
          try {
            final aCreated = a['created_at'];
            final bCreated = b['created_at'];
            if (aCreated == null || bCreated == null) return 0;
            final aTime = DateTime.parse(aCreated as String);
            final bTime = DateTime.parse(bCreated as String);
            final timeCompare = bTime.compareTo(aTime); // Descending: newest first
            if (timeCompare != 0) return timeCompare;
            final aId = (a['id'] as String?) ?? '';
            final bId = (b['id'] as String?) ?? '';
            return bId.compareTo(aId);
          } catch (e) {
            return 0;
          }
        });
        
        setState(() {
          _sales = salesList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching sales: $e');
      final cached = await LocalCacheService.getSales();
      if (mounted) {
        setState(() {
          if (cached.isNotEmpty) _sales = cached;
          _isLoading = false;
        });
      }
    }
  }

  List<dynamic> get _filteredSales {
    if (_searchQuery.isEmpty) return _sales;
    return _sales.where((s) {
      final invoice = (s['invoice_number'] as String?)?.toLowerCase() ?? '';
      final customer = (s['customer_name'] as String?)?.toLowerCase() ?? '';
      return invoice.contains(_searchQuery.toLowerCase()) || 
             customer.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _deleteSale(String id) async {
    try {
      final supabase = Supabase.instance.client;
      
      // Fetch invoice_number BEFORE deletion for activity logging
      String? invoiceNumber;
      try {
        final saleData = await supabase
            .from('sales')
            .select('invoice_number')
            .eq('id', id)
            .single();
        invoiceNumber = saleData?['invoice_number']?.toString();
      } catch (e) {
        debugPrint('Error fetching invoice number before deletion: $e');
      }
      
      // 1. Revert stock (Now handled by database triggers on sale_items delete)

      // 3. Delete related ledger entries
      await supabase.from('ledger_entries').delete().eq('reference_id', id).eq('reference_type', 'sale');

      // Add: Delete related transaction (reverts wallet)
      await supabase.from('transactions').delete().eq('reference_id', id).eq('reference_type', 'sale');

      // 4. Delete sale (This triggers stock addition)
      await supabase.from('sale_items').delete().eq('sale_id', id);
      await supabase.from('sales').delete().eq('id', id);
      
      _fetchSales();
      
      // Log deletion with invoice_number
      if (mounted) {
        context.read<ShopProvider>().logActivity(
          action: 'Delete Sale',
          entityType: 'sale',
          entityId: id,
          details: {
            'message': 'Permanently deleted sale invoice: ${invoiceNumber ?? id}',
            'invoice_number': invoiceNumber,
          },
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sale deleted and stock reverted'), backgroundColor: Colors.red)
        );
        context.read<DataRefreshNotifier>().notify([
          DataChannel.sales, DataChannel.products, DataChannel.transactions,
          DataChannel.wallets, DataChannel.ledger, DataChannel.activity,
        ]);
      }
    } catch (e) {
      debugPrint('Error deleting sale: $e');
    }
  }
  Future<void> _requestApproval(String refId, String actionType) async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (shopId == null || userId == null) return;

    try {
      final supabase = Supabase.instance.client;
      debugPrint('Creating approval request via RPC: shop=$shopId, user=$userId, action_type=$actionType, ref=$refId');
      
      // Use RPC function to bypass PostgREST schema cache
      final result = await supabase.rpc('insert_approval_request', params: {
        'p_shop_id': shopId,
        'p_requested_by': userId,
        'p_action_type': actionType,
        'p_reference_id': refId,
        'p_details': {'reference_id': refId},
        'p_status': 'pending',
      });
      
      debugPrint('Approval request created via RPC: $result');
      
      // Send notification to owner
      final shop = context.read<ShopProvider>().currentShop;
      if (shop != null) {
        final notificationService = NotificationService(supabase);
        await notificationService.notifyOwnerOfDeletionRequest(
          shopId: shopId,
          entityType: actionType == 'delete_sale' ? 'Sale' : 'Transaction',
          entityName: 'Invoice ID: $refId',
          performedBy: supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Employee',
          ownerId: shop.ownerUserId,
          referenceId: refId,
        );
      }
      
      if (mounted) {
        context.read<ShopProvider>().logActivity(
          action: 'Approval Requested',
          entityType: 'approval',
          entityId: refId,
          details: {
            'action': actionType,
            'message': 'Requested approval for $actionType on entity $refId'
          },
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deletion request sent to owner'), backgroundColor: Colors.orange)
        );
      }
    } catch (e) {
      debugPrint('Error requesting approval: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Sales', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchSales,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search by invoice or customer...',
                  prefixIcon: const Icon(LucideIcons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredSales.isEmpty
                      ? const Center(child: Text('No sales found'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredSales.length,
                          itemBuilder: (context, index) {
                            final sale = _filteredSales[index];
                            final createdAt = DateTime.parse(sale['created_at']);
                            final dateStr = DateFormat('dd MMM, yyyy').format(createdAt);
                            final due = double.tryParse(sale['due_amount'].toString()) ?? 0;

                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Theme.of(context).dividerColor),
                              ),
                              child: ListTile(
                                onTap: () => context.push('/invoice/sale/${sale['id']}'),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(LucideIcons.shoppingBag, 
                                    color: Theme.of(context).colorScheme.primary, size: 20),
                                ),
                                title: Text(sale['invoice_number'] ?? 'No Invoice', 
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(sale['customer_name'] ?? 'Walk-in Customer', 
                                      style: const TextStyle(fontSize: 12)),
                                    Row(
                                      children: [
                                        Text(dateStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                        if (due > 0 && sale['status'] != 'returned') ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text('Due: ৳${due.toStringAsFixed(0)}', 
                                              style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                        if (sale['status'] == 'returned') ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade700,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text('Returned', 
                                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('৳${sale['total_amount']}', 
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    Text('Paid: ৳${sale['paid_amount']}', 
                                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                                onLongPress: () {
                                  final isOnline = context.read<ConnectivityService>().isOnline;
                                  if (!isOnline) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Offline mode – action not available'))
                                    );
                                    return;
                                  }

                                  final auth = context.read<AuthProvider>();
                                  final canEdit = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.editSale);
                                  final canDelete = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.deleteSale);
                                  
                                  showModalBottomSheet(
                                    context: context,
                                    builder: (context) => Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(LucideIcons.rotateCcw, color: Colors.amber),
                                          title: const Text('Return'),
                                          onTap: () {
                                            context.pop();
                                            _showReturnDialog(sale);
                                          },
                                        ),
                                        if (canEdit)
                                          ListTile(
                                            leading: const Icon(LucideIcons.pencil, color: Colors.blue),
                                            title: const Text('Edit'),
                                            onTap: () {
                                              context.pop();
                                              context.push('/new-sale', extra: sale);
                                            },
                                          ),
                                        if (canDelete)
                                          ListTile(
                                            leading: const Icon(LucideIcons.trash2, color: Colors.red),
                                            title: const Text('Delete'),
                                            onTap: () {
                                              context.pop();
                                              _showDeleteConfirmation(sale['id']);
                                            },
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReturnDialog(dynamic sale) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Return Sale'),
        content: const Text('Are you sure you want to return this sale? Stock will be reverted and the sale record will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _handleReturn(sale);
            },
            child: const Text('Confirm Return', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleReturn(dynamic sale) async {
    final id = sale['id'];
    try {
      final supabase = Supabase.instance.client;
      final shopId = context.read<ShopProvider>().currentShop?.id;
      
      // 1. Fetch related transaction to get wallet_id
      final txBatch = await supabase.from('transactions')
          .select('wallet_id, amount')
          .eq('reference_id', id)
          .eq('reference_type', 'sale')
          .limit(1);
      final walletId = txBatch.isNotEmpty ? txBatch[0]['wallet_id'] : null;

      // 2. Create return record for history
      await supabase.from('returns').insert({
        'shop_id': shopId,
        'type': 'sale',
        'reference_id': sale['invoice_number'],
        'amount': sale['total_amount'],
        'note': 'Sale Returned (INV: ${sale['invoice_number']})',
      });

      // 3. Mark the sale as returned instead of deleting
      await supabase.from('sales').update({'status': 'returned'}).eq('id', id);

      // 4. Record reversal transaction (History for Aybay page)
      if (sale['paid_amount'] > 0 && walletId != null) {
        await supabase.from('transactions').insert({
          'shop_id': shopId,
          'wallet_id': walletId,
          'type': 'expense', // Reversing Income
          'amount': sale['paid_amount'],
          'category': 'Sale Return',
          'note': 'Reversal for INV ${sale['invoice_number']}',
          'reference_type': 'sale_return',
          'reference_id': id,
        });
        
        // Update wallet balance (since we aren't deleting original tx)
        await supabase.rpc('decrement_wallet_balance', params: {
          'p_wallet_id': walletId,
          'p_amount': sale['paid_amount'],
        });
      }

      // 5. Record reversal ledger entry (History for Party balance)
      if (sale['party_id'] != null) {
        await supabase.from('ledger_entries').insert({
          'shop_id': shopId,
          'party_id': sale['party_id'],
          'party_name': sale['customer_name'] ?? 'Walk-in Customer',
          'type': 'due', // Reversing a sale (which was a loan/payment_received)
          'amount': sale['total_amount'],
          'notes': 'Sale Returned (INV: ${sale['invoice_number']})',
          'reference_type': 'sale_return',
          'reference_id': id,
        });
      }

      // 6. Delete sale items to trigger STOCK REVERSION (via handle_stock_operation trigger)
      await supabase.from('sale_items').delete().eq('sale_id', id);
      
      _fetchSales();
      if (mounted) {
        context.read<ShopProvider>().logActivity(
          action: 'Return Sale',
          entityType: 'sale',
          entityId: id,
          details: {
            'invoice': sale['invoice_number'],
            'amount': sale['total_amount'],
            'message': 'Returned sale ${sale['invoice_number']} of amount ${sale['total_amount']}'
          },
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sale returned and history preserved'), backgroundColor: Colors.amber)
        );
        context.read<DataRefreshNotifier>().notify([
          DataChannel.sales, DataChannel.products, DataChannel.transactions,
          DataChannel.wallets, DataChannel.ledger, DataChannel.returns, DataChannel.activity,
        ]);
      }
    } catch (e) {
      debugPrint('Error returning sale: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  Future<void> _showDeleteConfirmation(String id) async {
    final isOwner = context.read<ShopProvider>().currentShop?.ownerUserId == Supabase.instance.client.auth.currentUser?.id;
    final auth = context.read<AuthProvider>();
    final hasDeletePermission = Permissions.hasPermission(auth.currentPermissions, AppPermission.deleteSale);
    
    // Determine if user can delete directly
    final canDeleteDirectly = isOwner || hasDeletePermission;
    
    // If not able to delete directly, check if there's already a pending request for this sale
    if (!canDeleteDirectly) {
      try {
        final supabase = Supabase.instance.client;
        final shopId = context.read<ShopProvider>().currentShop?.id;
        final userId = supabase.auth.currentUser?.id;
        
        if (shopId != null && userId != null) {
          final existingRequests = await supabase
              .from('approval_requests')
              .select('id, status')
              .eq('shop_id', shopId)
              .eq('reference_id', id)
              .eq('requested_by', userId)
              .inFilter('action_type', ['delete_sale', 'return_sale'])
              .eq('status', 'pending');
          
          if (existingRequests.isNotEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('A deletion request for this sale is already pending'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
        }
      } catch (e) {
        debugPrint('Error checking for existing requests: $e');
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(canDeleteDirectly ? 'Delete Sale' : 'Request Deletion'),
        content: Text(canDeleteDirectly
          ? 'Are you sure you want to delete this sale? This action cannot be undone.'
          : 'You do not have permission to delete sales. Would you like to send a deletion request to the shop owner?'),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              context.pop();
              if (canDeleteDirectly) {
                _deleteSale(id);
              } else {
                _requestApproval(id, 'delete_sale');
              }
            },
            child: Text(canDeleteDirectly ? 'Delete' : 'Send Request', style: TextStyle(color: canDeleteDirectly ? Colors.red : Colors.orange)),
          ),
        ],
      ),
    );
  }
}
