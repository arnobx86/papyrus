import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../core/shop_provider.dart';
import '../../core/auth_provider.dart';
import '../../core/permissions.dart';
import '../../core/notification_service.dart';
import '../../core/connectivity_service.dart';
import '../../core/local_cache_service.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  bool _isLoading = true;
  List<dynamic> _products = [];
  String _searchQuery = '';
  RealtimeChannel? _productsChannel;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupRealtimeSubscription();
    });
  }

  @override
  void dispose() {
    _productsChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    try {
      final shopId = context.read<ShopProvider>().currentShop?.id;
      if (shopId == null) {
        debugPrint('ProductsScreen: No shop ID, skipping real-time subscription');
        return;
      }

      final supabase = Supabase.instance.client;
      debugPrint('ProductsScreen: Setting up real-time subscription for shop $shopId');
      
      _productsChannel = supabase
        .channel('products')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'shop_id',
            value: shopId,
          ),
          callback: (payload) {
            debugPrint('ProductsScreen: Real-time event: ${payload.eventType} for product ${payload.newRecord?['id'] ?? payload.oldRecord?['id']}');
            _handleProductChange(payload);
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            debugPrint('ProductsScreen: Subscription error: $error');
          } else {
            debugPrint('ProductsScreen: Subscription status: $status');
          }
        });
    } catch (e) {
      debugPrint('ProductsScreen: Error setting up real-time subscription: $e');
    }
  }

  void _handleProductChange(PostgresChangePayload payload) {
    try {
      final newRecord = payload.newRecord;
      final oldRecord = payload.oldRecord;
      final eventType = payload.eventType;

      debugPrint('ProductsScreen: Handling $eventType for product ${newRecord?['id'] ?? oldRecord?['id']}');

      setState(() {
        if (eventType == 'UPDATE') {
          final productId = newRecord['id'];
          final index = _products.indexWhere((p) => p['id'] == productId);
          if (index != -1) {
            // Update the existing product with new data
            _products[index] = newRecord;
            debugPrint('ProductsScreen: Updated product $productId, new stock: ${newRecord['stock']}');
          } else {
            // This shouldn't happen for updates, but add it just in case
            _products.add(newRecord);
            _products.sort((a, b) => a['name'].compareTo(b['name']));
            debugPrint('ProductsScreen: Added missing product $productId');
          }
        } else if (eventType == 'INSERT') {
          // Add new product
          _products.add(newRecord);
          // Sort to maintain order
          _products.sort((a, b) => a['name'].compareTo(b['name']));
          debugPrint('ProductsScreen: Inserted new product ${newRecord['id']}');
        } else if (eventType == 'DELETE') {
          final productId = oldRecord['id'];
          _products.removeWhere((p) => p['id'] == productId);
          debugPrint('ProductsScreen: Deleted product $productId');
        }
      });
    } catch (e) {
      debugPrint('ProductsScreen: Error in _handleProductChange: $e');
    }
  }

  Future<void> _fetchProducts() async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    final isOnline = context.read<ConnectivityService>().isOnline;

    if (!isOnline) {
      debugPrint('ProductsScreen: Offline, loading from cache');
      final cached = await LocalCacheService.getProducts();
      if (mounted) {
        setState(() {
          _products = cached;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('products')
          .select()
          .eq('shop_id', shopId)
          .order('name');
      
      final products = response as List;
      await LocalCacheService.saveProducts(products);

      if (mounted) {
        setState(() {
          _products = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching products: $e');
      // Fallback to cache on error
      final cached = await LocalCacheService.getProducts();
      if (mounted) {
        setState(() {
          if (cached.isNotEmpty) _products = cached;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteProduct(String id) async {
    try {
      final supabase = Supabase.instance.client;
      final shopProvider = context.read<ShopProvider>();
      final auth = context.read<AuthProvider>();
      final shop = shopProvider.currentShop;
      
      // Find the product to get its name
      final product = _products.firstWhere((p) => p['id'] == id);
      final productName = product['name']?.toString() ?? 'Unknown Product';
      
      // Check if current user is the owner
      final isOwner = shop?.ownerUserId == supabase.auth.currentUser?.id;
      
      // If not owner, check if there's already a pending request for this product
      if (!isOwner) {
        try {
          final shopId = shop?.id;
          final userId = supabase.auth.currentUser?.id;
          
          if (shopId != null && userId != null) {
            final existingRequests = await supabase
                .from('approval_requests')
                .select('id, status')
                .eq('shop_id', shopId)
                .eq('reference_id', id)
                .eq('requested_by', userId)
                .eq('action_type', 'delete_product')
                .eq('status', 'pending');
            
            if (existingRequests.isNotEmpty) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('A deletion request for this product is already pending'),
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
        // Create approval request for non-owners using RPC function
        debugPrint('Creating product deletion approval request via RPC: shop=${shop?.id}, product=$id, name=$productName');
        
        // Use RPC function to bypass PostgREST schema cache
        final result = await supabase.rpc('insert_approval_request', params: {
          'p_shop_id': shop?.id,
          'p_requested_by': supabase.auth.currentUser?.id,  // Changed from p_requester_id to p_requested_by
          'p_action_type': 'delete_product',
          'p_reference_id': id,
          'p_details': {
            'entity_type': 'product',
            'entity_name': productName,
            'reference_id': id,
            'requested_by_name': supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Employee',
          },
          'p_status': 'pending',
        });
        debugPrint('Product deletion approval request created via RPC: $result');
        
        // Send notification to owner
        if (shop != null) {
          final notificationService = NotificationService(supabase);
          await notificationService.notifyOwnerOfDeletionRequest(
            shopId: shop.id,
            entityType: 'Product',
            entityName: productName,
            performedBy: supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Employee',
            ownerId: shop.ownerUserId,
            referenceId: id,
          );
        }

        // Log the approval request
        if (mounted) {
          shopProvider.logActivity(
            action: 'Approval Requested',
            entityType: 'approval',
            entityId: id,
            details: {
              'type': 'delete_product',
              'product': productName,
              'message': 'Requested approval to delete product: $productName'
            },
          );
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Deletion request sent for approval'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        // Owner can delete directly (or could also require approval)
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Product'),
            content: Text('Are you sure you want to delete "$productName"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        
        if (confirmed == true) {
          await supabase.from('products').delete().eq('id', id);
          await shopProvider.logActivity(
            action: 'Delete Product',
            entityType: 'product',
            entityId: id,
            details: {'message': 'Deleted product: $productName'},
          );
          _fetchProducts();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product deleted')));
          }
        }
      }
    } catch (e) {
      debugPrint('Error deleting product: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _products.where((p) {
      final name = p['name'].toString().toLowerCase();
      final sku = p['sku']?.toString().toLowerCase() ?? '';
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || sku.contains(q);
    }).toList();

    final auth = context.watch<AuthProvider>();
    final canManage = Permissions.hasPermission(auth.currentPermissions, AppPermission.manageProducts);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (context.read<ConnectivityService>().isOnline && (auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.manageProducts)))
            IconButton(
              icon: const Icon(LucideIcons.plus),
              onPressed: () async {
                final refresh = await context.push<bool>('/add-product');
                if (refresh == true) _fetchProducts();
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchProducts,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  prefixIcon: const Icon(LucideIcons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  fillColor: Theme.of(context).colorScheme.surface,
                  filled: true,
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.box, size: 64, color: Colors.grey.withOpacity(0.3)),
                              const SizedBox(height: 16),
                              Text(_searchQuery.isEmpty ? 'No products yet' : 'No products found', style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final p = filtered[index];
                            final stock = double.tryParse(p['stock'].toString()) ?? 0;
                            final minStock = double.tryParse(p['min_stock'].toString()) ?? 0;
                            final isLow = stock <= minStock;

                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 12),
                              color: isLow ? Colors.red.withOpacity(0.05) : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: isLow ? Colors.red.withOpacity(0.3) : Theme.of(context).dividerColor),
                              ),
                              child: ListTile(
                                onLongPress: () => _showContextMenu(context, p),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: (isLow ? Colors.red : Theme.of(context).colorScheme.primary).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: p['image_url'] != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          p['image_url'],
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Icon(LucideIcons.box, color: isLow ? Colors.red : Theme.of(context).colorScheme.primary, size: 20),
                                        ),
                                      )
                                    : Icon(LucideIcons.box, color: isLow ? Colors.red : Theme.of(context).colorScheme.primary, size: 20),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p['name'], 
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isLow) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                                        child: const Text('LOW', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                      ),
                                    ]
                                  ],
                                ),
                                subtitle: Text(
                                  'SKU: ${p['sku'] ?? '-'} • Stock: $stock ${p['unit'] ?? 'pcs'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: isLow ? Colors.red : Colors.grey),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('৳${(p['purchase_price'] ?? p['cost_price']) ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const Text('Purchase Price', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: (canManage && context.read<ConnectivityService>().isOnline) ? FloatingActionButton(
        onPressed: () async {
          final refresh = await context.push<bool>('/add-product');
          if (refresh == true) _fetchProducts();
        },
        child: const Icon(LucideIcons.plus),
      ) : null,
    );
  }

  void _showContextMenu(BuildContext context, dynamic product) {
    final auth = context.read<AuthProvider>();
    final canManage = Permissions.hasPermission(auth.currentPermissions, AppPermission.manageProducts);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canManage && context.read<ConnectivityService>().isOnline) ...[
                ListTile(
                  leading: const Icon(LucideIcons.pencil),
                  title: const Text('Edit'),
                  onTap: () async {
                    Navigator.pop(context);
                    final refresh = await context.push<bool>('/add-product', extra: product);
                    if (refresh == true) _fetchProducts();
                  },
                ),
                ListTile(
                  leading: const Icon(LucideIcons.trash2, color: Colors.red),
                  title: const Text('Delete', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteProduct(product['id']);
                  },
                ),
              ] else if (!context.read<ConnectivityService>().isOnline)
                const ListTile(
                  leading: Icon(LucideIcons.wifiOff),
                  title: Text('Offline mode – action not available'),
                )
              else 
                const ListTile(
                  leading: Icon(LucideIcons.info),
                  title: Text('No edit permission'),
                ),
            ],
          ),
        );
      },
    );
  }
}
