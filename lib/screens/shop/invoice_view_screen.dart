import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';
import '../../core/shop_provider.dart';

class InvoiceViewScreen extends StatefulWidget {
  final String type;
  final String id;

  const InvoiceViewScreen({super.key, required this.type, required this.id});

  @override
  State<InvoiceViewScreen> createState() => _InvoiceViewScreenState();
}

class _InvoiceViewScreenState extends State<InvoiceViewScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _transaction;
  List<dynamic> _items = [];
  String _invoicedByName = '';

  bool get isSale => widget.type == 'sale';

  static const Color _brandColor = Color(0xFF195243);

  @override
  void initState() {
    super.initState();
    _fetchInvoiceData();
  }

  Future<void> _fetchInvoiceData() async {
    try {
      final supabase = Supabase.instance.client;
      final table = isSale ? 'sales' : 'purchases';
      final itemsTable = isSale ? 'sale_items' : 'purchase_items';
      final fk = isSale ? 'sale_id' : 'purchase_id';

      final transaction = await supabase.from(table).select().eq('id', widget.id).single();
      final itemsResponse = await supabase.from(itemsTable).select().eq(fk, widget.id);
      final items = itemsResponse as List;

      String invoicedBy = 'Unknown';

      // 1. Try to deduce the creator from activity_logs
      try {
        final activities = await supabase
            .from('activity_logs')
            .select('user_id')
            .or('entity_id.eq.${widget.id},details->>message.ilike.%${transaction['invoice_number']}%')
            .inFilter('action', ['New Sale', 'New Purchase', 'Update Sale', 'Update Purchase'])
            .order('created_at', ascending: true)
            .limit(1);

        if (activities.isNotEmpty && activities.first['user_id'] != null) {
          final creatorId = activities.first['user_id'];
          final profile = await supabase.from('profiles').select('username, full_name, email').eq('id', creatorId).maybeSingle();
          if (profile != null) {
            invoicedBy = profile['username'] ?? profile['full_name'] ?? profile['email'] ?? 'Unknown';
          }
        }
      } catch (e) {
        debugPrint('Error finding creator from activity logs: $e');
      }

      if (invoicedBy == 'Unknown') {
        final user = supabase.auth.currentUser;
        if (user != null) {
          try {
            final profile = await supabase.from('profiles').select('username, full_name').eq('id', user.id).maybeSingle();
            if (profile != null) {
              invoicedBy = profile['username'] ?? profile['full_name'] ?? user.email ?? 'Unknown';
            } else {
              invoicedBy = user.email ?? 'Unknown';
            }
          } catch (_) {
            invoicedBy = user.email ?? 'Unknown';
          }
        }
      }

      setState(() {
        _transaction = transaction;
        _items = items;
        _invoicedByName = invoicedBy;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => _isLoading = false);
    }
  }

  String _currency() {
    final shop = context.read<ShopProvider>().currentShop;
    return shop?.metadata?['currency'] ?? 'Tk';
  }

  double _calcSubtotal() {
    double subtotal = 0.0;
    for (var item in _items) {
      final quantity = double.tryParse(item['quantity'].toString()) ?? 0;
      final price = double.tryParse(item['price'].toString()) ?? 0;
      subtotal += quantity * price;
    }
    return subtotal;
  }

  Future<Uint8List> _generatePdf() async {
    final shop = context.read<ShopProvider>().currentShop;
    final curr = shop?.metadata?['currency'] ?? 'Tk';
    final partyName = isSale ? _transaction!['customer_name'] ?? 'Walk-in Customer' : _transaction!['supplier_name'] ?? 'Supplier';
    final invoiceNo = _transaction!['invoice_number'] ?? '-';
    final createdAt = DateTime.parse(_transaction!['created_at']);
    final dateStr = DateFormat('dd MMM, yyyy').format(createdAt);
    final subtotal = _calcSubtotal();

    final regularFont = await PdfGoogleFonts.notoSansBengaliRegular();
    final boldFont = await PdfGoogleFonts.notoSansBengaliBold();

    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(56),
      build: (pw.Context ctx) {
        return pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(shop?.name ?? 'Papyrus', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#195243'))),
                  if (shop?.address != null) pw.Text(shop!.address!, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                  if (shop?.phone != null) pw.Text('Phone: ${shop!.phone}', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                ]),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('INVOICE', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#195243'))),
                  pw.Text('No: $invoiceNo', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800)),
                  pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800)),
                ]),
              ]),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 8),
              pw.Row(children: [
                pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('FROM', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey, fontWeight: pw.FontWeight.bold)),
                  pw.Text(shop?.name ?? 'Shop', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ])),
                pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('TO', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey, fontWeight: pw.FontWeight.bold)),
                  pw.Text(partyName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ])),
              ]),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#195243')),
                headers: ['#', 'Item', 'Qty', 'Unit Price', 'Total'],
                data: List.generate(_items.length, (i) {
                  final item = _items[i];
                  final qty = double.tryParse(item['quantity'].toString()) ?? 0;
                  final price = double.tryParse(item['price'].toString()) ?? 0;
                  return [
                    '${i + 1}',
                    item['product_name'] ?? 'Product',
                    '${qty.toStringAsFixed(2)}',
                    '$curr ${price.toStringAsFixed(2)}',
                    '$curr ${(qty * price).toStringAsFixed(2)}',
                  ];
                }),
              ),
              pw.SizedBox(height: 16),
              pw.Row(children: [
                pw.Spacer(flex: 2),
                pw.Expanded(flex: 3, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  _pdfSummaryRow('Grand Total:', '$curr ${_transaction!['total_amount']}', isBold: true, fontSize: 14),
                  _pdfSummaryRow('Paid:', '$curr ${_transaction!['paid_amount']}', isGreen: true),
                  if (double.parse(_transaction!['due_amount']?.toString() ?? '0') > 0)
                    _pdfSummaryRow('Due:', '$curr ${_transaction!['due_amount']}', isRed: true),
                ])),
              ]),
            ]),
            pw.Column(children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Payment Method: ${_transaction!['payment_method'] ?? 'Cash'}', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                  pw.Text('Invoiced by: $_invoicedByName', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ]),
                pw.Container(width: 140, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 1))), padding: const pw.EdgeInsets.only(top: 6), child: pw.Text(shop?.metadata?['authorized_name'] ?? 'Authorized Signatory', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
              ]),
              pw.SizedBox(height: 16),
              pw.Center(child: pw.Text('Powered by Papyrus', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey400, fontStyle: pw.FontStyle.italic))),
            ]),
          ],
        );
      },
    ));
    return pdf.save();
  }

  pw.Widget _pdfSummaryRow(String label, String value, {bool isBold = false, bool isRed = false, bool isGreen = false, double fontSize = 11}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(label, style: pw.TextStyle(fontSize: fontSize)),
        pw.Text(value, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: isRed ? PdfColor.fromHex('#d32f2f') : isGreen ? PdfColor.fromHex('#2e7d32') : PdfColors.black)),
      ]),
    );
  }

  void _printInvoice() async {
    final pdfData = await _generatePdf();
    await Printing.layoutPdf(onLayout: (_) async => pdfData, name: 'Invoice_$_transaction!["invoice_number"]');
  }

  void _saveAsPdf() async {
    final pdfData = await _generatePdf();
    await Printing.sharePdf(bytes: pdfData, filename: 'Invoice_$_transaction!["invoice_number"].pdf');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_transaction == null) return const Scaffold(body: Center(child: Text('Invoice not found')));

    final shop = context.read<ShopProvider>().currentShop;
    final partyName = isSale ? _transaction!['customer_name'] ?? 'Walk-in Customer' : _transaction!['supplier_name'] ?? 'Supplier';
    final invoiceNo = _transaction!['invoice_number'] ?? '-';
    final createdAt = DateTime.parse(_transaction!['created_at']);
    final dateStr = DateFormat('dd MMM, yyyy').format(createdAt);
    final subtotal = _calcSubtotal();
    final curr = _currency();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(title: const Text('Invoice', style: TextStyle(fontWeight: FontWeight.bold)), actions: [
        IconButton(icon: const Icon(Icons.print_rounded), onPressed: _printInvoice),
        IconButton(icon: const Icon(Icons.save_alt_rounded), onPressed: _saveAsPdf),
      ]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: Container(
              width: 794,
              height: 1123,
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))]),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(shop?.name ?? 'Papyrus', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: _brandColor)),
                        if (shop?.address != null) Text(shop!.address!, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        if (shop?.phone != null) Text('Phone: ${shop!.phone}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      ]),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('INVOICE', style: TextStyle(color: _brandColor, fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 2)),
                        Text('No: $invoiceNo', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                        Text('Date: $dateStr', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                      ]),
                    ]),
                    const Divider(height: 32),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('FROM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                        Text(shop?.name ?? 'Shop', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ])),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('TO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                        Text(partyName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ])),
                    ]),
                    const SizedBox(height: 24),
                    Table(
                      columnWidths: const {0: FixedColumnWidth(30), 1: FlexColumnWidth(5), 2: FixedColumnWidth(50), 3: FlexColumnWidth(2), 4: FlexColumnWidth(2)},
                      children: [
                        TableRow(decoration: const BoxDecoration(color: _brandColor), children: [
                          _buildTableCell('#', isHeader: true, align: TextAlign.center),
                          _buildTableCell('Item', isHeader: true),
                          _buildTableCell('Qty', isHeader: true, align: TextAlign.right),
                          _buildTableCell('Price', isHeader: true, align: TextAlign.right),
                          _buildTableCell('Total', isHeader: true, align: TextAlign.right),
                        ]),
                        for (var i = 0; i < _items.length; i++)
                          TableRow(decoration: BoxDecoration(color: i % 2 != 0 ? Colors.grey[50] : Colors.white), children: [
                            _buildTableCell('${i + 1}', align: TextAlign.center),
                            _buildTableCell(_items[i]['product_name'] ?? 'Product'),
                            _buildTableCell('${_items[i]['quantity']}', align: TextAlign.right),
                            _buildTableCell('$curr ${_items[i]['price']}', align: TextAlign.right),
                            _buildTableCell('$curr ${(double.parse(_items[i]['quantity'].toString()) * double.parse(_items[i]['price'].toString())).toStringAsFixed(2)}', isBold: true, align: TextAlign.right),
                          ]),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(children: [
                      const Spacer(flex: 2),
                      Expanded(flex: 3, child: Column(children: [
                        _buildSummaryLine('Subtotal:', '$curr ${subtotal.toStringAsFixed(2)}'),
                        _buildSummaryLine('Grand Total:', '$curr ${_transaction!['total_amount']}', isBold: true, fontSize: 15),
                        _buildSummaryLine('Paid:', '$curr ${_transaction!['paid_amount']}', color: Colors.green[700]),
                        if (double.parse(_transaction!['due_amount']?.toString() ?? '0') > 0)
                          _buildSummaryLine('Due:', '$curr ${_transaction!['due_amount']}', color: Colors.red[700]),
                      ])),
                    ]),
                  ]),
                  Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Payment: ${_transaction!['payment_method'] ?? 'Cash'}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                        Text('Invoiced by: $_invoicedByName', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _brandColor)),
                      ]),
                      Container(width: 140, decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black, width: 1))), padding: const EdgeInsets.only(top: 6), alignment: Alignment.center, child: Text(shop?.metadata?['authorized_name'] ?? 'Authorized Signatory', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                    ]),
                    const SizedBox(height: 24),
                    Center(child: Text('Thank you for your business!', style: TextStyle(color: Colors.grey[500], fontSize: 12))),
                    const SizedBox(height: 4),
                    Center(child: Text('Powered by Papyrus', style: TextStyle(color: Colors.grey[400], fontSize: 9, fontStyle: FontStyle.italic))),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isHeader = false, bool isBold = false, TextAlign align = TextAlign.left}) {
    return Padding(padding: const EdgeInsets.all(8), child: Text(text, textAlign: align, style: TextStyle(color: isHeader ? Colors.white : Colors.black, fontWeight: isHeader || isBold ? FontWeight.bold : FontWeight.normal, fontSize: 12)));
  }

  Widget _buildSummaryLine(String label, String value, {bool isBold = false, Color? color, double fontSize = 12}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(fontSize: fontSize, color: Colors.grey[600])), Text(value, style: TextStyle(fontSize: fontSize, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: color ?? Colors.black87))]));
  }
}
