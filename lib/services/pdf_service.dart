import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfService {
  // ─── Load Tamil-capable font from assets ──────────────────────────────────
  static Future<pw.Font> _loadTamilFont() async {
    final fontData = await rootBundle.load('assets/fonts/Bamini.ttf');
    return pw.Font.ttf(fontData);
  }

  // ─── Employee Report (used from Admin > Employee History) ──────────────────
  static Future<Uint8List> generateEmployeeReport({
    required String employeeName,
    required List<dynamic> collections,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/Bamini.ttf');
    return await Isolate.run(() async {
      final tamilFont = pw.Font.ttf(fontData);
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
          italic: pw.Font.helveticaOblique(),
          boldItalic: pw.Font.helveticaBoldOblique(),
          fontFallback: [tamilFont],
        ),
      );
      final df = DateFormat('dd MMM, yyyy');

    // Calculate Stats
    double totalAmount = 0;
    for (var c in collections) {
      totalAmount += double.tryParse(c['amount'].toString()) ?? 0;
    }

    int daysInPeriod = 1;
    if (startDate != null && endDate != null) {
      daysInPeriod = endDate.difference(startDate).inDays + 1;
    } else if (collections.isNotEmpty) {
      final dates = collections.map((c) {
        final s = c['date'].toString();
        return DateTime.parse(s.contains('Z') || s.contains('+') ? s : '${s}Z');
      }).toList();
      dates.sort();
      daysInPeriod = dates.last.difference(dates.first).inDays + 1;
    }
    if (daysInPeriod < 1) daysInPeriod = 1;

    final dailyAvg = totalAmount / daysInPeriod;
    final weeklyAvg = dailyAvg * 7;
    final monthlyAvg = dailyAvg * 30;

    pdf.addPage(
      pw.MultiPage(
        maxPages: 9999, // Remove the 20-page default limit
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context ctx) => _buildPageHeader(
          'Collection Report',
          df,
          startDate: startDate,
          endDate: endDate,
        ),
        footer: (pw.Context ctx) => _buildPageFooter(ctx),
        build: (pw.Context context) {
          return [
            pw.SizedBox(height: 12),
            pw.Text('Employee: $employeeName',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),

            // Stats Row
            pw.Row(
              children: [
                _buildStatBox('Total Collected', 'Rs. ${totalAmount.toStringAsFixed(2)}', PdfColors.green900),
                pw.SizedBox(width: 8),
                _buildStatBox('Daily Average', 'Rs. ${dailyAvg.toStringAsFixed(2)}', PdfColors.blue900),
                pw.SizedBox(width: 8),
                _buildStatBox('Weekly Average', 'Rs. ${weeklyAvg.toStringAsFixed(2)}', PdfColors.orange900),
                pw.SizedBox(width: 8),
                _buildStatBox('Monthly Average', 'Rs. ${monthlyAvg.toStringAsFixed(2)}', PdfColors.purple900),
              ],
            ),
            pw.SizedBox(height: 20),

            pw.Text('Collection Details',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),

            // Use TableHelper — it's MultiPage-aware and handles unlimited rows
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              headers: ['Date', 'Shop Name', 'Bill No', 'Mode', 'Amount', 'Status'],
              columnWidths: {
                0: const pw.FlexColumnWidth(1.5),
                1: const pw.FlexColumnWidth(2.8),
                2: const pw.FlexColumnWidth(1.8),
                3: const pw.FlexColumnWidth(1.3),
                4: const pw.FlexColumnWidth(1.4),
                5: const pw.FlexColumnWidth(1.5),
              },
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {
                5: pw.Alignment.center,
              },
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
              cellHeight: 24,
              data: collections.map((c) {
                final dateStr = c['date'].toString();
                final date = DateTime.parse(
                    dateStr.contains('Z') || dateStr.contains('+') ? dateStr : '${dateStr}Z');
                final billNo = c['bill_no']?.toString() ?? '-';
                final isCompleted = c['status']?.toString().toLowerCase() == 'completed';
                return [
                  DateFormat('dd-MM-yy').format(date.toLocal()),
                  c['shop_name'].toString(),
                  billNo,
                  c['payment_mode'].toString().toUpperCase(),
                  'Rs. ${c['amount']}',
                  isCompleted ? 'Finished' : '-',
                ];
              }).toList(),
            ),

            pw.SizedBox(height: 40),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Authorized Signature',
                  style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
            ),
          ];
        },
      ),
    );

      return await pdf.save();
    });
  }

  // ─── Employee-Wise Summary Report (Admin > All Collections) ───────────────
  static Future<Uint8List> generateEmployeeWiseReport({
    required List<dynamic> collections,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/Bamini.ttf');
    return await Isolate.run(() async {
      final tamilFont = pw.Font.ttf(fontData);
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
          italic: pw.Font.helveticaOblique(),
          boldItalic: pw.Font.helveticaBoldOblique(),
          fontFallback: [tamilFont],
        ),
      );
      final df = DateFormat('dd MMM, yyyy');

    // Group collections by employee
    final Map<String, List<dynamic>> grouped = {};
    for (var c in collections) {
      final name = c['employee_name']?.toString() ?? 'Unknown';
      grouped.putIfAbsent(name, () => []).add(c);
    }

    Map<String, double> calculateStats(List<dynamic> items) {
      double total = 0;
      for (var i in items) {
        total += double.tryParse(i['amount'].toString()) ?? 0;
      }
      int days = 1;
      if (startDate != null && endDate != null) {
        days = endDate.difference(startDate).inDays + 1;
      } else if (items.isNotEmpty) {
        final dates = items.map((i) {
          final s = i['date'].toString();
          return DateTime.parse(s.contains('Z') || s.contains('+') ? s : '${s}Z');
        }).toList();
        dates.sort();
        days = dates.last.difference(dates.first).inDays + 1;
      }
      if (days < 1) days = 1;
      final daily = total / days;
      return {'total': total, 'daily': daily, 'weekly': daily * 7, 'monthly': daily * 30};
    }

    pdf.addPage(
      pw.MultiPage(
        maxPages: 9999,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context ctx) => _buildPageHeader(
          'Employee-Wise Summary Report',
          df,
          startDate: startDate,
          endDate: endDate,
        ),
        footer: (pw.Context ctx) => _buildPageFooter(ctx),
        build: (pw.Context context) {
          final List<pw.Widget> widgets = [];

          for (var entry in grouped.entries) {
            final empName = entry.key;
            final items = entry.value;
            final stats = calculateStats(items);

            widgets.add(pw.SizedBox(height: 16));
            widgets.add(
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Employee: $empName',
                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      children: [
                        _buildStatBox('Total', 'Rs. ${stats['total']!.toStringAsFixed(2)}', PdfColors.green900),
                        pw.SizedBox(width: 6),
                        _buildStatBox('Daily Avg', 'Rs. ${stats['daily']!.toStringAsFixed(2)}', PdfColors.blue900),
                        pw.SizedBox(width: 6),
                        _buildStatBox('Weekly Avg', 'Rs. ${stats['weekly']!.toStringAsFixed(2)}', PdfColors.orange900),
                        pw.SizedBox(width: 6),
                        _buildStatBox('Monthly Avg', 'Rs. ${stats['monthly']!.toStringAsFixed(2)}', PdfColors.purple900),
                      ],
                    ),
                  ],
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 6));

            // TableHelper handles page breaks cleanly in MultiPage
            widgets.add(
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                headers: ['Date', 'Shop Name', 'Bill No', 'Mode', 'Amount', 'Status'],
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5),
                  1: const pw.FlexColumnWidth(2.3),
                  2: const pw.FlexColumnWidth(1.8),
                  3: const pw.FlexColumnWidth(1.2),
                  4: const pw.FlexColumnWidth(1.4),
                  5: const pw.FlexColumnWidth(1.5),
                },
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignments: {
                  5: pw.Alignment.center,
                },
                oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
                cellHeight: 22,
                data: items.map((i) {
                  final dateStr = i['date'].toString();
                  final date = DateTime.parse(
                      dateStr.contains('Z') || dateStr.contains('+') ? dateStr : '${dateStr}Z');
                  final billNo = i['bill_no']?.toString() ?? '-';
                  final isCompleted = i['status']?.toString().toLowerCase() == 'completed';
                  return [
                    DateFormat('dd-MM-yy').format(date.toLocal()),
                    i['shop_name'].toString(),
                    billNo,
                    i['payment_mode'].toString().toUpperCase(),
                    'Rs. ${i['amount']}',
                    isCompleted ? 'Finished' : '-',
                  ];
                }).toList(),
              ),
            );
          }

          return widgets;
        },
      ),
    );

      return await pdf.save();
    });
  }

  // ─── Collection-Wise (Flat) Report ────────────────────────────────────────
  static Future<Uint8List> generateCollectionWiseReport({
    required List<dynamic> collections,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/Bamini.ttf');
    return await Isolate.run(() async {
      final tamilFont = pw.Font.ttf(fontData);
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
          italic: pw.Font.helveticaOblique(),
          boldItalic: pw.Font.helveticaBoldOblique(),
          fontFallback: [tamilFont],
        ),
      );
      final df = DateFormat('dd MMM, yyyy');

    double total = 0;
    for (var i in collections) {
      total += double.tryParse(i['amount'].toString()) ?? 0;
    }

    int days = 1;
    if (startDate != null && endDate != null) {
      days = endDate.difference(startDate).inDays + 1;
    } else if (collections.isNotEmpty) {
      final dates = collections.map((i) {
        final s = i['date'].toString();
        return DateTime.parse(s.contains('Z') || s.contains('+') ? s : '${s}Z');
      }).toList();
      dates.sort();
      days = dates.last.difference(dates.first).inDays + 1;
    }
    if (days < 1) days = 1;

    final daily = total / days;
    final weekly = daily * 7;
    final monthly = daily * 30;

    pdf.addPage(
      pw.MultiPage(
        maxPages: 9999,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context ctx) => _buildPageHeader(
          'Complete Collection Log',
          df,
          startDate: startDate,
          endDate: endDate,
        ),
        footer: (pw.Context ctx) => _buildPageFooter(ctx),
        build: (pw.Context context) {
          return [
            pw.SizedBox(height: 12),

            // Overall Summary
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('OVERALL SUMMARY',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    children: [
                      _buildStatBox('Total Collected', 'Rs. ${total.toStringAsFixed(2)}', PdfColors.green900),
                      pw.SizedBox(width: 10),
                      _buildStatBox('Daily Average', 'Rs. ${daily.toStringAsFixed(2)}', PdfColors.blue900),
                      pw.SizedBox(width: 10),
                      _buildStatBox('Weekly Average', 'Rs. ${weekly.toStringAsFixed(2)}', PdfColors.orange900),
                      pw.SizedBox(width: 10),
                      _buildStatBox('Monthly Average', 'Rs. ${monthly.toStringAsFixed(2)}', PdfColors.purple900),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Full flat table — TableHelper handles page breaks automatically
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              headers: ['Date', 'Employee', 'Shop Name', 'Bill No', 'Mode', 'Amount', 'Status'],
              columnWidths: {
                0: const pw.FlexColumnWidth(1.3),
                1: const pw.FlexColumnWidth(1.7),
                2: const pw.FlexColumnWidth(2.0),
                3: const pw.FlexColumnWidth(1.6),
                4: const pw.FlexColumnWidth(0.9),
                5: const pw.FlexColumnWidth(1.4),
                6: const pw.FlexColumnWidth(1.4),
              },
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {
                6: pw.Alignment.center,
              },
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
              cellHeight: 22,
              data: collections.map((c) {
                final dateStr = c['date'].toString();
                final date = DateTime.parse(
                    dateStr.contains('Z') || dateStr.contains('+') ? dateStr : '${dateStr}Z');
                final billNo = c['bill_no']?.toString() ?? '-';
                final isCompleted = c['status']?.toString().toLowerCase() == 'completed';
                return [
                  DateFormat('dd-MM-yy').format(date.toLocal()),
                  c['employee_name']?.toString() ?? 'N/A',
                  c['shop_name'].toString(),
                  billNo,
                  c['payment_mode'].toString().toUpperCase(),
                  'Rs. ${c['amount']}',
                  isCompleted ? 'Finished' : '-',
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );

      return await pdf.save();
    });
  }

  // ─── Shared Helpers ────────────────────────────────────────────────────────

  static pw.Widget _buildPageHeader(
    String subtitle,
    DateFormat df, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('ACM AGENCIES',
                    style: pw.TextStyle(
                        fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                pw.Text(subtitle,
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Generated: ${df.format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 9)),
                if (startDate != null && endDate != null)
                  pw.Text('Period: ${df.format(startDate)} – ${df.format(endDate)}',
                      style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
        pw.Divider(thickness: 1.5, color: PdfColors.blue900, height: 20),
      ],
    );
  }

  static pw.Widget _buildPageFooter(pw.Context ctx) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('ACM Agencies — Confidential',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
      ],
    );
  }

  static pw.Widget _buildStatBox(String title, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text(value,
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
