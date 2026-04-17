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

class NewSaleScreen extends StatefulWidget {
  final Map<String, dynamic>? editSale;
  const NewSaleScreen({super.key, this.editSale});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final _invoiceController = TextEditingController(text: 'S-01');
  final _dateController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
  final _notesController = TextEditingController();
  
  // Persistent controllers for global numeric fields
  final _shippingController = TextEditingController(text: '0');
  final _otherCostController = TextEditingController(text: '0');
  final _discountController = TextEditingController(text: '0');
  final _paidAmountController = TextEditingController(text: '0');
  final _vatPercentController = TextEditingController(text: '0');
  
  String? _customerId;
  String _customerName = '';
  List<Map<String, dynamic>> _items = [];
  
  double _shippingCost = 0;
  double _otherCost = 0;
  double _discount = 0;
  double _paidAmount = 0;
  double _vatPercent = 0;
  
  bool _isSaving = false;
  List<dynamic> _customers = [];
  List<dynamic> _products = [];
  List<dynamic> _wallets = [];
  String? _selectedWalletId;
  
  // Maps to store controllers and focus nodes for item inputs
  final Map<String, TextEditingController> _itemControllers = {};
  final Map<String, FocusNode> _itemFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _fetchMasterData().then((_) {
      if (widget.editSale != null) {
        _populateEditData();
      }
    });
  }
  
  void _populateEditData() {
    final es = widget.editSale!;
    setState(() {
      _invoiceController.text = es['invoice_number'] ?? '';
      _dateController.text = es['created_at'] != null 
          ? DateFormat('yyyy-MM-dd').format(DateTime.parse(es['created_at'])) 
          : DateFormat('yyyy-MM-dd').format(DateTime.now());
      _notesController.text = es['notes'] ?? '';
      
      _customerId = es['customer_id'];
      _customerName = es['customer_name'] ?? '';
      
      _shippingCost = (es['shipping_cost'] ?? 0).toDouble();
      _otherCost = (es['other_cost'] ?? 0).toDouble();
      _discount = (es['discount'] ?? 0).toDouble();
      _paidAmount = (es['paid_amount'] ?? 0).toDouble();
      _vatPercent = (es['vat_percent'] ?? 0).toDouble();
      
      _shippingController.text = _shippingCost.toString();
      _otherCostController.text = _otherCost.toString();
      _discountController.text = _discount.toString();
      _paidAmountController.text = _paidAmount.toString();
      _vatPercentController.text = _vatPercent.toString();
      
      // Items will be fetched separately since they may not be in the initial object
      _fetchSaleItems(es['id']);
    });
  }
  
  Future<void> _fetchSaleItems(String saleId) async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('sale_items')
          .select()
          .eq('sale_id', saleId);
      
      setState(() {
        _items = (response as List).map((i) => {
          'productId': i['product_id'],
          'productName': i['product_name'],
          'quantity': i['quantity'],
          'price': (i['price'] ?? 0).toDouble(),
          'costPrice': (i['cost_price'] ?? 0).toDouble(),
        }).toList();
        
        // Initialize controllers for items
        for (int i = 0; i < _items.length; i++) {
          _getOrCreateController(i, 'quantity', _items[i]['quantity'].toString());
          _getOrCreateController(i, 'price', _items[i]['price'].toString());
        }
      });
    } catch (e) {
      debugPrint('Error fetching sale items: $e');
    }
  }
  
  @override
  void dispose() {
    // Dispose all item controllers and focus nodes
    for (var controller in _itemControllers.values) {
      controller.dispose();
    }
    for (var focusNode in _itemFocusNodes.values) {
      focusNode.dispose();
    }
    _shippingController.dispose();
    _otherCostController.dispose();
    _discountController.dispose();
    _paidAmountController.dispose();
    _vatPercentController.dispose();
    super.dispose();
  }
  
  String _getItemKey(int index, String field) => '${index}_$field';
  
  TextEditingController _getOrCreateController(int index, String field, String initialValue) {
    final key = _getItemKey(index, field);
    if (!_itemControllers.containsKey(key)) {
      _itemControllers[key] = TextEditingController(text: initialValue);
    }
    return _itemControllers[key]!;
  }
  
  FocusNode _getOrCreateFocusNode(int index, String field) {
    final key = _getItemKey(index, field);
    if (!_itemFocusNodes.containsKey(key)) {
      _itemFocusNodes[key] = FocusNode();
    }
    return _itemFocusNodes[key]!;
  }
  
  void _cleanupItemControllers(int index) {
    _itemControllers.remove('${index}_quantity');
    _itemControllers.remove('${index}_price');
    _itemFocusNodes.remove('${index}_quantity');
    _itemFocusNodes.remove('${index}_price');
  }

  Future<void> _fetchMasterData() async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    try {
      final supabase = Supabase.instance.client;
      final results = await Future.wait([
        supabase.from('parties').select().eq('shop_id', shopId).eq('type', 'customer'),
        supabase.from('products').select().eq('shop_id', shopId),
        supabase.from('wallets').select().eq('shop_id', shopId),
        supabase.from('sales').select('invoice_number').eq('shop_id', shopId).order('created_at', ascending: false).limit(1),
      ]);
      if (mounted) {
        setState(() {
          _customers = results[0] as List;
          _products = results[1] as List;
          _wallets = results[2] as List;
          if (_wallets.isNotEmpty) _selectedWalletId = _wallets[0]['id'];
          
          // Generate next invoice number for sales using settings if available
          final latestSales = results[3] as List;
          final shopProvider = context.read<ShopProvider>();
          final m = shopProvider.currentShop?.metadata;
          final prefix = m?['sale_prefix'] ?? 'S-';
          int nextNum = m?['sale_next_no'] ?? 1;

          // If current settings nextNum is already used, increment until a free one is found (basic collision avoidance)
          if (latestSales.isNotEmpty) {
            final latestInvoice = latestSales[0]['invoice_number'] as String?;
            if (latestInvoice != null && latestInvoice.startsWith(prefix)) {
              final suffix = latestInvoice.substring(prefix.length);
              final lastNum = int.tryParse(suffix) ?? 0;
              if (lastNum >= nextNum) {
                nextNum = lastNum + 1;
              }
            }
          }
          
          _invoiceController.text = '$prefix${nextNum.toString().padLeft(2, '0')}';
        });
      }
    } catch (e) {
      debugPrint('Error fetching master data: $e');
    }
  }

  double get _subtotal => _items.fold(0.0, (s, i) => s + (i['quantity'] * i['price']));
  double get _vatAmount => (_subtotal * _vatPercent) / 100;
  double get _grandTotal => _subtotal + _shippingCost + _otherCost + _vatAmount - _discount;
  double get _dueAmount => _grandTotal - _paidAmount;

  void _addItem(dynamic product) {
    setState(() {
      _items.add({
        'productId': product['id'],
        'productName': product['name'],
        'quantity': 1,
        'price': (double.tryParse(product['sale_price'].toString()) ?? 0).toDouble(),
        'costPrice': (double.tryParse((product['purchase_price'] ?? product['cost_price']).toString()) ?? 0).toDouble(),
      });
    });
  }

  void _updateItem(int index, String field, dynamic value) {
    setState(() {
      _items[index][field] = value;
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _cleanupItemControllers(index);
    });
  }

  Future<void> _handleSave() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one item')));
      return;
    }

    final lowStockItems = _items.where((item) {
      final product = _products.firstWhere((p) => p['id'] == item['productId']);
      return (double.tryParse(product['stock'].toString()) ?? 0) < item['quantity'];
    }).toList();

    if (lowStockItems.isNotEmpty) {
      final proceed = await _showStockWarningDialog(lowStockItems);
      if (proceed != true) return;
    }

    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    if (_paidAmount > 0 && _selectedWalletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a wallet for the paid amount')));
      return;
    }

    // No wallet balance validation needed for sales - money is coming IN to the wallet

    if (_dueAmount > 0 && _customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a customer for due sales')));
      return;
    }

    // Check for duplicate invoice number (skip check if editing and invoice hasn't changed)
    final invoiceNumber = _invoiceController.text.trim();
    if (invoiceNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice number cannot be empty')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;
      final shop = context.read<ShopProvider>().currentShop;
      
      // Check if invoice number already exists (only if not editing or invoice changed)
      if (widget.editSale == null || widget.editSale!['invoice_number'] != invoiceNumber) {
        final existing = await supabase
          .from('sales')
          .select('id')
          .eq('shop_id', shopId)
          .eq('invoice_number', invoiceNumber)
          .maybeSingle();
        
        if (existing != null) {
          throw Exception('Invoice number "$invoiceNumber" already exists. Please use a different invoice number.');
        }
      }
      
      final profit = _items.fold(0.0, (s, i) => s + ((i['price'] - i['costPrice']) * i['quantity']));

      dynamic sale;
      if (widget.editSale != null) {
        // 1. Delete old items (triggers will reverse stock)
        await supabase.from('sale_items').delete().eq('sale_id', widget.editSale!['id']);
        // 2. Delete old ledger entries & transactions
        await supabase.from('ledger_entries').delete().eq('reference_id', widget.editSale!['id']).eq('reference_type', 'sale');
        await supabase.from('transactions').delete().eq('reference_id', widget.editSale!['id']).eq('reference_type', 'sale');
        
        // 3. Update sale using RPC function to bypass PostgREST schema cache
        final result = await supabase.rpc('update_sale', params: {
          'p_sale_id': widget.editSale!['id'],
          'p_customer_id': _customerId,
          'p_customer_name': _customerName.isEmpty ? 'Walk-in Customer' : _customerName,
          'p_invoice_number': invoiceNumber,
          'p_total_amount': _grandTotal,
          'p_paid_amount': _paidAmount,
          'p_due_amount': _dueAmount,
          'p_vat_amount': _vatAmount,
          'p_vat_percent': _vatPercent,
          'p_discount': _discount,
          'p_notes': _notesController.text,
          'p_created_at': _dateController.text,
        });
        sale = result;
        // Update profit separately since it's not in the RPC function
        await supabase.from('sales').update({'profit': profit}).eq('id', widget.editSale!['id']);
      } else {
        // Insert new sale using RPC function to bypass PostgREST schema cache
        final result = await supabase.rpc('insert_sale', params: {
          'p_shop_id': shopId,
          'p_customer_id': _customerId,
          'p_customer_name': _customerName.isEmpty ? 'Walk-in Customer' : _customerName,
          'p_invoice_number': invoiceNumber,
          'p_total_amount': _grandTotal,
          'p_paid_amount': _paidAmount,
          'p_due_amount': _dueAmount,
          'p_vat_amount': _vatAmount,
          'p_vat_percent': _vatPercent,
          'p_discount': _discount,
          'p_notes': _notesController.text,
          'p_created_at': _dateController.text,
        });
        sale = result;
        // Update profit separately since it's not in the RPC function
        await supabase.from('sales').update({'profit': profit}).eq('id', sale['id']);
      }

      final saleItems = _items.map((i) => {
        'sale_id': sale['id'],
        'product_id': i['productId'],
        'product_name': i['productName'],
        'quantity': i['quantity'],
        'price': i['price'],
        'cost_price': i['costPrice'],
      }).toList();

      await supabase.from('sale_items').insert(saleItems);

      // Ledger entry (customer owes us money = loan/receivable)
      if (_dueAmount != 0 && _customerId != null) {
        await supabase.from('ledger_entries').insert({
          'shop_id': shopId,
          'party_id': _customerId,
          'party_name': _customerName,
          'type': 'loan',
          'amount': _dueAmount,
          'reference_type': 'sale',
          'reference_id': sale['id'],
          'created_at': _dateController.text,
        });
      }

      // Wallet & Transaction Update (Handled by Trigger on transactions insert)
      if (_paidAmount > 0 && _selectedWalletId != null) {
        await supabase.from('transactions').insert({
          'shop_id': shopId,
          'wallet_id': _selectedWalletId,
          'type': 'income',
          'amount': _paidAmount,
          'category': 'Sale',
          'note': 'Sale Payment for Invoice ${_invoiceController.text}',
          'reference_id': sale['id'],
          'reference_type': 'sale',
          'created_at': _dateController.text,
        });
      }

      // Send notification to owner if sale was made by non-owner
      if (shop != null && shop.ownerUserId != supabase.auth.currentUser?.id) {
        final notificationService = NotificationService(supabase);
        await notificationService.notifyOwnerOfActivity(
          shopId: shopId,
          actionType: 'sale',
          entityName: _invoiceController.text,
          amount: _grandTotal,
          performedBy: supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Employee',
          ownerId: shop.ownerUserId,
        );
      }

      await context.read<ShopProvider>().logActivity(
        action: widget.editSale != null ? 'Update Sale' : 'New Sale',
        entityType: 'sale',
        entityId: sale['id'],
        details: {'message': '${widget.editSale != null ? 'Updated' : 'Recorded'} sale of ৳$_grandTotal for ${_invoiceController.text}'},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sale saved!'), backgroundColor: Colors.green));
        context.read<DataRefreshNotifier>().notify([
          DataChannel.sales, DataChannel.products, DataChannel.transactions,
          DataChannel.wallets, DataChannel.ledger, DataChannel.activity,
        ]);

        // Increment invoice number in settings if it matches the generated one
        final shopProvider = context.read<ShopProvider>();
        final m = shopProvider.currentShop?.metadata;
        final prefix = m?['sale_prefix'] ?? 'S-';
        final expectedNext = m?['sale_next_no'] ?? 1;
        if (invoiceNumber == '$prefix${expectedNext.toString().padLeft(2, '0')}') {
          await shopProvider.updateInvoiceNumber('sale', expectedNext + 1);
        }

        context.pop();
      }
    } catch (e) {
      debugPrint('Error saving sale: $e');
      if (mounted) {
        String errorMessage = 'Failed to save sale. Please try again.';
        if (e.toString().contains('duplicate key value')) {
          errorMessage = 'Invoice number already exists. Please use a different invoice number.';
        } else if (e.toString().contains('network') || e.toString().contains('connection')) {
          errorMessage = 'Network error. Please check your internet connection and try again.';
        } else if (e.toString().contains('permission') || e.toString().contains('auth')) {
          errorMessage = 'Permission denied. You may not have access to perform this action.';
        } else if (e.toString().contains('Invoice number')) {
          // Use the custom duplicate invoice error message we threw earlier
          errorMessage = e.toString();
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canCreate = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.createSale);
    final canEdit = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.editSale);
    final isEditing = widget.editSale != null;
    final hasPermission = isEditing ? canEdit : canCreate;

    if (!hasPermission) {
      return Scaffold(
        appBar: AppBar(title: Text(isEditing ? 'Edit Sale' : 'New Sale')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.lock, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              const Text('Access Denied', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              const Text('You do not have permission to perform this action.', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editSale != null ? 'Edit Sale' : 'New Sale', 
          style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _handleSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(_isSaving ? 'Saving...' : 'Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _invoiceController,
                  decoration: const InputDecoration(labelText: 'Invoice Number', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _dateController,
                  readOnly: true,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder(), prefixIcon: Icon(LucideIcons.calendar)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildSelectionButton(
            label: _customerName.isEmpty ? 'Add Customer' : _customerName,
            icon: LucideIcons.plus,
            color: Colors.blue.withOpacity(0.1),
            textColor: Colors.blue,
            onTap: _showCustomerSelection,
          ),
          const SizedBox(height: 16),

          ...List.generate(_items.length, (index) => _buildItemRow(index)),

          _buildSelectionButton(
            label: 'Add Item',
            icon: LucideIcons.plus,
            color: Colors.transparent,
            textColor: Theme.of(context).colorScheme.primary,
            isDashed: true,
            onTap: _showProductSelection,
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(child: _buildNumberInput('Shipping Cost', (v) => setState(() => _shippingCost = v), controller: _shippingController)),
              const SizedBox(width: 12),
              Expanded(child: _buildNumberInput('Other Cost', (v) => setState(() => _otherCost = v), controller: _otherCostController)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildNumberInput('Discount', (v) => setState(() => _discount = v), controller: _discountController)),
              const SizedBox(width: 12),
              Expanded(child: _buildNumberInput('Paid Amount', (v) => setState(() => _paidAmount = v), controller: _paidAmountController)),
            ],
          ),
          const SizedBox(height: 12),
          if (_paidAmount > 0) ...[
            DropdownButtonFormField<String>(
              value: _selectedWalletId,
              decoration: const InputDecoration(labelText: 'Store Payment In', border: OutlineInputBorder()),
              items: _wallets.map((w) => DropdownMenuItem(value: w['id'] as String, child: Text(w['name']))).toList(),
              onChanged: (v) => setState(() => _selectedWalletId = v),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(child: _buildNumberInput('Vat %', (v) => setState(() => _vatPercent = v), prefix: '%', controller: _vatPercentController)),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Vat Amount', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      Text('৳${_vatAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Notes (Optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),

          _buildSummaryCard(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSelectionButton({required String label, required IconData icon, required Color color, required Color textColor, required VoidCallback onTap, bool isDashed = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: isDashed ? Border.all(color: textColor.withOpacity(0.5), style: BorderStyle.none) : null, // Simplified
        ),
        child: Row(
          children: [
            Icon(icon, color: textColor),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(int index) {
    final item = _items[index];
    final profit = (item['price'] - item['costPrice']) * item['quantity'];
    
    // Get or create persistent controllers and focus nodes
    final quantityController = _getOrCreateController(index, 'quantity', item['quantity'].toString());
    final priceController = _getOrCreateController(index, 'price', item['price'].toString());
    final quantityFocusNode = _getOrCreateFocusNode(index, 'quantity');
    final priceFocusNode = _getOrCreateFocusNode(index, 'price');
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).dividerColor)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(item['productName'], style: const TextStyle(fontWeight: FontWeight.bold))),
                IconButton(onPressed: () => _removeItem(index), icon: const Icon(LucideIcons.x, size: 16, color: Colors.grey)),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _buildIntegerInput('Quantity', (v) => _updateItem(index, 'quantity', v), initialValue: item['quantity'].toString(), focusNode: quantityFocusNode, controller: quantityController),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNumberInput('Selling Price', (v) => _updateItem(index, 'price', v), initialValue: item['price'].toString(), focusNode: priceFocusNode, controller: priceController),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Cost: ৳${item['costPrice']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text('Profit: ৳${profit.toStringAsFixed(2)}', style: TextStyle(fontSize: 11, color: profit >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberInput(String label, Function(double) onChanged, {String? prefix, String? initialValue, FocusNode? focusNode, TextEditingController? controller}) {
    return TextField(
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      focusNode: focusNode,
      controller: controller,
      onChanged: (v) => onChanged(double.tryParse(v) ?? 0),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
  
  Widget _buildIntegerInput(String label, Function(int) onChanged, {String? prefix, String? initialValue, FocusNode? focusNode, TextEditingController? controller}) {
    return TextField(
      keyboardType: TextInputType.number,
      focusNode: focusNode,
      controller: controller,
      onChanged: (v) {
        // Filter out non-digit characters
        final filtered = v.replaceAll(RegExp(r'[^\d]'), '');
        if (filtered != v) {
          controller?.text = filtered;
          controller?.selection = TextSelection.fromPosition(TextPosition(offset: filtered.length));
        }
        onChanged(int.tryParse(filtered) ?? 0);
      },
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          _buildSummaryRow('Subtotal', _subtotal.toStringAsFixed(2)),
          _buildSummaryRow('Shipping Cost', _shippingCost.toStringAsFixed(2)),
          _buildSummaryRow('Other Cost', _otherCost.toStringAsFixed(2)),
          _buildSummaryRow('VAT (${_vatPercent.toStringAsFixed(1)}%)', _vatAmount.toStringAsFixed(2)),
          _buildSummaryRow('Discount', _discount.toStringAsFixed(2)),
          const Divider(),
          _buildSummaryRow('Grand Total', _grandTotal.toStringAsFixed(2), isBold: true),
          _buildSummaryRow('Due', _dueAmount.toStringAsFixed(2), isBold: true, color: Colors.red),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text('৳$value/-', style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
        ],
      ),
    );
  }

  void _showCustomerSelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _SelectionModal(
          title: 'Select Customer',
          items: _customers,
          onSelect: (c) {
            setState(() {
              _customerId = c['id'];
              _customerName = c['name'];
            });
            Navigator.pop(context);
          },
          onAdd: () async {
             Navigator.pop(context);
             final refresh = await context.push<bool>('/add-person', extra: {'type': 'customer'});
             if (refresh == true) {
               await _fetchMasterData();
               _showCustomerSelection(); // Re-open with new data
             }
          },
        );
      },
    );
  }

  void _showProductSelection() {
     showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _SelectionModal(
          title: 'Select Product',
          items: _products,
          isProduct: true,
          onSelect: (p) {
            _addItem(p);
            Navigator.pop(context);
          },
          onAdd: () async {
             Navigator.pop(context);
             final refresh = await context.push<bool>('/add-product');
             if (refresh == true) {
               await _fetchMasterData();
               _showProductSelection(); // Re-open with new data
             }
          },
        );
      },
    );
  }

  Future<bool?> _showStockWarningDialog(List<Map<String, dynamic>> lowStockItems) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: Colors.red),
            SizedBox(width: 8),
            Text('Insufficient Stock'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The following items have insufficient stock:'),
            const SizedBox(height: 12),
            ...lowStockItems.map((item) {
              final product = _products.firstWhere((p) => p['id'] == item['productId']);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(item['productName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    Text('Stock: ${product['stock']} / Need: ${item['quantity']}', style: const TextStyle(color: Colors.red, fontSize: 10)),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            const Text('Proceeding will result in negative stock.', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sell Anyway', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _SelectionModal extends StatefulWidget {
  final String title;
  final List<dynamic> items;
  final Function(dynamic) onSelect;
  final VoidCallback onAdd;
  final bool isProduct;

  const _SelectionModal({required this.title, required this.items, required this.onSelect, required this.onAdd, this.isProduct = false});

  @override
  State<_SelectionModal> createState() => _SelectionModalState();
}

class _SelectionModalState extends State<_SelectionModal> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((i) {
      final query = _query.toLowerCase();
      final name = i['name'].toString().toLowerCase();
      final sku = (i['sku'] ?? '').toString().toLowerCase();
      return name.contains(query) || sku.contains(query);
    }).toList();
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(hintText: 'Search by Name or SKU...', prefixIcon: Icon(LucideIcons.search)),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.small(onPressed: widget.onAdd, child: const Icon(LucideIcons.plus)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final item = filtered[index];
                final sku = item['sku']?.toString();
                return ListTile(
                  title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: widget.isProduct 
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (sku != null && sku.isNotEmpty)
                            Text('SKU: $sku', style: const TextStyle(fontSize: 11, color: Colors.blue)),
                          Text('Stock: ${item['stock']} ${item['unit']}'),
                        ],
                      )
                    : (item['phone'] != null ? Text(item['phone']) : null),
                  trailing: widget.isProduct ? Text('৳${(item['sale_price'] ?? item['cost_price']) ?? 0}') : null,
                  onTap: () => widget.onSelect(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
