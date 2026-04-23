import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/shop_provider.dart';

class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;

  String _formatCurrency(double amount) {
    if (amount == amount.toInt()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
  }

  // Data
  double _totalSales = 0;
  int _salesCount = 0;
  double _totalPurchases = 0;
  double _totalPayment = 0;
  double _totalReceived = 0;
  double _totalIncome = 0;
  double _totalExpense = 0;
  List<Map<String, dynamic>> _transactions = [];

  // Cumulative Balance (Rewound to end of selected day)
  double _finalWalletBalance = 0;

  @override
  void initState() {
    super.initState();
    _fetchReportData();
  }

  Future<void> _fetchReportData() async {
    final shopId = context.read<ShopProvider>().currentShop?.id;
    if (shopId == null) return;

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // 1. Fetch Sales (for today's summary)
      final salesResponse = await supabase
          .from('sales')
          .select('total_amount')
          .eq('shop_id', shopId)
          .eq('created_at', dateStr);
      
      // 2. Fetch Purchases (for today's summary)
      final purchasesResponse = await supabase
          .from('purchases')
          .select('total_amount')
          .eq('shop_id', shopId)
          .eq('created_at', dateStr);

      // 3. Fetch Transactions for the selected date (for today's breakdown)
      final txResponse = await supabase
          .from('transactions')
          .select()
          .eq('shop_id', shopId)
          .eq('transaction_date', dateStr);

      // 4. Fetch CURRENT Wallets to get ground truth balance
      final walletsResponse = await supabase
          .from('wallets')
          .select('balance')
          .eq('shop_id', shopId);

      // 5. Fetch Sum of Net Transactions AFTER the selected date to "rewind" balance
      // We look for transactions where transaction_date > selectedDate
      final futureTxResponse = await supabase
          .from('transactions')
          .select('type, amount')
          .eq('shop_id', shopId)
          .gt('transaction_date', dateStr);

      final sales = salesResponse as List;
      final purchases = purchasesResponse as List;
      final txList = (txResponse as List).cast<Map<String, dynamic>>();
      final wallets = walletsResponse as List;
      final futureTxList = (futureTxResponse as List).cast<Map<String, dynamic>>();

      // Current total balance
      final currentTotalBalance = wallets.fold(0.0, (s, w) => s + (double.tryParse(w['balance'].toString()) ?? 0));

      // Net change after selected date
      final futureNetChange = futureTxList.fold(0.0, (s, t) {
        final amt = double.tryParse(t['amount'].toString()) ?? 0;
        final type = t['type'] as String;
        final isPositive = ['income', 'received', 'sale'].contains(type);
        return s + (isPositive ? amt : -amt);
      });

      setState(() {
        _totalSales = sales.fold(0.0, (s, i) => s + (double.tryParse(i['total_amount'].toString()) ?? 0));
        _salesCount = sales.length;
        _totalPurchases = purchases.fold(0.0, (s, i) => s + (double.tryParse(i['total_amount'].toString()) ?? 0));
        
        _totalPayment = txList.where((t) => t['type'] == 'payment').fold(0.0, (s, t) => s + (double.tryParse(t['amount'].toString()) ?? 0));
        _totalReceived = txList.where((t) => t['type'] == 'received').fold(0.0, (s, t) => s + (double.tryParse(t['amount'].toString()) ?? 0));
        _totalIncome = txList.where((t) => t['type'] == 'income').fold(0.0, (s, t) => s + (double.tryParse(t['amount'].toString()) ?? 0));
        _totalExpense = txList.where((t) => t['type'] == 'expense').fold(0.0, (s, t) => s + (double.tryParse(t['amount'].toString()) ?? 0));
        
        _transactions = txList;
        _finalWalletBalance = currentTotalBalance - futureNetChange;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching report data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _netToday {
    // Net cash flow of JUST this day
    final moneyIn = _transactions.where((t) => ['income', 'received', 'sale'].contains(t['type'])).fold(0.0, (s, t) => s + (double.tryParse(t['amount'].toString()) ?? 0));
    final moneyOut = _transactions.where((t) => ['expense', 'payment', 'purchase'].contains(t['type'])).fold(0.0, (s, t) => s + (double.tryParse(t['amount'].toString()) ?? 0));
    return moneyIn - moneyOut;
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchReportData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: const Text('Daily Report', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF154834),
      ),
      body: Column(
        children: [
          _buildDateSelector(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _fetchReportData,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildSummarySection(),
                      const SizedBox(height: 24),
                      _buildDetailedBreakdown(),
                      const SizedBox(height: 24),
                      _buildFinalBalanceCard(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Select Date:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
          InkWell(
            onTap: _selectDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF154834).withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF154834).withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.calendar, size: 16, color: const Color(0xFF154834)),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('dd MMM, yyyy').format(_selectedDate),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF154834)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Business Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1B2C24))),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            _buildReportCard('Total Sales', '৳${_formatCurrency(_totalSales)}', Colors.blue, LucideIcons.trendingUp, subtitle: '$_salesCount Sales'),
            _buildReportCard('Total Purchases', '৳${_formatCurrency(_totalPurchases)}', Colors.amber, LucideIcons.shoppingCart),
            _buildReportCard('Income (Ay-Bay)', '৳${_formatCurrency(_totalIncome)}', Colors.teal, LucideIcons.arrowUpRight),
            _buildReportCard('Expense (Ay-Bay)', '৳${_formatCurrency(_totalExpense)}', Colors.red, LucideIcons.arrowDownLeft),
            _buildReportCard('Received (Len-Den)', '৳${_formatCurrency(_totalReceived)}', Colors.green, LucideIcons.plusCircle),
            _buildReportCard('Payment (Len-Den)', '৳${_formatCurrency(_totalPayment)}', Colors.orange, LucideIcons.minusCircle),
          ],
        ),
      ],
    );
  }

  Widget _buildReportCard(String title, String value, Color color, IconData icon, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const Spacer(),
          FittedBox(child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color))),
          if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _buildDetailedBreakdown() {
    if (_transactions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Daily Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B2C24))),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _transactions.length,
            separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.withOpacity(0.1)),
            itemBuilder: (context, index) {
              final t = _transactions[index];
              final type = t['type'] as String;
              final isPositive = ['income', 'received', 'sale'].contains(type);
              
              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isPositive ? Colors.green : Colors.red).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPositive ? LucideIcons.plus : LucideIcons.minus,
                    size: 16,
                    color: isPositive ? Colors.green : Colors.red,
                  ),
                ),
                title: Text(t['category'] ?? t['type'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(t['note'] ?? 'No note', style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(
                  '${isPositive ? '+' : '-'}৳${_formatCurrency((double.tryParse(t['amount'].toString()) ?? 0))}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green : Colors.red,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFinalBalanceCard() {
    final netToday = _netToday;
    final isNetPositive = netToday >= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF154834), Color(0xFF2E6B4F)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF154834).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Final Cash Balance of the Day',
            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            '৳${_formatCurrency(_finalWalletBalance)}',
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isNetPositive ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                  size: 14,
                  color: isNetPositive ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  "Today's Net: ${isNetPositive ? '+' : ''}৳${_formatCurrency(netToday)}",
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
