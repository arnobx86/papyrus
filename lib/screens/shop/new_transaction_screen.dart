import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/shop_provider.dart';
import '../../core/data_refresh_notifier.dart';

class NewTransactionScreen extends StatefulWidget {
  final String? type; // 'income' or 'expense'
  const NewTransactionScreen({super.key, this.type});

  @override
  State<NewTransactionScreen> createState() => _NewTransactionScreenState();
}

class _NewTransactionScreenState extends State<NewTransactionScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _dateController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
  
  late String _selectedType;
  bool _isSaving = false;
  String? _selectedCategory;
  String? _selectedWalletId;
  List<dynamic> _wallets = [];
  List<dynamic> _categories = [];
  RealtimeChannel? _categoriesChannel;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.type ?? 'expense';
    _fetchWallets();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchCategories();
      _setupRealtimeSubscription();
    });
  }

  @override
  void dispose() {
    _categoriesChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchWallets() async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.from('wallets').select().eq('shop_id', shopId);
      setState(() => _wallets = response as List);
      if (_wallets.isNotEmpty) {
        final defaultFound = _wallets.where((w) => w['is_default'] == true || w['is_default'].toString() == 'true');
        final defaultWallet = defaultFound.isNotEmpty ? defaultFound.first : _wallets[0];
        _selectedWalletId = defaultWallet['id'];
      }
    } catch (e) {
      debugPrint('Error fetching wallets: $e');
    }
  }

  Future<void> _fetchCategories() async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('categories')
          .select()
          .eq('shop_id', shopId)
          .order('name');
      
      if (mounted) {
        setState(() {
          _categories = response as List;
        });
        debugPrint('Fetched ${_categories.length} categories from database');
      }
    } catch (e) {
      debugPrint('Error fetching categories: $e');
      // Fallback to hardcoded categories if database table doesn't exist
      if (mounted) {
        setState(() {
          _categories = [
            {'id': '1', 'name': 'Rent', 'type': 'expense'},
            {'id': '2', 'name': 'Salary', 'type': 'income'},
            {'id': '3', 'name': 'Utility', 'type': 'expense'},
            {'id': '4', 'name': 'Food', 'type': 'expense'},
            {'id': '5', 'name': 'Others', 'type': 'expense'},
            {'id': '6', 'name': 'Investment', 'type': 'expense'},
            {'id': '7', 'name': 'Loan', 'type': 'expense'},
          ];
        });
      }
    }
  }

  void _setupRealtimeSubscription() {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    try {
      final supabase = Supabase.instance.client;
      _categoriesChannel?.unsubscribe();
      
      _categoriesChannel = supabase
          .channel('categories')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'categories',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'shop_id',
              value: shopId,
            ),
            callback: (payload) {
              debugPrint('Categories real-time update: ${payload.eventType}');
              _fetchCategories(); // Refresh categories when changes occur
            },
          )
          .subscribe((status, error) {
            debugPrint('Categories subscription status: $status');
            if (error != null) debugPrint('Categories subscription error: $error');
          });
    } catch (e) {
      debugPrint('Error setting up categories real-time subscription: $e');
    }
  }

  Future<void> _handleSave() async {
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount')));
      return;
    }

    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    if (_selectedWalletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a wallet')));
      return;
    }

    Map<String, dynamic>? wallet;
    for (var w in _wallets) {
      if (w['id'] == _selectedWalletId) {
        wallet = w as Map<String, dynamic>;
        break;
      }
    }
    
    if (wallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid wallet selected')));
      return;
    }
    final currentBalance = double.tryParse(wallet['balance'].toString()) ?? 0.0;

    if (_selectedType == 'expense' && amount > currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient wallet balance for this expense')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;
      
      // 1. Insert into transactions table
      // Use actual timestamp for created_at (for proper ordering)
      // Store user-selected date in transaction_date field
      await supabase.from('transactions').insert({
        'shop_id': shopId,
        'wallet_id': _selectedWalletId,
        'type': _selectedType,
        'amount': amount,
        'category': _selectedCategory ?? 'Others',
        'note': _notesController.text,
        'transaction_date': _dateController.text, // User-selected date for display
        'reference_type': 'manual', // Mark as created via Ay-Bay forms
        // created_at will be auto-generated by database as actual creation timestamp
      });

      // 2. Update wallet balance
      final wallet = _wallets.firstWhere((w) => w['id'] == _selectedWalletId);
      final currentBalance = double.parse(wallet['balance'].toString());
      final newBalance = _selectedType == 'income' 
          ? currentBalance + amount 
          : currentBalance - amount;

      await supabase.from('wallets').update({'balance': newBalance}).eq('id', _selectedWalletId!);

      await context.read<ShopProvider>().logActivity(
        action: 'New Transaction',
        details: {'message': 'Added ${_selectedType.toUpperCase()} of ৳$amount for ${_selectedCategory ?? 'Others'}'},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction saved!'), backgroundColor: Colors.green));
        context.read<DataRefreshNotifier>().notify([
          DataChannel.transactions, DataChannel.wallets, DataChannel.activity,
        ]);
        context.pop();
      }
    } catch (e) {
      debugPrint('Error saving transaction: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _selectedType == 'income' ? Colors.teal : Colors.red;

    return Scaffold(
      appBar: AppBar(
        title: Text('New $_selectedType', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Type Toggle
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                _buildTypeTab('expense', Colors.red),
                _buildTypeTab('income', Colors.teal),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: accentColor),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '৳ ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            ),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            value: _selectedCategory,
            items: _getFilteredCategories().map((c) => DropdownMenuItem(
              value: c['name'] as String,
              child: Text(c['name'] as String),
            )).toList(),
            onChanged: (v) => setState(() => _selectedCategory = v),
            decoration: InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(LucideIcons.tag),
            ),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            value: _selectedWalletId,
            items: _wallets.map((w) => DropdownMenuItem(value: w['id'] as String, child: Text(w['name']))).toList(),
            onChanged: (v) => setState(() => _selectedWalletId = v),
            decoration: InputDecoration(
              labelText: 'Select Wallet',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(LucideIcons.wallet),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _dateController,
            readOnly: true,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
              }
            },
            decoration: InputDecoration(
              labelText: 'Date',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(LucideIcons.calendar),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Notes (Optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _handleSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(_isSaving ? 'Saving...' : 'Save ${_selectedType[0].toUpperCase()}${_selectedType.substring(1)}', 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  List<dynamic> _getFilteredCategories() {
    // Show ALL categories in both income and expense pages (as requested by user)
    // No filtering by type
    if (_categories.isEmpty) {
      return [];
    }
    
    // Add "Others" as a default option if not present
    final hasOthers = _categories.any((c) => (c['name'] as String).toLowerCase() == 'others');
    if (!hasOthers) {
      final allCategories = List<dynamic>.from(_categories);
      allCategories.add({'id': 'others', 'name': 'Others', 'type': 'expense'});
      debugPrint('Showing all categories: ${allCategories.length} items (including added "Others")');
      return allCategories;
    }
    
    debugPrint('Showing all categories: ${_categories.length} items');
    return _categories;
  }

  Widget _buildTypeTab(String type, Color color) {
    final active = _selectedType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedType = type;
            _selectedCategory = null; // Reset category when type changes
          });
          // Refresh categories to ensure proper filtering
          _fetchCategories();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            type[0].toUpperCase() + type.substring(1),
            style: TextStyle(
              color: active ? Colors.white : Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
