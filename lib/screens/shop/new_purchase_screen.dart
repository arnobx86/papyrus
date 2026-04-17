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

class NewPurchaseScreen extends StatefulWidget {
  final Map<String, dynamic>? editPurchase;
  const NewPurchaseScreen({super.key, this.editPurchase});

  @override
  State<NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends State<NewPurchaseScreen> {
  final _invoiceController = TextEditingController(text: 'P-01');
  final _dateController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
  final _notesController = TextEditingController();
  
  // Persistent controllers for global numeric fields
  final _shippingController = TextEditingController(text: '0');
  final _otherCostController = TextEditingController(text: '0');
  final _discountController = TextEditingController(text: '0');
  final _paidAmountController = TextEditingController(text: '0');
  final _vatPercentController = TextEditingController(text: '0');
  
  String? _supplierId;
  String _supplierName = '';
  List<Map<String, dynamic>> _items = [];
  
  double _shippingCost = 0;
  double _otherCost = 0;
  double _discount = 0;
  double _paidAmount = 0;
  double _vatPercent = 0;
  
  bool _isSaving = false;
  List<dynamic> _suppliers = [];
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
      if (widget.editPurchase != null) {
        _populateEditData();
      }
    });
  }
  
  void _populateEditData() {
    final ep = widget.editPurchase!;
    setState(() {
      _invoiceController.text = ep['invoice_number'] ?? '';
      _dateController.text = ep['created_at'] != null 
          ? DateFormat('yyyy-MM-dd').format(DateTime.parse(ep['created_at'])) 
          : DateFormat('yyyy-MM-dd').format(DateTime.now());
      _notesController.text = ep['notes'] ?? '';
      
      _supplierId = ep['supplier_id'];
      _supplierName = ep['supplier_name'] ?? '';
      
      _shippingCost = (ep['shipping_cost'] ?? 0).toDouble();
      _otherCost = (ep['other_cost'] ?? 0).toDouble();
      _discount = (ep['discount'] ?? 0).toDouble();
      _paidAmount = (ep['paid_amount'] ?? 0).toDouble();
      _vatPercent = (ep['vat_percent'] ?? 0).toDouble();
      
      _shippingController.text = _shippingCost.toString();
      _otherCostController.text = _otherCost.toString();
      _discountController.text = _discount.toString();
      _paidAmountController.text = _paidAmount.toString();
      _vatPercentController.text = _vatPercent.toString();
      
      // Items will be fetched separately since they may not be in the initial object
      _fetchPurchaseItems(ep['id']);
    });
  }
  
  Future<void> _fetchPurchaseItems(String purchaseId) async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('purchase_items')
          .select()
          .eq('purchase_id', purchaseId);
      
      setState(() {
        _items = (response as List).map((i) => {
          'productId': i['product_id'],
          'productName': i['product_name'],
          'quantity': i['quantity'],
          'price': (i['price'] ?? 0).toDouble(),
        }).toList();
        
        // Initialize controllers for items
        for (int i = 0; i < _items.length; i++) {
          _getOrCreateController(i, 'quantity', _items[i]['quantity'].toString());
          _getOrCreateController(i, 'price', _items[i]['price'].toString());
        }
      });
    } catch (e) {
      debugPrint('Error fetching purchase items: $e');
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
        supabase.from('parties').select().eq('shop_id', shopId).eq('type', 'supplier'),
        supabase.from('products').select().eq('shop_id', shopId),
        supabase.from('wallets').select().eq('shop_id', shopId),
        // Get the latest purchase invoice number
        supabase.from('purchases')
          .select('invoice_number')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false)
          .limit(1),
      ]);
      
      if (mounted) {
        setState(() {
          _suppliers = results[0] as List;
          _products = results[1] as List;
          _wallets = results[2] as List;
          if (_wallets.isNotEmpty) _selectedWalletId = _wallets[0]['id'];
          
          // Generate next invoice number for purchases using settings if available
          final latestPurchases = results[3] as List;
          final shopProvider = context.read<ShopProvider>();
          final m = shopProvider.currentShop?.metadata;
          final prefix = m?['purchase_prefix'] ?? 'P-';
          int nextNum = m?['purchase_next_no'] ?? 1;

          // If current settings nextNum is already used, increment until a free one is found
          if (latestPurchases.isNotEmpty) {
            final latestInvoice = latestPurchases[0]['invoice_number'] as String?;
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
      // Fallback to default
      if (mounted) {
        setState(() {
          _invoiceController.text = 'P-01';
        });
      }
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
        'price': (double.tryParse((product['purchase_price'] ?? product['cost_price']).toString()) ?? 0).toDouble(),
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

    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    if (_paidAmount > 0 && _selectedWalletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a wallet for the paid amount')));
      return;
    }

    // Validate wallet balance for purchase payment
    if (_paidAmount > 0 && _selectedWalletId != null) {
      Map<String, dynamic>? selectedWallet;
      try {
        selectedWallet = _wallets.firstWhere((w) => w['id'] == _selectedWalletId);
      } catch (e) {
        selectedWallet = null;
      }
      
      if (selectedWallet != null) {
        final walletBalance = double.tryParse(selectedWallet['balance'].toString()) ?? 0.0;
        debugPrint('Wallet balance check - Balance: $walletBalance, Required: $_paidAmount');
        if (walletBalance < _paidAmount) {
          debugPrint('Insufficient balance detected');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Insufficient wallet balance. Available: ৳${walletBalance.toStringAsFixed(2)}, Required: ৳${_paidAmount.toStringAsFixed(2)}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      } else {
        debugPrint('Selected wallet not found in wallets list');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selected wallet not found')));
        }
        return;
      }
    }

    if (_dueAmount > 0 && _supplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a supplier for due purchases')));
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
      if (widget.editPurchase == null || widget.editPurchase!['invoice_number'] != invoiceNumber) {
        final existing = await supabase
          .from('purchases')
          .select('id')
          .eq('shop_id', shopId)
          .eq('invoice_number', invoiceNumber)
          .maybeSingle();
        
        if (existing != null) {
          throw Exception('Invoice number "$invoiceNumber" already exists. Please use a different invoice number.');
        }
      }
      
      dynamic purchase;
      if (widget.editPurchase != null) {
        // 1. Delete old items (triggers will reverse stock)
        await supabase.from('purchase_items').delete().eq('purchase_id', widget.editPurchase!['id']);
        // 2. Delete old ledger entries & transactions
        await supabase.from('ledger_entries').delete().eq('reference_id', widget.editPurchase!['id']).eq('reference_type', 'purchase');
        await supabase.from('transactions').delete().eq('reference_id', widget.editPurchase!['id']).eq('reference_type', 'purchase');
        
        // 3. Update purchase using RPC function to bypass PostgREST schema cache
        final result = await supabase.rpc('update_purchase', params: {
          'p_purchase_id': widget.editPurchase!['id'],
          'p_supplier_id': _supplierId,
          'p_supplier_name': _supplierName.isEmpty ? 'Unknown Supplier' : _supplierName,
          'p_invoice_number': _invoiceController.text,
          'p_total_amount': _grandTotal,
          'p_paid_amount': _paidAmount,
          'p_due_amount': _dueAmount,
          'p_vat_amount': _vatAmount,
          'p_vat_percent': _vatPercent,
          'p_shipping_cost': _shippingCost,
          'p_other_cost': _otherCost,
          'p_discount': _discount,
          'p_notes': _notesController.text,
          'p_created_at': _dateController.text,
        });
        purchase = result;
      } else {
        // Insert new purchase using RPC function to bypass PostgREST schema cache
        final result = await supabase.rpc('insert_purchase', params: {
          'p_shop_id': shopId,
          'p_supplier_id': _supplierId,
          'p_supplier_name': _supplierName.isEmpty ? 'Unknown Supplier' : _supplierName,
          'p_invoice_number': _invoiceController.text,
          'p_total_amount': _grandTotal,
          'p_paid_amount': _paidAmount,
          'p_due_amount': _dueAmount,
          'p_vat_amount': _vatAmount,
          'p_vat_percent': _vatPercent,
          'p_shipping_cost': _shippingCost,
          'p_other_cost': _otherCost,
          'p_discount': _discount,
          'p_notes': _notesController.text,
          'p_created_at': _dateController.text,
        });
        purchase = result;
      }

      final purchaseItems = _items.map((i) => {
        'purchase_id': purchase['id'],
        'product_id': i['productId'],
        'product_name': i['productName'],
        'quantity': i['quantity'],
        'price': i['price'],
      }).toList();

      await supabase.from('purchase_items').insert(purchaseItems);

      // Ledger entry (we owe supplier money = due/payable)
      if (_dueAmount != 0 && _supplierId != null) {
        await supabase.from('ledger_entries').insert({
          'shop_id': shopId,
          'party_id': _supplierId,
          'party_name': _supplierName,
          'type': 'due',
          'amount': _dueAmount,
          'reference_type': 'purchase',
          'reference_id': purchase['id'],
          'created_at': _dateController.text,
        });
      }

      // Wallet & Transaction Update (Handled by Trigger on transactions insert)
      if (_paidAmount > 0 && _selectedWalletId != null) {
        await supabase.from('transactions').insert({
          'shop_id': shopId,
          'wallet_id': _selectedWalletId,
          'type': 'expense',
          'amount': _paidAmount,
          'category': 'Purchase',
          'note': 'Purchase Payment for Invoice ${_invoiceController.text}',
          'reference_id': purchase['id'],
          'reference_type': 'purchase',
          'created_at': _dateController.text,
        });
      }

      // Send notification to owner if purchase was made by non-owner
      if (shop != null && shop.ownerUserId != supabase.auth.currentUser?.id) {
        final notificationService = NotificationService(supabase);
        await notificationService.notifyOwnerOfActivity(
          shopId: shopId,
          actionType: 'purchase',
          entityName: _invoiceController.text,
          amount: _grandTotal,
          performedBy: supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Employee',
          ownerId: shop.ownerUserId,
        );
      }

      await context.read<ShopProvider>().logActivity(
        action: widget.editPurchase != null ? 'Update Purchase' : 'New Purchase',
        entityType: 'purchase',
        entityId: purchase['id'],
        details: {'message': '${widget.editPurchase != null ? 'Updated' : 'Recorded'} purchase of ৳$_grandTotal for ${_invoiceController.text}'},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Purchase saved!'), backgroundColor: Colors.amber));
        context.read<DataRefreshNotifier>().notify([
          DataChannel.purchases, DataChannel.products, DataChannel.transactions,
          DataChannel.wallets, DataChannel.ledger, DataChannel.activity,
        ]);

        // Increment invoice number in settings if it matches the generated one
        final shopProvider = context.read<ShopProvider>();
        final m = shopProvider.currentShop?.metadata;
        final prefix = m?['purchase_prefix'] ?? 'P-';
        final expectedNext = m?['purchase_next_no'] ?? 1;
        if (invoiceNumber == '$prefix${expectedNext.toString().padLeft(2, '0')}') {
          await shopProvider.updateInvoiceNumber('purchase', expectedNext + 1);
        }

        context.pop();
      }
    } catch (e) {
      debugPrint('Error saving purchase: $e');
      if (mounted) {
        String errorMessage = 'Failed to save purchase. Please try again.';
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
    final canCreate = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.createPurchase);
    final canEdit = auth.currentRole == 'Owner' || Permissions.hasPermission(auth.currentPermissions, AppPermission.editPurchase);
    final isEditing = widget.editPurchase != null;
    final hasPermission = isEditing ? canEdit : canCreate;

    if (!hasPermission) {
      return Scaffold(
        appBar: AppBar(title: Text(isEditing ? 'Edit Purchase' : 'New Purchase')),
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
        title: Text(widget.editPurchase != null ? 'Edit Purchase' : 'New Purchase', 
          style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _handleSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[700],
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
            label: _supplierName.isEmpty ? 'Add Supplier' : _supplierName,
            icon: LucideIcons.plus,
            color: Colors.amber.withOpacity(0.1),
            textColor: Colors.amber[800]!,
            onTap: _showSupplierSelection,
          ),
          const SizedBox(height: 16),

          ...List.generate(_items.length, (index) => _buildItemRow(index)),

          _buildSelectionButton(
            label: 'Add Item',
            icon: LucideIcons.plus,
            color: Colors.transparent,
            textColor: Colors.amber[700]!,
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
              decoration: const InputDecoration(labelText: 'Pay From Wallet', border: OutlineInputBorder()),
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
                  decoration: BoxDecoration(color: Colors.amber.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Vat Amount', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      Text('৳${_vatAmount.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber[700])),
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
          border: isDashed ? Border.all(color: textColor.withOpacity(0.5), style: BorderStyle.none) : null,
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
                  child: _buildNumberInput('Price', (v) => _updateItem(index, 'price', v), initialValue: item['price'].toString(), focusNode: priceFocusNode, controller: priceController),
                ),
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

  void _showSupplierSelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _SelectionModal(
          title: 'Select Supplier',
          items: _suppliers,
          onSelect: (s) {
            setState(() {
              _supplierId = s['id'];
              _supplierName = s['name'];
            });
            Navigator.pop(context);
          },
          onAdd: () async {
             Navigator.pop(context);
             final refresh = await context.push<bool>('/add-person', extra: {'type': 'supplier'});
             if (refresh == true) {
               await _fetchMasterData();
               _showSupplierSelection(); // Re-open with new data
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
                  trailing: widget.isProduct ? Text('৳${(item['purchase_price'] ?? item['cost_price']) ?? 0}') : null,
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
