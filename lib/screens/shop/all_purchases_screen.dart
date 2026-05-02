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

class AllPurchasesScreen extends StatefulWidget {
  const AllPurchasesScreen({super.key});

  @override
  State<AllPurchasesScreen> createState() => _AllPurchasesScreenState();
}

class _AllPurchasesScreenState extends State<AllPurchasesScreen> {
  bool _isLoading = true;
  List<dynamic> _purchases = [];
  String _searchQuery = '';
  RealtimeChannel? _purchasesChannel;

  @override
  void initState() {
    super.initState();
    _fetchPurchases();
    _setupRealtime();
  }

  @override
  void dispose() {
    _purchasesChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtime() {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    final supabase = Supabase.instance.client;
    
    // Subscribe to purchases changes
    _purchasesChannel = supabase
        .channel('all_purchases')
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
            debugPrint('All purchases change detected: ${payload.eventType}');
            if (mounted) {
              _fetchPurchases();
            }
          },
        )
        .subscribe((status, error) {
          debugPrint('All purchases subscription status: $status');
        });
  }

  Future<void> _fetchPurchases() async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    final isOnline = context.read<ConnectivityService>().isOnline;

    if (!isOnline) {
      debugPrint('AllPurchasesScreen: Offline, loading from cache');
      final cached = await LocalCacheService.getPurchases();
      if (mounted) {
        setState(() {
          _purchases = cached;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('purchases')
          .select()
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);
      
      final purchasesList = response as List;
      await LocalCacheService.savePurchases(purchasesList);

      if (mounted) {
        // Client-side sort
        purchasesList.sort((a, b) {
          try {
            final aCreated = a['created_at'];
            final bCreated = b['created_at'];
            if (aCreated == null || bCreated == null) return 0;
            final aTime = DateTime.parse(aCreated as String);
            final bTime = DateTime.parse(bCreated as String);
            final timeCompare = bTime.compareTo(aTime);
            if (timeCompare != 0) return timeCompare;
            final aId = (a['id'] as String?) ?? '';
            final bId = (b['id'] as String?) ?? '';
            return bId.compareTo(aId);
          } catch (e) {
            return 0;
          }
        });
        
        setState(() {
          _purchases = purchasesList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching purchases: $e');
      final cached = await LocalCacheService.getPurchases();
      if (mounted) {
        setState(() {
          if (cached.isNotEmpty) _purchases = cached;
          _isLoading = false;
        });
      }
    }
  }

  List<dynamic> get _filteredPurchases {
    if (_searchQuery.isEmpty) return _purchases;
    return _purchases.where((p) {
      final invoice = (p['invoice_number'] as String?)?.toLowerCase() ?? '';
      final supplier = (p['supplier_name'] as String?)?.toLowerCase() ?? '';
      return invoice.contains(_searchQuery.toLowerCase()) || 
             supplier.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _deletePurchase(String id) async {
    try {
      final supabase = Supabase.instance.client;
      
      // Fetch invoice_number BEFORE deletion for activity logging
      String? invoiceNumber;
      try {
        final purchaseData = await supabase
            .from('purchases')
            .select('invoice_number')
            .eq('id', id)
            .single();
        invoiceNumber = purchaseData?['invoice_number']?.toString();
      } catch (e) {
        debugPrint('Error fetching invoice number before deletion: $e');
      }
      
      // 1. Revert stock (Now handled by database triggers on purchase_items delete)

      // 3. Delete related ledger entries
      await supabase.from('ledger_entries').delete().eq('reference_id', id).eq('reference_type', 'purchase');

      // Add: Delete related transaction (reverts wallet)
      await supabase.from('transactions').delete().eq('reference_id', id).eq('reference_type', 'purchase');

      // 4. Delete purchase (This triggers stock subtraction)
      await supabase.from('purchase_items').delete().eq('purchase_id', id);
      await supabase.from('purchases').delete().eq('id', id);
      
      _fetchPurchases();
      
      // Log deletion with invoice_number
      if (mounted) {
        context.read<ShopProvider>().logActivity(
          action: 'Delete Purchase',
          entityType: 'purchase',
          entityId: id,
          details: {
            'message': 'Permanently deleted purchase invoice: ${invoiceNumber ?? id}',
            'invoice_number': invoiceNumber,
          },
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase deleted and stock reverted'), backgroundColor: Colors.red)
        );
        context.read<DataRefreshNotifier>().notify([
          DataChannel.purchases, DataChannel.products, DataChannel.transactions,
          DataChannel.wallets, DataChannel.ledger, DataChannel.activity,
        ]);
      }
    } catch (e) {
      debugPrint('Error deleting purchase: $e');
    }
  }
  Future<void> _requestApproval(String refId, String actionType) async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (shopId == null || userId == null) return;

    try {
      final supabase = Supabase.instance.client;
      debugPrint('Creating purchase approval request via RPC: shop=$shopId, user=$userId, action_type=$actionType, ref=$refId');
      
      // Use RPC function to bypass PostgREST schema cache
      final result = await supabase.rpc('insert_approval_request', params: {
        'p_shop_id': shopId,
        'p_requested_by': userId,  // Changed from p_requester_id to p_requested_by
        'p_action_type': actionType,
        'p_reference_id': refId,
        'p_details': {'reference_id': refId},
        'p_status': 'pending',
      });
      
      debugPrint('Purchase approval request created via RPC: $result');
      
      // Send notification to owner
      final shop = context.read<ShopProvider>().currentShop;
      if (shop != null) {
        final notificationService = NotificationService(supabase);
        await notificationService.notifyOwnerOfDeletionRequest(
          shopId: shopId,
          entityType: actionType == 'delete_purchase' ? 'Purchase' : 'Transaction',
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
        title: const Text('All Purchases', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchPurchases,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search by invoice or supplier...',
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
                  : _filteredPurchases.isEmpty
                      ? const Center(child: Text('No purchases found'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredPurchases.length,
                          itemBuilder: (context, index) {
                            final purchase = _filteredPurchases[index];
                            final createdAt = DateTime.parse(purchase['created_at']);
                            final dateStr = DateFormat('dd MMM, yyyy').format(createdAt);
                            final due = double.tryParse(purchase['due_amount'].toString()) ?? 0;

                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Theme.of(context).dividerColor),
                              ),
                              child: ListTile(
                                onTap: () => context.push('/invoice/purchase/${purchase['id']}'),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(LucideIcons.shoppingCart, 
                                    color: Colors.amber, size: 20),
                                ),
                                title: Text(purchase['invoice_number'] ?? 'No Invoice', 
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(purchase['supplier_name'] ?? 'Unknown Supplier', 
                                      style: const TextStyle(fontSize: 12)),
                                    Row(
                                      children: [
                                        Text(dateStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                        if (due > 0 && purchase['status'] != 'returned') ...[
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
                                        if (purchase['status'] == 'returned') ...[
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
                                    Text('৳${purchase['total_amount']}', 
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    Text('Paid: ৳${purchase['paid_amount']}', 
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
                                  final canEdit = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.editPurchase);
                                  final canDelete = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.deletePurchase);

                                  showModalBottomSheet(
                                    context: context,
                                    builder: (context) => Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(LucideIcons.rotateCcw, color: Colors.purple),
                                          title: const Text('Return'),
                                          onTap: () {
                                            context.pop();
                                            _showReturnDialog(purchase);
                                          },
                                        ),
                                        if (canEdit)
                                          ListTile(
                                            leading: const Icon(LucideIcons.pencil, color: Colors.blue),
                                            title: const Text('Edit'),
                                            onTap: () {
                                              context.pop();
                                              context.push('/new-purchase', extra: purchase);
                                            },
                                          ),
                                        if (canDelete)
                                          ListTile(
                                            leading: const Icon(LucideIcons.trash2, color: Colors.red),
                                            title: const Text('Delete'),
                                            onTap: () {
                                              context.pop();
                                              _showDeleteConfirmation(purchase['id']);
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

  void _showReturnDialog(dynamic purchase) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Return Purchase'),
        content: const Text('Are you sure you want to return this purchase? Stock will be reduced and the purchase record will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _handleReturn(purchase);
            },
            child: const Text('Confirm Return', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleReturn(dynamic purchase) async {
    final id = purchase['id'];
    try {
      final supabase = Supabase.instance.client;
      final shopId = context.read<ShopProvider>().currentShop?.id;
      
      // 1. Fetch related transaction to get wallet_id
      final txBatch = await supabase.from('transactions')
          .select('wallet_id, amount')
          .eq('reference_id', id)
          .eq('reference_type', 'purchase')
          .limit(1);
      final walletId = txBatch.isNotEmpty ? txBatch[0]['wallet_id'] : null;

      // 2. Create return record for history
      await supabase.from('returns').insert({
        'shop_id': shopId,
        'type': 'purchase',
        'reference_id': purchase['invoice_number'],
        'amount': purchase['total_amount'],
        'note': 'Purchase Returned (INV: ${purchase['invoice_number']})',
      });

      // 3. Mark the purchase as returned instead of deleting
      await supabase.from('purchases').update({'status': 'returned'}).eq('id', id);

      // 4. Record reversal transaction (History for Aybay page)
      if (purchase['paid_amount'] > 0 && walletId != null) {
        await supabase.from('transactions').insert({
          'shop_id': shopId,
          'wallet_id': walletId,
          'type': 'income', // Reversing Expense
          'amount': purchase['paid_amount'],
          'category': 'Purchase Return',
          'note': 'Reversal for INV ${purchase['invoice_number']}',
          'reference_type': 'purchase_return',
          'reference_id': id,
        });
        
        // Update wallet balance (since we aren't deleting original tx)
        await supabase.rpc('increment_wallet_balance', params: {
          'p_wallet_id': walletId,
          'p_amount': purchase['paid_amount'],
        });
      }

      // 5. Record reversal ledger entry (History for Party balance)
      if (purchase['supplier_id'] != null) {
        await supabase.from('ledger_entries').insert({
          'shop_id': shopId,
          'party_id': purchase['supplier_id'],
          'party_name': purchase['supplier_name'] ?? 'Unknown Supplier',
          'type': 'loan', // Reversing a purchase (which was 'due')
          'amount': purchase['total_amount'],
          'notes': 'Purchase Returned (INV: ${purchase['invoice_number']})',
          'reference_type': 'purchase_return',
          'reference_id': id,
        });
      }

      // 6. Delete items to trigger STOCK REDUCTION (via handle_stock_operation trigger)
      await supabase.from('purchase_items').delete().eq('purchase_id', id);
      
      _fetchPurchases();
      if (mounted) {
        context.read<ShopProvider>().logActivity(
          action: 'Return Purchase',
          entityType: 'purchase',
          entityId: id,
          details: {
            'invoice': purchase['invoice_number'],
            'amount': purchase['total_amount'],
            'message': 'Returned purchase ${purchase['invoice_number']} of amount ${purchase['total_amount']}'
          },
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase returned and history preserved'), backgroundColor: Colors.purple)
        );
        context.read<DataRefreshNotifier>().notify([
          DataChannel.purchases, DataChannel.products, DataChannel.transactions,
          DataChannel.wallets, DataChannel.ledger, DataChannel.returns, DataChannel.activity,
        ]);
      }
    } catch (e) {
      debugPrint('Error returning purchase: $e');
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
    final hasDeletePermission = Permissions.hasPermission(auth.currentPermissions, AppPermission.deletePurchase);
    
    // Determine if user can delete directly
    final canDeleteDirectly = isOwner || hasDeletePermission;
    
    // If not able to delete directly, check if there's already a pending request for this purchase
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
              .inFilter('action_type', ['delete_purchase', 'return_purchase'])
              .eq('status', 'pending');
          
          if (existingRequests.isNotEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('A deletion request for this purchase is already pending'),
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
        title: Text(canDeleteDirectly ? 'Delete Purchase' : 'Request Deletion'),
        content: Text(canDeleteDirectly
          ? 'Are you sure you want to delete this purchase? This action cannot be undone.'
          : 'You do not have permission to delete purchases. Would you like to send a deletion request to the shop owner?'),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              context.pop();
              if (canDeleteDirectly) {
                _deletePurchase(id);
              } else {
                _requestApproval(id, 'delete_purchase');
              }
            },
            child: Text(canDeleteDirectly ? 'Delete' : 'Send Request', style: TextStyle(color: canDeleteDirectly ? Colors.red : Colors.orange)),
          ),
        ],
      ),
    );
  }
}
