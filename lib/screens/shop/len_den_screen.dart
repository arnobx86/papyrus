import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../core/shop_provider.dart';
import '../../core/data_refresh_notifier.dart';
import '../../core/connectivity_service.dart';
import '../../core/local_cache_service.dart';

class LenDenScreen extends StatefulWidget {
  const LenDenScreen({super.key});

  @override
  State<LenDenScreen> createState() => _LenDenScreenState();
}

class _LenDenScreenState extends State<LenDenScreen> {
  String _activeTab = 'all';
  String _searchQuery = '';
  bool _isLoading = true;
  List<dynamic> _parties = [];
  List<dynamic> _ledger = [];
  RealtimeChannel? _partiesChannel;
  RealtimeChannel? _ledgerChannel;

  late DataRefreshNotifier _refreshNotifier;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _setupRealtime();
    _refreshNotifier = context.read<DataRefreshNotifier>();
    _refreshNotifier.addListener(_onDataRefresh);
  }

  void _onDataRefresh() {
    if (_refreshNotifier.shouldRefreshAny({DataChannel.ledger, DataChannel.parties, DataChannel.transactions, DataChannel.sales, DataChannel.purchases})) {
      _fetchData();
    }
  }

  @override
  void dispose() {
    _refreshNotifier.removeListener(_onDataRefresh);
    _partiesChannel?.unsubscribe();
    _ledgerChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtime() {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    final supabase = Supabase.instance.client;
    
    // Subscribe to parties changes with stable channel name
    _partiesChannel = supabase
        .channel('len_den_parties')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'parties',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'shop_id',
            value: shopId,
          ),
          callback: (payload) {
            debugPrint('Parties change detected: ${payload.eventType}');
            if (mounted) {
              _fetchData(); // Refresh data when parties change
            }
          },
        )
        .subscribe((status, error) {
          debugPrint('Parties subscription status: $status');
          if (error != null) debugPrint('Parties subscription error: $error');
        });

    // Subscribe to ledger entries changes with stable channel name
    _ledgerChannel = supabase
        .channel('len_den_ledger')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ledger_entries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'shop_id',
            value: shopId,
          ),
          callback: (payload) {
            debugPrint('Ledger change detected: ${payload.eventType}');
            if (mounted) {
              _fetchData(); // Refresh data when ledger entries change
            }
          },
        )
        .subscribe((status, error) {
          debugPrint('Ledger subscription status: $status');
          if (error != null) debugPrint('Ledger subscription error: $error');
        });
  }

  Future<void> _fetchData() async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    final isOnline = context.read<ConnectivityService>().isOnline;

    if (!isOnline) {
      debugPrint('LenDenScreen: Offline, loading from cache');
      final cachedParties = await LocalCacheService.getParties();
      final cachedLedger = await LocalCacheService.getLedger();
      
      if (mounted) {
        setState(() {
          _parties = cachedParties;
          _ledger = cachedLedger;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final results = await Future.wait([
        supabase.from('parties').select().eq('shop_id', shopId).order('created_at', ascending: false),
        supabase.from('ledger_entries').select().eq('shop_id', shopId),
      ]);

      if (mounted) {
        final parties = results[0] as List;
        final ledger = results[1] as List;
        
        await LocalCacheService.saveParties(parties);
        await LocalCacheService.saveLedger(ledger);

        setState(() {
          _parties = parties;
          _ledger = ledger;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching len den data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _processedParties {
    return _parties.map((p) {
      final partyMap = p as Map<String, dynamic>;
      final entries = _ledger.where((l) => l['party_id'] == partyMap['id']).toList();
      
      // Unified Net Balance System:
      // Net Balance = Total Receivable - Total Payable
      // If Net > 0 → Loan (person owes me money / I will receive)
      // If Net < 0 → Due (I owe money / I need to pay)
      // Never both Due and Loan at the same time
      
      // Calculate total payable (due entries - money I owe)
      final payableTotal = entries.where((e) => e['type'] == 'due' && (e['notes'] == null || !(e['notes'] as String).toLowerCase().contains('payment:'))).fold(0.0, (s, e) => s + (double.tryParse(e['amount'].toString()) ?? 0));
      
      // Calculate total receivable (loan entries - money I will receive)
      final receivableTotal = entries.where((e) => e['type'] == 'loan' && (e['notes'] == null || !(e['notes'] as String).toLowerCase().contains('received:'))).fold(0.0, (s, e) => s + (double.tryParse(e['amount'].toString()) ?? 0));
      
      // Calculate total payments made (payment entries)
      final paymentTotal = entries.where((e) => e['type'] == 'due' && e['notes'] != null && (e['notes'] as String).toLowerCase().contains('payment:')).fold(0.0, (s, e) => s + (double.tryParse(e['amount'].toString()) ?? 0));
      
      // Calculate total received (received entries)
      final receivedTotal = entries.where((e) => e['type'] == 'loan' && e['notes'] != null && (e['notes'] as String).toLowerCase().contains('received:')).fold(0.0, (s, e) => s + (double.tryParse(e['amount'].toString()) ?? 0));
      
      // Net Balance = (Payable + Received) - (Receivable + Payment)
      // Positive = Due (I need to pay), Negative = Loan (I will receive)
      final netBalance = (payableTotal + receivedTotal) - (receivableTotal + paymentTotal);
      
      // Unified balance: either Due OR Loan, never both
      final dueAmount = netBalance > 0 ? netBalance : 0.0;
      final loanAmount = netBalance < 0 ? netBalance.abs() : 0.0;
      
      return {
        ...partyMap,
        'dueTotal': dueAmount,
        'loanTotal': loanAmount,
        'netBalance': netBalance,
        'payableTotal': payableTotal,
        'receivableTotal': receivableTotal,
        'paymentTotal': paymentTotal,
        'receivedTotal': receivedTotal,
      };
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredParties {
    var list = _processedParties;
    if (_activeTab == 'due') list = list.where((p) => (p['dueTotal'] as double) > 0).toList();
    if (_activeTab == 'loan') list = list.where((p) => (p['loanTotal'] as double) > 0).toList();
    
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((p) {
        final name = (p['name'] as String).toLowerCase();
        final phone = (p['phone'] as String?)?.toLowerCase() ?? '';
        return name.contains(q) || phone.contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final partiesWithBalance = _processedParties;
    final totalDue = partiesWithBalance.fold(0.0, (s, p) => s + (p['dueTotal'] as double));
    final totalLoan = partiesWithBalance.fold(0.0, (s, p) => s + (p['loanTotal'] as double));

    return Scaffold(
      appBar: AppBar(
        title: const Text('লেন দেন', style: TextStyle(fontWeight: FontWeight.bold)),
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
            // Tabs and Stats Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).dividerColor)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Toggle Tabs
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(25)),
                        child: Row(
                          children: ['all', 'due', 'loan'].map((tab) {
                            final active = _activeTab == tab;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _activeTab = tab),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: active ? Theme.of(context).colorScheme.primary : Colors.transparent,
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
                      // Stats
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem('Due', totalDue.toStringAsFixed(0), Colors.red, LucideIcons.arrowDown),
                          _buildStatItem('Loan', totalLoan.toStringAsFixed(0), Colors.green, LucideIcons.arrowUp),
                          _buildStatItem('People', partiesWithBalance.length.toString(), Colors.blue, LucideIcons.users),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone',
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  fillColor: Theme.of(context).colorScheme.surface,
                  filled: true,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredParties.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.inbox, size: 64, color: Colors.grey.withOpacity(0.3)),
                              const SizedBox(height: 16),
                              const Text('কোন ব্যক্তি নেই', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
                          itemCount: _filteredParties.length,
                          itemBuilder: (context, index) {
                            final person = _filteredParties[index];
                            // Use netBalance: positive = Due (I owe), negative = Loan (they owe me)
                            final netBalance = person['netBalance'] as double;
                            final balance = netBalance > 0 ? netBalance : -netBalance;
                            final isDue = netBalance > 0;
                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).dividerColor)),
                              child: ListTile(
                                onTap: () => context.push('/ledger/${person['id']}/${Uri.encodeComponent(person['name'])}'),
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                  child: const Icon(LucideIcons.user, size: 24, color: Colors.blue),
                                ),
                                title: Text(person['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: person['phone'] != null ? Text(person['phone'], style: const TextStyle(fontSize: 12)) : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      balance.toStringAsFixed(0),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDue ? Colors.red : Colors.green,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    PopupMenuButton<String>(
                                      icon: const Icon(LucideIcons.moreVertical, size: 16, color: Colors.grey),
                                      onSelected: (value) => _handlePersonMenu(value, person),
                                      itemBuilder: (context) {
                                        final isOnline = context.read<ConnectivityService>().isOnline;
                                        return [
                                          PopupMenuItem<String>(
                                            value: 'edit',
                                            enabled: isOnline,
                                            child: Row(
                                              children: [
                                                Icon(LucideIcons.pencil, size: 16, color: isOnline ? null : Colors.grey),
                                                const SizedBox(width: 8),
                                                Text('Edit', style: TextStyle(color: isOnline ? null : Colors.grey)),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'delete',
                                            enabled: isOnline,
                                            child: Row(
                                              children: [
                                                Icon(LucideIcons.trash2, size: 16, color: isOnline ? Colors.red : Colors.grey),
                                                const SizedBox(width: 8),
                                                Text('Delete', style: TextStyle(color: isOnline ? Colors.red : Colors.grey)),
                                              ],
                                            ),
                                          ),
                                          if (!isOnline)
                                            const PopupMenuItem<String>(
                                              enabled: false,
                                              child: Text('Offline mode', style: TextStyle(fontSize: 10, color: Colors.orange)),
                                            ),
                                        ];
                                      },
                                    ),
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
      floatingActionButton: context.watch<ConnectivityService>().isOnline ? FloatingActionButton.extended(
        onPressed: () async {
          final refresh = await context.push<bool>('/add-person');
          if (refresh == true && mounted) {
            _fetchData();
          }
        },
        label: const Text('Add'),
        icon: const Icon(LucideIcons.plus),
      ) : null,
    );
  }

  void _handlePersonMenu(String value, Map<String, dynamic> person) async {
    if (value == 'edit') {
      // Navigate to edit person screen
      context.push('/add-person', extra: {
        'person': person,
      });
    } else if (value == 'delete') {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Person'),
          content: Text('Are you sure you want to delete ${person['name']}? This will also delete all related transactions.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await _deletePerson(person['id']);
      }
    }
  }

  Future<void> _deletePerson(String personId) async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    try {
      final supabase = Supabase.instance.client;
      // First delete ledger entries for this person
      await supabase
          .from('ledger_entries')
          .delete()
          .eq('shop_id', shopId)
          .eq('party_id', personId);
      
      // Then delete the person
      await supabase
          .from('parties')
          .delete()
          .eq('shop_id', shopId)
          .eq('id', personId);

      // Refresh data
      _fetchData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Person deleted successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Error deleting person: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting person: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildStatItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ],
    );
  }
}
