import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';
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
  double _openingBalance = 0;
  double _closingBalance = 0;
  double _totalIncome = 0;
  double _totalExpense = 0;
  List<Map<String, dynamic>> _incomeTransactions = [];
  List<Map<String, dynamic>> _expenseTransactions = [];

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

      // 1. Fetch Transactions for the selected date
      final txResponse = await supabase
          .from('transactions')
          .select()
          .eq('shop_id', shopId)
          .eq('transaction_date', dateStr);

      // 2. Fetch CURRENT Wallets to get ground truth balance
      final walletsResponse = await supabase
          .from('wallets')
          .select('balance')
          .eq('shop_id', shopId);

      // 3. Fetch all transactions AFTER selected date (to rewind to closing balance)
      final futureTxResponse = await supabase
          .from('transactions')
          .select('type, amount')
          .eq('shop_id', shopId)
          .gt('transaction_date', dateStr);

      // 4. Fetch all transactions ON or AFTER selected date (to rewind to opening balance)
      final todayAndFutureTxResponse = await supabase
          .from('transactions')
          .select('type, amount')
          .eq('shop_id', shopId)
          .gte('transaction_date', dateStr);

      final txList = (txResponse as List).cast<Map<String, dynamic>>();
      final wallets = walletsResponse as List;
      final futureTxList = (futureTxResponse as List).cast<Map<String, dynamic>>();
      final todayAndFutureTxList = (todayAndFutureTxResponse as List).cast<Map<String, dynamic>>();

      // Current total balance
      final currentTotalBalance = wallets.fold(0.0, (s, w) => s + (double.tryParse(w['balance'].toString()) ?? 0));

      // Net change after selected date (to find Closing Balance)
      final futureNetChange = futureTxList.fold(0.0, (s, t) {
        final amt = double.tryParse(t['amount'].toString()) ?? 0;
        final type = t['type'] as String;
        final refType = t['reference_type'] as String?;
        final isPositive = ['income', 'received', 'sale'].contains(type) || refType == 'sale';
        return s + (isPositive ? amt : -amt);
      });

      // Net change on or after selected date (to find Opening Balance)
      final todayAndFutureNetChange = todayAndFutureTxList.fold(0.0, (s, t) {
        final amt = double.tryParse(t['amount'].toString()) ?? 0;
        final type = t['type'] as String;
        final refType = t['reference_type'] as String?;
        final isPositive = ['income', 'received', 'sale'].contains(type) || refType == 'sale';
        return s + (isPositive ? amt : -amt);
      });

      setState(() {
        _incomeTransactions = txList.where((t) {
          final type = t['type'] as String;
          final refType = t['reference_type'] as String?;
          return ['income', 'received', 'sale'].contains(type) || refType == 'sale';
        }).toList();
        
        _expenseTransactions = txList.where((t) {
          final type = t['type'] as String;
          final refType = t['reference_type'] as String?;
          return ['expense', 'payment', 'purchase'].contains(type) || refType == 'purchase';
        }).toList();
        
        _totalIncome = _incomeTransactions.fold(0.0, (s, t) => s + (double.tryParse(t['amount'].toString()) ?? 0));
        _totalExpense = _expenseTransactions.fold(0.0, (s, t) => s + (double.tryParse(t['amount'].toString()) ?? 0));
        
        _closingBalance = currentTotalBalance - futureNetChange;
        _openingBalance = currentTotalBalance - todayAndFutureNetChange;
        
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching report data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
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

  String _getTransactionName(Map<String, dynamic> t, {bool simplify = false}) {
    final type = t['type'] as String;
    final refType = t['reference_type'] as String?;
    final partyName = t['party_name'] as String?;
    final category = (t['category'] as String?)?.toLowerCase();
    final note = (t['note'] as String?)?.trim() ?? '';

    if (refType == 'sale' || category == 'sale') {
      if (simplify) return 'Sale';
      final inv = note.split(' ').last;
      return (inv.contains('-') || inv.startsWith('S-')) ? 'Sale $inv' : 'Sale';
    } else if (refType == 'purchase' || category == 'purchase') {
      if (simplify) return 'Purchase';
      final inv = note.split(' ').last;
      return (inv.contains('-') || inv.startsWith('P-')) ? 'Purchase $inv' : 'Purchase';
    } else if (category == 'received' || type == 'received') {
      return simplify ? 'Received' : 'Received from ${partyName ?? 'Customer'}';
    } else if (category == 'payment' || type == 'payment') {
      return simplify ? 'Payment' : 'Paid to ${partyName ?? 'Supplier'}';
    } else if (t['category'] != null) {
      return t['category'];
    }
    return type.toUpperCase();
  }

  Future<Uint8List> _generatePdf() async {
    final shop = context.read<ShopProvider>().currentShop;
    final curr = shop?.metadata?['currency'] ?? '৳';
    final dateStr = DateFormat('dd MMM, yyyy').format(_selectedDate);

    final regularFont = await PdfGoogleFonts.notoSansBengaliRegular();
    final boldFont = await PdfGoogleFonts.notoSansBengaliBold();

    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(shop?.name ?? 'Papyrus', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#154834'))),
                    if (shop?.address != null) pw.Text(shop!.address!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    if (shop?.phone != null) pw.Text('Phone: ${shop!.phone}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('DAILY REPORT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#154834'))),
                    pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 10),

            // Opening Balance
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Opening Balance', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text('$curr ${_formatCurrency(_openingBalance)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                pw.Expanded(child: pw.SizedBox()), // Spacer to match Closing Balance layout
              ],
            ),
            pw.SizedBox(height: 20),

            // Main Columns
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Income Column
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#2e7d32')),
                        child: pw.Text('INCOME', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      ),
                      pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.grey300),
                        children: [
                          ..._incomeTransactions.map((t) {
                            String name = _getTransactionName(t, simplify: true);
                            return pw.TableRow(
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(5),
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text(name, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                                      if (t['note'] != null && t['note'].toString().isNotEmpty)
                                        pw.Text(t['note'].toString(), style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                                    ],
                                  ),
                                ),
                                pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$curr ${_formatCurrency(double.tryParse(t['amount'].toString()) ?? 0)}', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
                              ],
                            );
                          }),
                        ],
                      ),
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(color: PdfColors.grey100),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Total Income:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                            pw.Text('$curr ${_formatCurrency(_totalIncome)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColor.fromHex('#2e7d32'))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 20),
                // Expenditure Column
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#d32f2f')),
                        child: pw.Text('EXPENDITURE', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      ),
                      pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.grey300),
                        children: [
                          ..._expenseTransactions.map((t) {
                            String name = _getTransactionName(t, simplify: true);
                            return pw.TableRow(
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(5),
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text(name, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                                      if (t['note'] != null && t['note'].toString().isNotEmpty)
                                        pw.Text(t['note'].toString(), style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                                    ],
                                  ),
                                ),
                                pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$curr ${_formatCurrency(double.tryParse(t['amount'].toString()) ?? 0)}', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
                              ],
                            );
                          }),
                        ],
                      ),
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(color: PdfColors.grey100),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Total Expense:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                            pw.Text('$curr ${_formatCurrency(_totalExpense)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColor.fromHex('#d32f2f'))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            pw.SizedBox(height: 30),

            // Closing Balance
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#154834'),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Closing Balance', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 14)),
                        pw.Text('$curr ${_formatCurrency(_closingBalance)}', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
                pw.Expanded(child: pw.SizedBox()), // Spacer
              ],
            ),

            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300),
            pw.Center(child: pw.Text('Powered by Papyrus', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500, fontStyle: pw.FontStyle.italic))),
          ],
        );
      },
    ));

    return pdf.save();
  }

  void _printReport() async {
    final pdfData = await _generatePdf();
    await Printing.layoutPdf(onLayout: (_) async => pdfData, name: 'Daily_Report_${DateFormat('yyyyMMdd').format(_selectedDate)}');
  }

  void _saveAsPdf() async {
    final pdfData = await _generatePdf();
    await Printing.sharePdf(bytes: pdfData, filename: 'Daily_Report_${DateFormat('yyyyMMdd').format(_selectedDate)}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF154834);
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: const Text('Daily Cash Flow', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded),
            onPressed: _printReport,
            tooltip: 'Print Report',
          ),
          IconButton(
            icon: const Icon(Icons.save_alt_rounded),
            onPressed: _saveAsPdf,
            tooltip: 'Download PDF',
          ),
          const SizedBox(width: 8),
        ],
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
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildBalanceCard('Opening Balance', _openingBalance, Colors.grey[700]!, LucideIcons.unlock),
                      const SizedBox(height: 20),
                      
                      _buildTransactionSection('Income', _incomeTransactions, Colors.green, LucideIcons.arrowDownLeft, _totalIncome),
                      const SizedBox(height: 20),
                      
                      _buildTransactionSection('Expenditure', _expenseTransactions, Colors.red, LucideIcons.arrowUpRight, _totalExpense),
                      const SizedBox(height: 20),
                      
                      _buildBalanceCard('Closing Balance', _closingBalance, primaryColor, LucideIcons.lock, isClosing: true),
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

  Widget _buildBalanceCard(String title, double amount, Color color, IconData icon, {bool isClosing = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isClosing ? color : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isClosing ? color : color.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(isClosing ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isClosing ? Colors.white : color).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: isClosing ? Colors.white : color, size: 20),
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isClosing ? Colors.white : Colors.grey[800],
                ),
              ),
            ],
          ),
          Text(
            '৳${_formatCurrency(amount)}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isClosing ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionSection(String title, List<Map<String, dynamic>> txs, Color color, IconData icon, double total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Total: ৳${_formatCurrency(total)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
          ),
          child: txs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'No ${title.toLowerCase()} recorded',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: txs.length,
                  separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.withOpacity(0.1)),
                  itemBuilder: (context, index) {
                    final t = txs[index];
                    String source = _getTransactionName(t);

                    return ListTile(
                      dense: true,
                      title: Text(source, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(t['note'] ?? 'No notes', style: const TextStyle(fontSize: 11)),
                      trailing: Text(
                        '৳${_formatCurrency(double.tryParse(t['amount'].toString()) ?? 0)}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
