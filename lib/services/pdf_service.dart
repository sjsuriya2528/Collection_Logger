import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfService {
  static Future<pw.Document> generateEmployeeReport({
    required String employeeName,
    required List<dynamic> collections,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    print('Generating PDF for $employeeName with ${collections.length} records');
    final pdf = pw.Document();
    final df = DateFormat('dd MMM, yyyy');

    // Calculate Stats
    double totalAmount = 0;
    for (var c in collections) {
      totalAmount += double.tryParse(c['amount'].toString()) ?? 0;
    }

    // Days in period (based on filter or data span)
    int daysInPeriod = 1;
    if (startDate != null && endDate != null) {
      daysInPeriod = endDate.difference(startDate).inDays + 1;
    } else if (collections.isNotEmpty) {
      final dates = collections.map((c) => DateTime.parse(c['date'].toString())).toList();
      dates.sort();
      daysInPeriod = dates.last.difference(dates.first).inDays + 1;
    }
    if (daysInPeriod < 1) daysInPeriod = 1;

    final dailyAvg = totalAmount / daysInPeriod;
    final weeklyAvg = dailyAvg * 7;
    final monthlyAvg = dailyAvg * 30;

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
                pw.SizedBox(width: 12),
                _buildStatBox('Daily Average', 'Rs. ${dailyAvg.toStringAsFixed(2)}', PdfColors.blue900),
                pw.SizedBox(width: 12),
                _buildStatBox('Weekly Average', 'Rs. ${weeklyAvg.toStringAsFixed(2)}', PdfColors.orange900),
                pw.SizedBox(width: 12),
                _buildStatBox('Monthly Average', 'Rs. ${monthlyAvg.toStringAsFixed(2)}', PdfColors.purple900),
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
                final dateStr = c['date'].toString();
                final date = DateTime.parse(dateStr.contains('Z') || dateStr.contains('+') ? dateStr : "${dateStr}Z");
                return pw.TableRow(
                  children: [
                    _tableCell(DateFormat('dd-MM-yy').format(date.toLocal())),
                    _tableCell(c['shop_name'].toString()),
                    _tableCell(c['status'].toString().toLowerCase() == 'completed' ? "${c['bill_no']} (Completed)" : c['bill_no'].toString()),
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

  return pdf;
}

  static Future<pw.Document> generateEmployeeWiseReport({
    required List<dynamic> collections,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdf = pw.Document();
    final df = DateFormat('dd MMM, yyyy');

    // Group collections by employee
    final Map<String, List<dynamic>> grouped = {};
    for (var c in collections) {
      final name = c['employee_name'] ?? 'Unknown';
      if (!grouped.containsKey(name)) grouped[name] = [];
      grouped[name]!.add(c);
    }

    // Helper to calculate stats
    Map<String, double> calculateStats(List<dynamic> items) {
      double total = 0;
      for (var i in items) {
        total += double.tryParse(i['amount'].toString()) ?? 0;
      }
      
      int days = 1;
      if (startDate != null && endDate != null) {
        days = endDate.difference(startDate).inDays + 1;
      } else if (items.isNotEmpty) {
        final dates = items.map((i) => DateTime.parse(i['date'].toString())).toList();
        dates.sort();
        days = dates.last.difference(dates.first).inDays + 1;
      }
      if (days < 1) days = 1;

      final daily = total / days;
      return {
        'total': total,
        'daily': daily,
        'weekly': daily * 7,
        'monthly': daily * 30,
      };
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          final List<pw.Widget> widgets = [];

          // Header
          widgets.add(
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('ACM AGENCIES', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text('Employee-Wise Summary Report', style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
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
          );
          widgets.add(pw.Divider(thickness: 2, color: PdfColors.blue900, height: 32));

          for (var entry in grouped.entries) {
            final empName = entry.key;
            final items = entry.value;
            final stats = calculateStats(items);

            // Employee Summary Header
            widgets.add(pw.SizedBox(height: 20));
            widgets.add(
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: const pw.BoxDecoration(color: PdfColors.grey50),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Employee: $empName', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 12),
                    pw.Row(
                      children: [
                        _buildStatBox('Total', 'Rs. ${stats['total']!.toStringAsFixed(2)}', PdfColors.green900),
                        pw.SizedBox(width: 8),
                        _buildStatBox('Daily Avg', 'Rs. ${stats['daily']!.toStringAsFixed(2)}', PdfColors.blue900),
                        pw.SizedBox(width: 8),
                        _buildStatBox('Weekly Avg', 'Rs. ${stats['weekly']!.toStringAsFixed(2)}', PdfColors.orange900),
                        pw.SizedBox(width: 8),
                        _buildStatBox('Monthly Avg', 'Rs. ${stats['monthly']!.toStringAsFixed(2)}', PdfColors.purple900),
                      ],
                    ),
                  ],
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 8));

            // Employee Table
            widgets.add(
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5),
                  1: const pw.FlexColumnWidth(2.5),
                  2: const pw.FlexColumnWidth(2.5),
                  3: const pw.FlexColumnWidth(1.2),
                  4: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      _tableCell('Date', isHeader: true),
                      _tableCell('Shop Name', isHeader: true),
                      _tableCell('Bill No', isHeader: true),
                      _tableCell('Mode', isHeader: true),
                      _tableCell('Amount', isHeader: true),
                    ],
                  ),
                  ...items.map((i) {
                    final dateStr = i['date'].toString();
                    final date = DateTime.parse(dateStr.contains('Z') || dateStr.contains('+') ? dateStr : "${dateStr}Z");
                    final billNo = i['bill_no']?.toString() ?? '-';
                    final statusText = i['status']?.toString().toLowerCase() == 'completed' ? ' (Completed)' : '';
                    
                    return pw.TableRow(
                      children: [
                        _tableCell(DateFormat('dd-MM-yy').format(date.toLocal())),
                        _tableCell(i['shop_name'].toString()),
                        _tableCell('$billNo$statusText'),
                        _tableCell(i['payment_mode'].toString().toUpperCase()),
                        _tableCell('Rs. ${i['amount']}'),
                      ],
                    );
                  }).toList(),
                ],
              ),
            );
          }

          return widgets;
        },
      ),
    );

    return pdf;
  }

  static Future<pw.Document> generateCollectionWiseReport({
    required List<dynamic> collections,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdf = pw.Document();
    final df = DateFormat('dd MMM, yyyy');

    // Calculate Global Stats
    double total = 0;
    for (var i in collections) {
      total += double.tryParse(i['amount'].toString()) ?? 0;
    }
    
    int days = 1;
    if (startDate != null && endDate != null) {
      days = endDate.difference(startDate).inDays + 1;
    } else if (collections.isNotEmpty) {
      final dates = collections.map((i) => DateTime.parse(i['date'].toString())).toList();
      dates.sort();
      days = dates.last.difference(dates.first).inDays + 1;
    }
    if (days < 1) days = 1;

    final daily = total / days;
    final weekly = daily * 7;
    final monthly = daily * 30;

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
                    pw.Text('Complete Collection Log', style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
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

            // Summary Stats Card at top
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('OVERALL SUMMARY', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.SizedBox(height: 12),
                  pw.Row(
                    children: [
                      _buildStatBox('Total Collected', 'Rs. ${total.toStringAsFixed(2)}', PdfColors.green900),
                      pw.SizedBox(width: 12),
                      _buildStatBox('Daily Average', 'Rs. ${daily.toStringAsFixed(2)}', PdfColors.blue900),
                      pw.SizedBox(width: 12),
                      _buildStatBox('Weekly Average', 'Rs. ${weekly.toStringAsFixed(2)}', PdfColors.orange900),
                      pw.SizedBox(width: 12),
                      _buildStatBox('Monthly Average', 'Rs. ${monthly.toStringAsFixed(2)}', PdfColors.purple900),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(1),
                5: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _tableCell('Date', isHeader: true),
                    _tableCell('Employee', isHeader: true),
                    _tableCell('Shop Name', isHeader: true),
                    _tableCell('Bill No', isHeader: true),
                    _tableCell('Mode', isHeader: true),
                    _tableCell('Amount', isHeader: true),
                  ],
                ),
                ...collections.map((c) {
                  final dateStr = c['date'].toString();
                  final date = DateTime.parse(dateStr.contains('Z') || dateStr.contains('+') ? dateStr : "${dateStr}Z");
                  final billNo = c['bill_no']?.toString() ?? '-';
                  final statusText = c['status']?.toString().toLowerCase() == 'completed' ? ' (Completed)' : '';

                  return pw.TableRow(
                    children: [
                      _tableCell(DateFormat('dd-MM-yy').format(date.toLocal())),
                      _tableCell(c['employee_name']?.toString() ?? 'N/A'),
                      _tableCell(c['shop_name'].toString()),
                      _tableCell('$billNo$statusText'),
                      _tableCell(c['payment_mode'].toString().toUpperCase()),
                      _tableCell('Rs. ${c['amount']}'),
                    ],
                  );
                }).toList(),
              ],
            ),
          ];
        },
      ),
    );

    return pdf;
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
