import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/pdf_service.dart';
import '../common/pdf_preview_screen.dart';
import '../employee/add_collection_screen.dart';
import '../../models/collection.dart';
import '../common/full_screen_image_viewer.dart';

class AllCollectionsHistoryScreen extends StatefulWidget {
  const AllCollectionsHistoryScreen({super.key});

  @override
  State<AllCollectionsHistoryScreen> createState() => _AllCollectionsHistoryScreenState();
}

class _AllCollectionsHistoryScreenState extends State<AllCollectionsHistoryScreen> {
  List<dynamic> _allCollections = [];
  bool _isLoading = true;
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedMode = 'all';
  String _selectedStatusFilter = 'all';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day);
    _fetchData();
  }

  void _applyQuickFilter(String type) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    setState(() {
      if (type == 'Today') {
        _startDate = today;
        _endDate = today;
      } else if (type == 'Yesterday') {
        _startDate = today.subtract(const Duration(days: 1));
        _endDate = today.subtract(const Duration(days: 1));
      } else if (type == 'Last 7 Days') {
        _startDate = today.subtract(const Duration(days: 7));
        _endDate = today;
      }
    });
    _updateFilteredData();
    Navigator.pop(context);
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      final data = await ApiService.getAllCollections(auth.user!.token!);
      _allCollections = data;
      _isLoading = false;
      _updateFilteredData();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  DateTime _parseDate(dynamic date) {
    String dateStr = date.toString();
    if (!dateStr.contains('Z') && !dateStr.contains('+')) {
      dateStr += 'Z';
    }
    return DateTime.parse(dateStr).toLocal();
  }

  List<dynamic> _cachedFilteredCollections = [];
  double _totalAmount = 0;
  double _cashAmount = 0;
  double _upiAmount = 0;
  double _chequeAmount = 0;

  void _updateFilteredData() {
    final filtered = _allCollections.where((c) {
      final date = _parseDate(c['date']);
      final d = DateTime(date.year, date.month, date.day);

      bool matchesDate = true;
      if (_startDate != null && _endDate != null) {
        matchesDate = !d.isBefore(_startDate!) && !d.isAfter(_endDate!);
      }
      
      // Mode Filter
      bool matchesMode = true;
      if (_selectedMode != 'all') {
        final mode = c['payment_mode'].toString().toLowerCase();
        matchesMode = mode == _selectedMode || (_selectedMode == 'upi' && mode == 'both');
      }

      // Status Filter
      bool matchesStatus = true;
      if (_selectedStatusFilter != 'all') {
        matchesStatus = (c['status'] ?? 'partial').toString().toLowerCase() == _selectedStatusFilter;
      }

      final query = _searchController.text.toLowerCase();
      bool matchesSearch = c['shop_name'].toString().toLowerCase().contains(query) ||
                          c['bill_no'].toString().toLowerCase().contains(query) ||
                          (c['employee_name'] ?? '').toString().toLowerCase().contains(query);
      
      return matchesDate && matchesSearch && matchesMode && matchesStatus;
    }).toList()..sort((a, b) => b['date'].compareTo(a['date']));

    double total = 0;
    double cash = 0;
    double upi = 0;
    double cheque = 0;

    for (var item in filtered) {
      final amt = double.tryParse(item['amount'].toString()) ?? 0;
      final mode = item['payment_mode'].toString().toLowerCase();
      total += amt;
      if (mode == 'cash') cash += amt;
      else if (mode == 'upi') upi += amt;
      else if (mode == 'cheque') cheque += amt;
      else if (mode == 'both') {
        cash += double.tryParse(item['cash_amount'].toString()) ?? 0;
        upi += double.tryParse(item['upi_amount'].toString()) ?? 0;
      }
    }

    setState(() {
      _cachedFilteredCollections = filtered;
      _totalAmount = total;
      _cashAmount = cash;
      _upiAmount = upi;
      _chequeAmount = cheque;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Collection History', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          _buildReportsButton(),
          IconButton(
            icon: Icon(
              Icons.tune_rounded, 
              color: (_startDate != null || _selectedMode != 'all' || _selectedStatusFilter != 'all') ? Colors.cyanAccent : Colors.white
            ),
            onPressed: _showFilterBottomSheet,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          _buildSummaryCards(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
              : _cachedFilteredCollections.isEmpty 
                ? const Center(child: Text('No records found', style: TextStyle(color: Colors.white38)))
                : Scrollbar(
                    thumbVisibility: Platform.isWindows || Platform.isMacOS || Platform.isLinux,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _cachedFilteredCollections.length,
                      itemBuilder: (context, index) {
                        final coll = _cachedFilteredCollections[index];
                        return _buildCollectionCard(coll);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsButton() {
    return TextButton.icon(
      onPressed: () => _showReportOptions(),
      icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.cyanAccent, size: 20),
      label: const Text('REPORTS', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
    );
  }

  void _showReportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Generate Report', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Choose how you want to organize the data', style: TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 24),
            _buildReportOption(
              'Employee Wise', 
              'Group records by each employee', 
              Icons.people_alt_rounded,
              () => _generatePdf('employee'),
            ),
            const SizedBox(height: 12),
            _buildReportOption(
              'Collection Wise', 
              'Linear list of all collections', 
              Icons.list_alt_rounded,
              () => _generatePdf('collection'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildReportOption(String title, String sub, IconData icon, VoidCallback onTap) {
    return ListTile(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: Colors.cyanAccent),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: Colors.white.withOpacity(0.03),
    );
  }

  Future<void> _generatePdf(String type) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF Report...')));
    try {
      final pdf = type == 'employee' 
        ? await PdfService.generateEmployeeWiseReport(collections: _cachedFilteredCollections, startDate: _startDate, endDate: _endDate)
        : await PdfService.generateCollectionWiseReport(collections: _cachedFilteredCollections, startDate: _startDate, endDate: _endDate);
      
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => PdfPreviewScreen(pdf: pdf, fileName: 'Collection_Report_$type.pdf')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) => _updateFilteredData(),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search shop, bill or employee...',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.cyanAccent, size: 20),
              suffixIcon: _searchController.text.isNotEmpty 
                ? IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white24, size: 20), onPressed: () => setState(() => _searchController.clear()))
                : null,
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.05))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.cyanAccent, width: 1)),
            ),
          ),
          if (_startDate != null || _selectedMode != 'all' || _selectedStatusFilter != 'all') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.filter_list_rounded, color: Colors.cyanAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_selectedMode.toUpperCase()} • ${_startDate == null ? "All Time" : (_startDate == _endDate ? DateFormat('dd MMM').format(_startDate!) : "${DateFormat('dd MMM').format(_startDate!)} - ${DateFormat('dd MMM').format(_endDate!)}")} • ${_selectedStatusFilter.toUpperCase()}',
                    style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                    GestureDetector(
                      onTap: () {
                        _startDate = null; 
                        _endDate = null; 
                        _selectedMode = 'all'; 
                        _selectedStatusFilter = 'all';
                        _updateFilteredData();
                      },
                      child: const Text('Clear', style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 24, left: 24, right: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 24),
                    const Text('Filter Collections', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    const Text('PAYMENT STATUS', style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: ['all', 'partial', 'completed'].map((s) {
                        final isSelected = _selectedStatusFilter == s;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setModalState(() => _selectedStatusFilter = s),
                            child: Container(
                              margin: EdgeInsets.only(right: s == 'completed' ? 0 : 8),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  s.toUpperCase(),
                                  style: TextStyle(color: isSelected ? const Color(0xFF1A1A2E) : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    const Text('PAYMENT MODE', style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['all', 'cash', 'upi', 'cheque'].map((m) {
                          final isSelected = _selectedMode == m;
                          return GestureDetector(
                            onTap: () => setModalState(() => _selectedMode = m),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                m.toUpperCase(),
                                style: TextStyle(color: isSelected ? const Color(0xFF1A1A2E) : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text('DATE RANGE', style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildQuickChip('Today'),
                        const SizedBox(width: 8),
                        _buildQuickChip('Yesterday'),
                        const SizedBox(width: 8),
                        _buildQuickChip('Last 7 Days'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildDateTile('Start Date', _startDate, (d) => setModalState(() => _startDate = d))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildDateTile('End Date', _endDate, (d) => setModalState(() => _endDate = d))),
                      ],
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          _updateFilteredData();
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: const Color(0xFF1A1A2E),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('APPLY FILTER', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickChip(String label) {
    return GestureDetector(
      onTap: () => _applyQuickFilter(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ),
    );
  }

  Widget _buildDateTile(String label, DateTime? date, Function(DateTime) onPicked) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2023),
          lastDate: DateTime.now(),
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Colors.cyanAccent,
                onPrimary: Color(0xFF1A1A2E),
                surface: Color(0xFF16213E),
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Text(
                  date == null ? 'Select Date' : DateFormat('dd MMM, yyyy').format(date),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [

          _buildStatCard('TOTAL', _totalAmount, Colors.cyanAccent),
          _buildStatCard('CASH', _cashAmount, Colors.greenAccent),
          _buildStatCard('UPI', _upiAmount, Colors.orangeAccent),
          _buildStatCard('CHEQUE', _chequeAmount, Colors.purpleAccent),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, double amount, Color color) {
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.1))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          FittedBox(child: Text('₹${amount.toInt()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16))),
        ],
      ),
    );
  }

  Widget _buildCollectionCard(dynamic coll) {
    final date = DateTime.parse(coll['date']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            coll['shop_name'], 
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),

                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time_rounded, size: 11, color: Colors.white30),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('dd MMM, hh:mm a').format(date.toLocal()), 
                              style: const TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_outline, size: 11, color: Colors.cyanAccent),
                            const SizedBox(width: 4),
                            Text(coll['employee_name'] ?? 'Unknown', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.confirmation_number_outlined, size: 11, color: Colors.white30),
                            const SizedBox(width: 4),
                            Text('Bill #${coll['bill_no']}', style: const TextStyle(color: Colors.white30, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((coll['status'] ?? 'partial').toString().toLowerCase().trim() == 'completed') ...[
                        _buildStatusIcon(false),
                        const SizedBox(width: 6),
                      ],
                      Text('₹${(double.tryParse(coll['amount'].toString()) ?? 0).toInt()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(coll['payment_mode'].toString().toUpperCase(), style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          if ((coll['bill_proof'] != null && coll['bill_proof'].toString().trim().isNotEmpty) || coll['payment_proof'] != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (coll['bill_proof'] != null && coll['bill_proof'].toString().trim().isNotEmpty) 
                  _buildProofChip('BILL', coll['bill_proof'].toString().split(',').where((e) => e.trim().isNotEmpty).toList()),
                if (coll['payment_proof'] != null) 
                  _buildProofChip('PAY', [coll['payment_proof'].toString()]),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (context) => AddCollectionScreen(initialItems: [Collection.fromMap(coll)]))
                  ).then((_) => _fetchData());
                },
                icon: const Icon(Icons.edit_rounded, size: 14, color: Colors.white38),
                label: const Text('EDIT', style: TextStyle(color: Colors.white38, fontSize: 10)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
              ),
              const SizedBox(width: 16),
              TextButton.icon(
                onPressed: () => _confirmDelete(coll),
                icon: Icon(Icons.delete_outline_rounded, size: 14, color: Colors.redAccent.withOpacity(0.7)),
                label: Text('DELETE', style: TextStyle(color: Colors.redAccent.withOpacity(0.7), fontSize: 10)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(bool isLarge) {
    return Container(
      padding: EdgeInsets.all(isLarge ? 4 : 2),
      decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), shape: BoxShape.circle, border: Border.all(color: Colors.greenAccent.withOpacity(0.3), width: 1)),
      child: Icon(Icons.check_rounded, color: Colors.greenAccent, size: isLarge ? 14 : 10),
    );
  }

  Widget _buildProofChip(String label, List<String> paths) {
    return GestureDetector(
      onTap: () => _showImageViewer(paths, label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.cyanAccent.withOpacity(0.2))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_search_rounded, size: 12, color: Colors.cyanAccent),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showImageViewer(List<String> paths, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImageViewer(paths: paths, title: title),
      ),
    );
  }

  void _confirmDelete(dynamic coll) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Delete Record', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete the record for ${coll['shop_name']}?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final auth = Provider.of<AuthProvider>(context, listen: false);
              final success = await ApiService.deleteCollection(coll['id'], auth.user!.token!);
              if (success) {
                _fetchData();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted successfully')));
              }
            }, 
            child: const Text('DELETE', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

  }
}
