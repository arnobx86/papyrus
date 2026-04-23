import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/shop_provider.dart';
import '../../core/notification_service.dart';
import '../../core/auth_provider.dart';
import '../../core/permissions.dart';
import '../../core/data_refresh_notifier.dart';

class AyBayScreen extends StatefulWidget {
  const AyBayScreen({super.key});

  @override
  State<AyBayScreen> createState() => _AyBayScreenState();
}

class _AyBayScreenState extends State<AyBayScreen> {
  String _activeTab = 'total';
  String _searchQuery = '';
  bool _isLoading = true;
  List<dynamic> _transactions = [];
  List<dynamic> _wallets = [];
  List<dynamic> _filteredTransactions = [];
  RealtimeChannel? _transactionsChannel;
  RealtimeChannel? _walletsChannel;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _setupRealtime();
  }

  @override
  void dispose() {
    _transactionsChannel?.unsubscribe();
    _walletsChannel?.unsubscribe();
    super.dispose();
  }

  // Helper method to determine transaction display properties
  Map<String, dynamic> _getTransactionDisplayProperties(Map<String, dynamic> transaction) {
    final type = transaction['type'] as String? ?? '';
    final amount = double.tryParse(transaction['amount'].toString()) ?? 0.0;
    
    // Determine if transaction represents money coming IN (positive) or going OUT (negative)
    bool isMoneyIn = false;
    bool isMoneyOut = false;
    Color color = Colors.grey;
    IconData icon = LucideIcons.circle;
    String sign = '';
    
    switch (type) {
      case 'income':
      case 'received':
      case 'sale':
        isMoneyIn = true;
        color = Colors.teal;
        icon = LucideIcons.arrowUpRight;
        sign = '+';
        break;
      case 'expense':
      case 'payment':
      case 'purchase':
        isMoneyOut = true;
        color = Colors.red;
        icon = LucideIcons.arrowDownLeft;
        sign = '-';
        break;
      case 'payable':
      case 'receivable':
        // Non-cash movements - use neutral styling
        color = Colors.orange;
        icon = LucideIcons.fileText;
        sign = ''; // No sign for non-cash movements
        break;
      default:
        color = Colors.grey;
        icon = LucideIcons.circle;
        sign = '';
    }
    
    return {
      'type': type,
      'isMoneyIn': isMoneyIn,
      'isMoneyOut': isMoneyOut,
      'color': color,
      'icon': icon,
      'sign': sign,
      'amount': amount,
    };
  }

  void _setupRealtime() {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    final supabase = Supabase.instance.client;
    
    // Subscribe to transactions changes
    _transactionsChannel = supabase
        .channel('aybay_transactions')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'shop_id',
            value: shopId,
          ),
          callback: (payload) {
            debugPrint('AyBay transactions change detected: ${payload.eventType}');
            if (mounted) {
              _fetchData();
            }
          },
        )
        .subscribe((status, error) {
          debugPrint('AyBay transactions subscription status: $status');
        });

    // Subscribe to wallets changes
    _walletsChannel = supabase
        .channel('aybay_wallets')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'shop_id',
            value: shopId,
          ),
          callback: (payload) {
            debugPrint('AyBay wallets change detected: ${payload.eventType}');
            if (mounted) {
              _fetchData();
            }
          },
        )
        .subscribe((status, error) {
          debugPrint('AyBay wallets subscription status: $status');
        });
  }

  Future<void> _editTransaction(Map<String, dynamic> transaction) async {
    final isIncome = transaction['type'] == 'income';
    final amountController = TextEditingController(text: transaction['amount'].toString());
    final noteController = TextEditingController(text: transaction['note']?.toString() ?? '');
    String selectedType = isIncome ? 'income' : 'expense';
    String? selectedWalletId = transaction['wallet_id'];
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Transaction'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Type Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Income'),
                            selected: selectedType == 'income',
                            onSelected: (selected) {
                              setDialogState(() {
                                selectedType = 'income';
                              });
                            },
                            selectedColor: Colors.teal.shade100,
                            labelStyle: TextStyle(
                              color: selectedType == 'income' ? Colors.teal : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Expense'),
                            selected: selectedType == 'expense',
                            onSelected: (selected) {
                              setDialogState(() {
                                selectedType = 'expense';
                              });
                            },
                            selectedColor: Colors.red.shade100,
                            labelStyle: TextStyle(
                              color: selectedType == 'expense' ? Colors.red : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Amount Field
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                      prefixText: '৳ ',
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Wallet Dropdown
                  DropdownButtonFormField<String>(
                    value: _wallets.any((w) => w['id'] == selectedWalletId) ? selectedWalletId : null,
                    decoration: const InputDecoration(
                      labelText: 'Wallet',
                      border: OutlineInputBorder(),
                    ),
                    items: _wallets.map((w) {
                      return DropdownMenuItem<String>(
                        value: w['id'] as String?,
                        child: Text(w['name'] as String),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedWalletId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // Note Field
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note (Optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              StatefulBuilder(
                builder: (context, setBtnState) {
                  return ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final amount = double.tryParse(amountController.text);
                            if (amount == null || amount <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please enter a valid amount')),
                              );
                              return;
                            }

                            if (selectedType == 'expense' && selectedWalletId != null) {
                              Map<String, dynamic>? wallet;
                              for (var w in _wallets) {
                                if (w['id'] == selectedWalletId) {
                                  wallet = w as Map<String, dynamic>;
                                  break;
                                }
                              }
                              if (wallet != null) {
                                final currentBalance = double.tryParse(wallet['balance'].toString()) ?? 0.0;
                                // Simple validation: check if amount is greater than current balance
                                // (Note: this doesn't fully account for the old amount if editing the same expense,
                                // but serves as a basic necessary validation constraint)
                                final oldAmount = double.tryParse(transaction['amount'].toString()) ?? 0.0;
                                final oldType = transaction['type'];
                                final oldWalletId = transaction['wallet_id'];
                                
                                double effectiveBalance = currentBalance;
                                if (oldWalletId == selectedWalletId && oldType == 'expense') {
                                  effectiveBalance += oldAmount; // Add back the old expense before checking new expense
                                }
                                
                                if (amount > effectiveBalance) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Insufficient wallet balance for this expense')),
                                  );
                                  return;
                                }
                              }
                            }

                            setBtnState(() => isSaving = true);
                            try {
                              final supabase = Supabase.instance.client;
                              await supabase.from('transactions').update({
                                'type': selectedType,
                                'amount': amount,
                                'note': noteController.text.isEmpty ? null : noteController.text,
                                'wallet_id': selectedWalletId,
                              }).eq('id', transaction['id']);

                              if (mounted) {
                                Navigator.pop(context);
                                
                                // Log the editing of transaction
                                context.read<ShopProvider>().logActivity(
                                  action: 'Edit Transaction',
                                  details: {
                                    'message': 'Edited transaction ${transaction['category'] ?? 'Others'} to amount $amount',
                                  },
                                );

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Transaction updated successfully')),
                                );
                              }
                            } catch (e) {
                              debugPrint('Error updating transaction: $e');
                              if (mounted) {
                                setBtnState(() => isSaving = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            }
                          },
                    child: isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
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
          entityType: 'Transaction',
          entityName: 'Transaction ID: $refId',
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
            'message': 'Requested approval for $actionType on transaction $refId'
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

  Future<void> _deleteTransaction(Map<String, dynamic> transaction) async {
    final isOwner = context.read<ShopProvider>().currentShop?.ownerUserId == Supabase.instance.client.auth.currentUser?.id;
    final auth = context.read<AuthProvider>();
    final hasDeletePermission = Permissions.hasPermission(auth.currentPermissions, AppPermission.deletePurchase); // Fallback permission, but typically logic binds on isOwner
    final canDeleteDirectly = isOwner || hasDeletePermission;
    
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
              .eq('reference_id', transaction['id'])
              .eq('requested_by', userId)
              .eq('action_type', 'delete_transaction')
              .eq('status', 'pending');
          
          if (existingRequests.isNotEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('A deletion request for this transaction is already pending'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
        }
      } catch (e) {
        debugPrint('Error checking existing requests: $e');
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(canDeleteDirectly ? 'Delete Transaction' : 'Request Deletion'),
        content: Text(canDeleteDirectly 
          ? 'Are you sure you want to delete this transaction? This action cannot be undone.'
          : 'You do not have permission to delete transactions. Would you like to send a deletion request to the shop owner?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: canDeleteDirectly ? Colors.red : Colors.orange),
            child: Text(canDeleteDirectly ? 'Delete' : 'Send Request'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (canDeleteDirectly) {
        try {
          final supabase = Supabase.instance.client;
          
          // Bidirectional sync: If this transaction came from the Ledger, delete it there too
          if (transaction['reference_type'] == 'manual' && transaction['reference_id'] != null) {
            await supabase.from('ledger_entries').delete().eq('id', transaction['reference_id']);
          }
          
          await supabase.from('transactions').delete().eq('id', transaction['id']);

          if (mounted) {
            // Notify other screens to refresh
            context.read<DataRefreshNotifier>().notify([
              DataChannel.transactions,
              DataChannel.wallets,
              DataChannel.ledger,
            ]);

            // Log the deletion of transaction
            context.read<ShopProvider>().logActivity(
              action: 'Delete Transaction',
              details: {
                'message': 'Deleted transaction ${transaction['category'] ?? 'Others'} of amount ${transaction['amount']}',
              },
            );

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Transaction deleted successfully')),
            );
          }
        } catch (e) {
          debugPrint('Error deleting transaction: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error deleting transaction: $e')),
            );
          }
        }
      } else {
        await _requestApproval(transaction['id'].toString(), 'delete_transaction');
      }
    }
  }

  Future<void> _fetchData() async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    if (mounted) {
      setState(() => _isLoading = true);
    }
    
    try {
      final supabase = Supabase.instance.client;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();

      // Fetch transactions based on active tab
      var query = supabase
          .from('transactions')
          .select()
          .eq('shop_id', shopId);

      if (_activeTab == 'today') {
        query = query.gte('created_at', todayStart);
      } else if (_activeTab == 'monthly') {
        query = query.gte('created_at', monthStart);
      }

      final txResponse = await query.order('created_at', ascending: false);

      // Always fetch all wallets (balance is always total)
      final walletResponse = await supabase
          .from('wallets')
          .select()
          .eq('shop_id', shopId)
          .order('name');

      if (mounted) {
        final txList = txResponse as List;
        // Log BEFORE sorting
        debugPrint('=== AYBAY TRANSACTIONS ORDERING DEBUG ===');
        if (txList.isNotEmpty) {
          debugPrint('BEFORE sort - First item: ${txList.first['created_at']}, Last item: ${txList.last['created_at']}');
        }
        debugPrint('Total transactions: ${txList.length}');
        
        // Client-side sort to ensure most recent first by actual transaction date
        txList.sort((a, b) {
          try {
            // Use transaction_date if available, otherwise fall back to created_at
            final aDate = a['transaction_date'] ?? a['created_at'];
            final bDate = b['transaction_date'] ?? b['created_at'];
            
            if (aDate == null || bDate == null) return 0;
            
            final aTime = DateTime.parse(aDate.toString());
            final bTime = DateTime.parse(bDate.toString());
            
            final timeCompare = bTime.compareTo(aTime); // Descending: newest first
            if (timeCompare != 0) return timeCompare;
            
            // Secondary sort by created_at (if transaction_dates were the same)
            final aCreated = a['created_at'] != null ? DateTime.parse(a['created_at'].toString()) : DateTime(0);
            final bCreated = b['created_at'] != null ? DateTime.parse(b['created_at'].toString()) : DateTime(0);
            final createdCompare = bCreated.compareTo(aCreated);
            if (createdCompare != 0) return createdCompare;

            // Final fallback by id
            final aId = (a['id'] as String?) ?? '';
            final bId = (b['id'] as String?) ?? '';
            return bId.compareTo(aId);
          } catch (e) {
            debugPrint('Error sorting transactions: $e');
            return 0;
          }
        });
        
        // Log AFTER sorting
        if (txList.isNotEmpty) {
          debugPrint('AFTER sort - First item: ${txList.first['created_at']}, Last item: ${txList.last['created_at']}');
        }
        debugPrint('=== END AYBAY TRANSACTIONS ORDERING DEBUG ===');
        // Compute filtered transactions once
        final filtered = _computeFilteredTransactions(txList);
        
        // Debug logging for FILTERED list with FULL details
        debugPrint('=== AYBAY FILTERED TRANSACTIONS DEBUG (FULL) ===');
        debugPrint('Filtered count: ${filtered.length}');
        if (filtered.isNotEmpty) {
          debugPrint('FILTERED First item: ${filtered.first['created_at']}, type=${filtered.first['type']}');
          debugPrint('FILTERED Last item: ${filtered.last['created_at']}, type=${filtered.last['type']}');
          // Log ALL filtered items in order with full details
          for (var i = 0; i < filtered.length; i++) {
            final tx = filtered[i];
            debugPrint('  [$i] created_at=${tx['created_at']}, type=${tx['type']}, category=${tx['category']}, id=${tx['id']}');
          }
        }
        debugPrint('=== END AYBAY FILTERED TRANSACTIONS DEBUG (FULL) ===');
        
        setState(() {
          _transactions = txList;
          _wallets = walletResponse as List;
          _filteredTransactions = filtered;
          _isLoading = false;
        });
        
        // Debug logging
        debugPrint('AyBay: Fetched ${_transactions.length} transactions, showing ${_filteredTransactions.length}');
        if (_transactions.isNotEmpty) {
          debugPrint('AyBay: First transaction type: ${_transactions.first['type']}');
          debugPrint('AyBay: First transaction created_at: ${_transactions.first['created_at']}');
          debugPrint('AyBay: Last transaction created_at: ${_transactions.last['created_at']}');
        }
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<dynamic> _computeFilteredTransactions(List<dynamic> transactions) {
    // Show ALL transaction types (income, expense, payment, received, payable, receivable, sale, purchase)
    var list = transactions.toList();
    
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((t) {
        final category = (t['category'] as String? ?? '').toLowerCase();
        final note = (t['note'] as String?)?.toLowerCase() ?? '';
        return category.contains(q) || note.contains(q);
      }).toList();
    }
    return list;
  }

  void _updateFilteredTransactions() {
    setState(() {
      _filteredTransactions = _computeFilteredTransactions(_transactions);
    });
  }

  // Total wallet balance = ground truth of actual cash
  double get _walletBalance => _wallets.fold(
        0.0,
        (s, w) => s + (double.tryParse(w['balance'].toString()) ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canViewReports = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.viewReports);

    if (!canViewReports) {
      return Scaffold(
        appBar: AppBar(title: const Text('আয় ব্যয় (Ay Bay)')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.lock, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              const Text('Access Denied', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              const Text('You do not have permission to view transactions.', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    // Calculate income (money coming IN): income, received, sale
    final income = _transactions
        .where((t) {
          final type = t['type'] as String?;
          return type == 'income' || type == 'received' || type == 'sale';
        })
        .fold(0.0, (s, t) => s + (double.tryParse(t['amount'].toString()) ?? 0));
    
    // Calculate expense (money going OUT): expense, payment, purchase
    final expense = _transactions
        .where((t) {
          final type = t['type'] as String?;
          return type == 'expense' || type == 'payment' || type == 'purchase';
        })
        .fold(0.0, (s, t) => s + (double.tryParse(t['amount'].toString()) ?? 0));
    
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('আয় ব্যয়', style: TextStyle(fontWeight: FontWeight.bold)),
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
        onRefresh: _fetchData,
        child: Column(
          children: [
            // Stats Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Filter Tabs
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Row(
                          children: ['today', 'monthly', 'total'].map((tab) {
                            final active = _activeTab == tab;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _activeTab = tab);
                                  _fetchData();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: active ? primaryColor : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    tab[0].toUpperCase() + tab.substring(1),
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
                      ),
                      const SizedBox(height: 20),
                      // Income / Expense (period-filtered)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem('Income', income, Colors.teal),
                          Container(width: 1, height: 40, color: Colors.grey.withOpacity(0.2)),
                          _buildStatItem('Expense', expense, Colors.red),
                        ],
                      ),
                      const Divider(height: 24),
                      // Wallet Balance (always total actual balance)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.wallet, size: 14, color: primaryColor),
                          const SizedBox(width: 6),
                          Text(
                            'Wallet Balance',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '৳${_walletBalance.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _walletBalance >= 0 ? primaryColor : Colors.red,
                        ),
                      ),
                      // Individual wallet breakdown
                      if (_wallets.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: _wallets.map((w) {
                            final bal = double.tryParse(w['balance'].toString()) ?? 0;
                            final isNegative = bal < 0;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: isNegative ? Colors.red.withOpacity(0.08) : primaryColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isNegative ? Colors.red.withOpacity(0.2) : primaryColor.withOpacity(0.2)),
                              ),
                              child: Text(
                                '${w['name']}: ৳${bal.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isNegative ? Colors.red : primaryColor,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Search and Action Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) {
                        setState(() => _searchQuery = v);
                        _updateFilteredTransactions();
                      },
                      decoration: InputDecoration(
                        hintText: 'Search transactions...',
                        prefixIcon: const Icon(LucideIcons.search, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(context).dividerColor),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        fillColor: Theme.of(context).colorScheme.surface,
                        filled: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildIconButton(LucideIcons.tag, () => context.push('/categories')),
                  const SizedBox(width: 8),
                  _buildIconButton(LucideIcons.wallet, () async {
                    await context.push('/wallets');
                    _fetchData(); // Refresh after visiting wallets
                  }),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Transaction List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredTransactions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.receipt, size: 64, color: Colors.grey.withOpacity(0.3)),
                              const SizedBox(height: 16),
                              const Text('No transactions', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
                          itemCount: _filteredTransactions.length,
                          itemBuilder: (context, index) {
                            final tx = _filteredTransactions[index];
                            // Debug: log what's being rendered
                            if (index < 3) {
                              debugPrint('AyBay UI rendering item $index: created_at=${tx['created_at']}, type=${tx['type']}, category=${tx['category']}');
                            }
                            
                            // Get transaction display properties using helper method
                            final props = _getTransactionDisplayProperties(tx);
                            final color = props['color'] as Color;
                            final icon = props['icon'] as IconData;
                            final sign = props['sign'] as String;
                            final amount = props['amount'] as double;
                            
                            // Determine if this is an Ay-Bay transaction that should have edit/delete menu
                            final txType = tx['type'] as String?;
                            final refType = tx['reference_type'] as String?;
                            final isAyBayTransaction = (txType == 'income' || txType == 'expense') &&
                                                      (refType == null || refType == 'manual');
                            // Find wallet name for this transaction
                            final walletName = _wallets
                                .where((w) => w['id'] == tx['wallet_id'])
                                .map((w) => w['name'] as String)
                                .firstOrNull;

                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Theme.of(context).dividerColor),
                              ),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    icon,
                                    size: 20,
                                    color: color,
                                  ),
                                ),
                                title: Text(
                                  tx['category'] ?? 'Uncategorized',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Display transaction_date (user-selected) or fall back to created_at
                                    Builder(
                                      builder: (context) {
                                        String dateStr;
                                        try {
                                          final txDate = tx['transaction_date'] != null
                                              ? DateTime.parse(tx['transaction_date'].toString())
                                              : DateTime.parse(tx['created_at'].toString());
                                          dateStr = DateFormat('dd MMM, yyyy').format(txDate);
                                        } catch (e) {
                                          dateStr = 'Unknown date';
                                        }
                                        return Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[500]));
                                      },
                                    ),
                                    if (tx['note'] != null && tx['note'].toString().isNotEmpty)
                                      Text(tx['note'], style: const TextStyle(fontSize: 12)),
                                    if (walletName != null)
                                      Row(
                                        children: [
                                          Icon(LucideIcons.wallet, size: 10, color: Colors.grey[400]),
                                          const SizedBox(width: 4),
                                          Text(walletName, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                                        ],
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${sign}৳${amount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: color,
                                      ),
                                    ),
                                    // Show three-dot menu only for Ay-Bay income/expense transactions
                                    if (isAyBayTransaction) ...[
                                      const SizedBox(width: 16),
                                      PopupMenuButton<String>(
                                        icon: const Icon(LucideIcons.moreVertical, size: 18),
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _editTransaction(tx);
                                          } else if (value == 'delete') {
                                            _deleteTransaction(tx);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(LucideIcons.edit, size: 16),
                                                SizedBox(width: 8),
                                                Text('Edit'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(LucideIcons.trash, size: 16, color: Colors.red),
                                                SizedBox(width: 8),
                                                Text('Delete', style: TextStyle(color: Colors.red)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/new-transaction');
          _fetchData(); // Refresh after adding transaction
        },
        label: const Text('Add'),
        icon: const Icon(LucideIcons.plus),
      ),
    );
  }

  Widget _buildStatItem(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          '৳${value.toStringAsFixed(0)}',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: color),
        ),
      ],
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return Container(
      height: 40,
      width: 40,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onTap,
        color: Colors.grey,
        padding: EdgeInsets.zero,
      ),
    );
  }
}
