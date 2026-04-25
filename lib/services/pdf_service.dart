import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfService {
  static Future<void> generateEmployeeReport({
    required String employeeName,
    required List<dynamic> collections,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    print('Generating PDF for $employeeName with ${collections.length} records');
    try {
      final pdf = pw.Document();
      final df = DateFormat('dd MMM, yyyy');

      // Calculate Stats
      double totalAmount = 0;
      for (var c in collections) {
        totalAmount += double.tryParse(c['amount'].toString()) ?? 0;
      }
      print('Total Amount calculated: $totalAmount');

      // Days in period (based on filter or data span)
      int daysInPeriod = 1;
      if (startDate != null && endDate != null) {
        daysInPeriod = endDate.difference(startDate).inDays + 1;
      } else if (collections.isNotEmpty) {
        final dates = collections.map((c) => DateTime.parse(c['date'])).toList();
        dates.sort();
        daysInPeriod = dates.last.difference(dates.first).inDays + 1;
      }
      if (daysInPeriod < 1) daysInPeriod = 1;

      final dailyAvg = totalAmount / daysInPeriod;
      final weeklyAvg = dailyAvg * 7;
      final monthlyAvg = dailyAvg * 30;
      final avgPerShop = collections.isNotEmpty ? totalAmount / collections.length : 0;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('ACM AGENCIES', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      pw.Text('Collection Report', style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date Generated: ${df.format(DateTime.now())}'),
                      if (startDate != null && endDate != null)
                        pw.Text('Period: ${df.format(startDate)} - ${df.format(endDate)}', style: pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 2, color: PdfColors.blue900, height: 32),

              // Employee Info
              pw.Text('Employee: $employeeName', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 24),

              // Stats Grid
              pw.Row(
                children: [
                  _buildStatBox('Total Collected', 'Rs. ${totalAmount.toStringAsFixed(2)}', PdfColors.green900),
                  pw.SizedBox(width: 16),
                  _buildStatBox('Weekly Average', 'Rs. ${weeklyAvg.toStringAsFixed(2)}', PdfColors.blue900),
                  pw.SizedBox(width: 16),
                  _buildStatBox('Monthly Average', 'Rs. ${monthlyAvg.toStringAsFixed(2)}', PdfColors.orange900),
                ],
              ),
              pw.SizedBox(height: 32),

            // Table Header
            pw.Text('Collection Details', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),

            // Table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(2),
              },
              children: [
                // Table Row Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _tableCell('Date', isHeader: true),
                    _tableCell('Shop Name', isHeader: true),
                    _tableCell('Bill No', isHeader: true),
                    _tableCell('Mode', isHeader: true),
                    _tableCell('Amount', isHeader: true),
                  ],
                ),
                // Data Rows
                ...collections.map((c) {
                  final date = DateTime.parse(c['date']);
                  return pw.TableRow(
                    children: [
                      _tableCell(DateFormat('dd-MM-yy').format(date)),
                      _tableCell(c['shop_name'].toString()),
                      _tableCell(c['status'] == 'completed' ? "${c['bill_no']} (Completed)" : c['bill_no'].toString()),
                      _tableCell(c['payment_mode'].toString().toUpperCase()),
                      _tableCell('Rs. ${c['amount']}'),
                    ],
                  );
                }).toList(),
              ],
            ),

            // Footer
            pw.SizedBox(height: 40),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Authorized Signature', style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
            ),
          ];
        },
      ),
    );

    // Show Preview/Download
    print('Opening PDF layout...');
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${employeeName}_Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    } catch (e, stack) {
      print('PDF Generation Error: $e');
      print(stack);
      rethrow;
    }
  }

  static pw.Widget _buildStatBox(String title, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 1),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _tableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: isHeader ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }
}
