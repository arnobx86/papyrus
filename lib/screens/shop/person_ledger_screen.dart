import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../core/shop_provider.dart';
import '../../core/data_refresh_notifier.dart';

class PersonLedgerScreen extends StatefulWidget {
  final String personId;
  final String personName;

  const PersonLedgerScreen({super.key, required this.personId, required this.personName});

  @override
  State<PersonLedgerScreen> createState() => _PersonLedgerScreenState();
}

class _PersonLedgerScreenState extends State<PersonLedgerScreen> {
  bool _isLoading = true;
  List<dynamic> _entries = [];
  Map<String, dynamic>? _personDetails;
  RealtimeChannel? _ledgerChannel;
  List<dynamic> _wallets = [];

  late DataRefreshNotifier _refreshNotifier;

  @override
  void initState() {
    super.initState();
    _fetchLedger();
    _setupRealtime();
    _refreshNotifier = context.read<DataRefreshNotifier>();
    _refreshNotifier.addListener(_onDataRefresh);
  }

  void _onDataRefresh() {
    if (_refreshNotifier.shouldRefreshAny({DataChannel.ledger, DataChannel.transactions, DataChannel.wallets})) {
      _fetchLedger();
    }
  }

  @override
  void dispose() {
    _refreshNotifier.removeListener(_onDataRefresh);
    _ledgerChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtime() {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    final supabase = Supabase.instance.client;
    
    _ledgerChannel = supabase
        .channel('person_ledger_${widget.personId}')
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
            final record = payload.newRecord ?? payload.oldRecord;
            if (record != null && record['party_id'] == widget.personId) {
              if (mounted) {
                _fetchLedger();
              }
            }
          },
        )
        .subscribe();
  }

  Future<void> _fetchLedger() async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      
      final personResponse = await supabase
          .from('parties')
          .select()
          .eq('shop_id', shopId)
          .eq('id', widget.personId)
          .single();
      
      final ledgerResponse = await supabase
          .from('ledger_entries')
          .select()
          .eq('shop_id', shopId)
          .eq('party_id', widget.personId)
          .order('created_at', ascending: false);
      
      final walletResponse = await supabase
          .from('wallets')
          .select()
          .eq('shop_id', shopId)
          .order('name');
      
      if (mounted) {
        final entriesList = ledgerResponse as List;
        entriesList.sort((a, b) {
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
          _personDetails = personResponse as Map<String, dynamic>;
          _entries = entriesList;
          _wallets = walletResponse as List;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  (double netBalance, double dueAmount, double loanAmount, double payableTotal, double receivableTotal, double paymentTotal, double receivedTotal) _calculateUnifiedBalances() {
    final payableTotal = _entries
        .where((e) => e['type'] == 'due' && (e['notes'] == null || !(e['notes'] as String).toLowerCase().contains('payment:')))
        .fold(0.0, (s, e) => s + (double.tryParse(e['amount'].toString()) ?? 0));
    
    final receivableTotal = _entries
        .where((e) => e['type'] == 'loan' && (e['notes'] == null || !(e['notes'] as String).toLowerCase().contains('received:')))
        .fold(0.0, (s, e) => s + (double.tryParse(e['amount'].toString()) ?? 0));
    
    final paymentTotal = _entries
        .where((e) => e['type'] == 'due' && e['notes'] != null && (e['notes'] as String).toLowerCase().contains('payment:'))
        .fold(0.0, (s, e) => s + (double.tryParse(e['amount'].toString()) ?? 0));
    
    final receivedTotal = _entries
        .where((e) => e['type'] == 'loan' && e['notes'] != null && (e['notes'] as String).toLowerCase().contains('received:'))
        .fold(0.0, (s, e) => s + (double.tryParse(e['amount'].toString()) ?? 0));
    
    final netBalance = (payableTotal + receivedTotal) - (receivableTotal + paymentTotal);
    final dueAmount = netBalance > 0 ? netBalance : 0.0;
    final loanAmount = netBalance < 0 ? netBalance.abs() : 0.0;
    
    return (netBalance, dueAmount, loanAmount, payableTotal, receivableTotal, paymentTotal, receivedTotal);
  }

  @override
  Widget build(BuildContext context) {
    final (netBalance, dueAmount, loanAmount, _, _, _, _) = _calculateUnifiedBalances();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.personName, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.moreVertical),
            onPressed: () => _showPersonMenu(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchLedger,
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_personDetails != null) _buildPersonInfoCard(),
                  _buildSummaryCard(netBalance, dueAmount, loanAmount),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Transaction History', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        Text('${_entries.length} entries', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  _buildTransactionList(),
                ],
              ),
            ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTransactionDialog(),
        label: const Text('Add Transaction'),
        icon: const Icon(LucideIcons.plus),
      ),
    );
  }

  void _showAddTransactionDialog() {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    bool isSaving = false;
    String transactionType = 'payable';
    String? selectedWalletId;
    DateTime selectedDate = DateTime.now();
    
    final (_, dueAmount, _, _, _, _, _) = _calculateUnifiedBalances();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            Map<String, dynamic>? selectedWallet;
            if (selectedWalletId != null) {
              try {
                selectedWallet = _wallets.firstWhere((w) => w['id'] == selectedWalletId);
              } catch (_) {}
            } else if (_wallets.isNotEmpty) {
              selectedWallet = _wallets[0];
              selectedWalletId = selectedWallet!['id'] as String?;
            }
            
            final walletBalance = selectedWallet != null ? (double.tryParse(selectedWallet['balance'].toString()) ?? 0) : 0.0;
            final amount = double.tryParse(amountController.text) ?? 0.0;
            final isWalletInsufficient = transactionType == 'payment' && walletBalance < amount;
            final isPaymentExceedsDue = transactionType == 'payment' && dueAmount > 0 && amount > dueAmount;
            final isPaymentBlocked = transactionType == 'payment' && (isWalletInsufficient || isPaymentExceedsDue);

            return Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add Transaction', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF195243))),
                  const SizedBox(height: 16),
                  _buildFourSegmentedButtons(setDialogState, transactionType, (type) {
                    setDialogState(() {
                      transactionType = type;
                      if (type == 'payment' && dueAmount > 0) amountController.text = dueAmount.toStringAsFixed(2);
                    });
                  }),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, color: Color(0xFF195243)),
                    decoration: const InputDecoration(hintText: '৳ 0.00', border: InputBorder.none),
                  ),
                  if (transactionType == 'payment' || transactionType == 'received') ...[
                    Text(
                      isPaymentBlocked ? 'Limit exceeded or low balance' : 'Wallet: ৳${walletBalance.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 12, color: isPaymentBlocked ? Colors.red : Colors.green),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedWalletId,
                      decoration: const InputDecoration(labelText: 'Select Wallet', border: OutlineInputBorder()),
                      items: _wallets.map((w) => DropdownMenuItem(value: w['id'] as String, child: Text(w['name'] as String))).toList(),
                      onChanged: (val) => setDialogState(() => selectedWalletId = val),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Date'),
                    subtitle: Text(DateFormat('dd MMM, yyyy').format(selectedDate)),
                    trailing: const Icon(LucideIcons.calendar),
                    onTap: () async {
                      final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (picked != null) setDialogState(() => selectedDate = picked);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: 'Note (Optional)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                      Expanded(child: ElevatedButton(
                        onPressed: (isSaving || isPaymentBlocked) ? null : () async {
                          final amount = double.tryParse(amountController.text) ?? 0;
                          if (amount <= 0) return;
                          setDialogState(() => isSaving = true);
                          try {
                            final shopId = context.read<ShopProvider>().currentShop?.id;
                            if (shopId == null) return;
                            final supabase = Supabase.instance.client;
                            String dbType;
                            String prefix = '';
                            switch (transactionType) {
                              case 'payable': dbType = 'due'; break;
                              case 'receivable': dbType = 'loan'; break;
                              case 'payment': dbType = 'due'; prefix = 'Payment: '; break;
                              case 'received': dbType = 'loan'; prefix = 'Received: '; break;
                              default: dbType = 'due';
                            }
                            final notes = '$prefix${noteController.text.trim()}';
                            final now = DateTime.now();
                            final timestamp = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, now.hour, now.minute, now.second, now.millisecond);
                            
                            final res = await supabase.from('ledger_entries').insert({
                              'shop_id': shopId,
                              'party_id': widget.personId,
                              'party_name': widget.personName,
                              'type': dbType,
                              'amount': amount,
                              'notes': notes.isEmpty ? null : notes,
                              'reference_type': 'manual',
                              'created_at': timestamp.toIso8601String(),
                            }).select().single();
                            
                            if ((transactionType == 'payment' || transactionType == 'received') && selectedWalletId != null) {
                              await supabase.from('transactions').insert({
                                'shop_id': shopId,
                                'wallet_id': selectedWalletId,
                                'type': transactionType == 'payment' ? 'expense' : 'income',
                                'amount': amount,
                                'category': transactionType == 'payment' ? 'Payment' : 'Received',
                                'note': '${transactionType == 'payment' ? 'To' : 'From'} ${widget.personName}: $notes',
                                'reference_id': res['id'],
                                'reference_type': 'manual',
                                'transaction_date': timestamp.toIso8601String(),
                                'created_at': timestamp.toIso8601String(),
                              });
                            }
                            if (context.mounted) {
                              context.read<DataRefreshNotifier>().notify([
                                DataChannel.ledger,
                                DataChannel.transactions,
                                DataChannel.wallets,
                              ]);
                              Navigator.pop(context);
                              _fetchLedger();
                            }
                          } catch (_) {} finally {
                            if (mounted) setDialogState(() => isSaving = false);
                          }
                        },
                        child: Text(isSaving ? 'Saving...' : 'Add'),
                      )),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFourSegmentedButtons(StateSetter setDialogState, String transactionType, Function(String) onTypeSelected) {
    final types = [
      {'type': 'payable', 'label': 'Payable', 'color': Colors.red},
      {'type': 'receivable', 'label': 'Receivable', 'color': Colors.green},
      {'type': 'payment', 'label': 'Payment', 'color': Colors.orange},
      {'type': 'received', 'label': 'Received', 'color': Colors.teal},
    ];
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      childAspectRatio: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: types.map((t) {
        final isActive = transactionType == t['type'];
        final color = t['color'] as Color;
        return InkWell(
          onTap: () => onTypeSelected(t['type'] as String),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(color: isActive ? color.withOpacity(0.1) : Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: isActive ? Border.all(color: color) : null),
            child: Text(t['label'] as String, style: TextStyle(color: isActive ? color : Colors.grey, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPersonInfoCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Person Details', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildInfoRow(LucideIcons.mapPin, 'Address', _personDetails!['address'] ?? 'No address'),
            _buildInfoRow(LucideIcons.phone, 'Phone', _personDetails!['phone'] ?? 'No phone', isPhone: true),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {bool isPhone = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(value, style: TextStyle(fontSize: 13, color: isPhone ? Colors.blue : Colors.black)),
          ]),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(double netBalance, double dueAmount, double loanAmount) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _buildSummaryItem('Due', '৳${dueAmount.toStringAsFixed(0)}', Colors.red),
          _buildSummaryItem('Loan', '৳${loanAmount.toStringAsFixed(0)}', Colors.green),
        ]),
        const Divider(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Net Balance', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('৳${netBalance.abs().toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, color: netBalance >= 0 ? Colors.red : Colors.green, fontSize: 18)),
        ]),
      ]),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
    ]);
  }

  Widget _buildTransactionList() {
    if (_entries.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No transactions')));
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final e = _entries[index];
        final type = e['type'] as String;
        final notes = e['notes'] as String? ?? '';
        final isPayment = type == 'due' && notes.toLowerCase().contains('payment:');
        final isReceived = type == 'loan' && notes.toLowerCase().contains('received:');
        final isDue = type == 'due' && !isPayment;
        final color = (isDue || isPayment) ? Colors.red : Colors.green;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(isPayment ? 'Payment' : isReceived ? 'Received' : isDue ? 'Due' : 'Loan', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            subtitle: Text(DateFormat('dd MMM, hh:mm a').format(DateTime.parse(e['created_at']))),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('৳${e['amount']}', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                if (e['reference_type'] == null || e['reference_type'] == 'manual')
                  PopupMenuButton<String>(
                    onSelected: (val) => _handleTransactionMenu(val, e),
                    itemBuilder: (context) => [const PopupMenuItem(value: 'edit', child: Text('Edit')), const PopupMenuItem(value: 'delete', child: Text('Delete'))],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPersonMenu(BuildContext context) {
    showModalBottomSheet(context: context, builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(LucideIcons.trash, color: Colors.red), title: const Text('Delete Person'), onTap: () => _deletePerson()),
    ]));
  }

  void _deletePerson() {
    // Implementation placeholder
  }

  void _handleTransactionMenu(String value, Map<String, dynamic> transaction) {
    if (transaction['reference_type'] != null && transaction['reference_type'] != 'manual') {
      final refType = transaction['reference_type'] == 'purchase' ? 'Purchase' : 'Sale';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot edit/delete $refType transactions here. Please edit the $refType directly.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    if (value == 'edit') {
      _editTransaction(transaction);
    } else if (value == 'delete') {
      _deleteTransaction(transaction);
    }
  }

  void _editTransaction(Map<String, dynamic> transaction) {
    final amountController = TextEditingController(text: transaction['amount'].toString());
    
    String initialNote = transaction['notes']?.toString() ?? '';
    if (initialNote.toLowerCase().startsWith('payment:')) initialNote = initialNote.substring(8).trim();
    else if (initialNote.toLowerCase().startsWith('received:')) initialNote = initialNote.substring(9).trim();
    
    final noteController = TextEditingController(text: initialNote);
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Transaction'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount')),
              TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount <= 0) return;
                
                setDialogState(() => isSaving = true);
                try {
                  final shopId = context.read<ShopProvider>().currentShop?.id;
                  if (shopId == null) return;
                  final supabase = Supabase.instance.client;
                  
                  await supabase.from('ledger_entries').update({
                    'amount': amount,
                    'notes': noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                  }).eq('id', transaction['id']);
                  
                  final oldTxResponse = await supabase
                      .from('transactions')
                      .select()
                      .eq('shop_id', shopId)
                      .or('reference_id.eq.${transaction['id']},and(note.ilike.%${widget.personName}%,reference_id.is.null)')
                      .order('created_at', ascending: false)
                      .limit(1);
                  
                  if (oldTxResponse.isNotEmpty) {
                    final oldTx = oldTxResponse[0];
                    await supabase.from('transactions').update({
                      'amount': amount,
                      'note': (oldTx['note'] as String).split(':').first + ': ' + noteController.text.trim(),
                    }).eq('id', oldTx['id']);
                  }
                  
                  if (context.mounted) {
                    context.read<DataRefreshNotifier>().notify([
                      DataChannel.ledger,
                      DataChannel.transactions,
                      DataChannel.wallets,
                    ]);
                    Navigator.pop(context);
                    _fetchLedger();
                  }
                } catch (_) {} finally {
                  if (mounted) setDialogState(() => isSaving = false);
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteTransaction(Map<String, dynamic> transaction) {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete Transaction'),
      content: const Text('Are you sure you want to delete this?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () async {
          try {
            final shopId = context.read<ShopProvider>().currentShop?.id;
            if (shopId == null) return;
            final supabase = Supabase.instance.client;
            
            final txResponse = await supabase
                .from('transactions')
                .select()
                .eq('shop_id', shopId)
                .or('reference_id.eq.${transaction['id']},and(note.ilike.%${widget.personName}%,reference_id.is.null)')
                .order('created_at', ascending: false)
                .limit(1);
            
            if (txResponse.isNotEmpty) {
              await supabase.from('transactions').delete().eq('id', txResponse[0]['id']);
            }
            
            await supabase.from('ledger_entries').delete().eq('id', transaction['id']);
            
            if (context.mounted) {
              context.read<DataRefreshNotifier>().notify([
                DataChannel.ledger,
                DataChannel.transactions,
                DataChannel.wallets,
              ]);
              Navigator.pop(context);
              _fetchLedger();
            }
          } catch (_) {}
        }, child: const Text('Delete', style: TextStyle(color: Colors.red))),
      ],
    ));
  }
}
