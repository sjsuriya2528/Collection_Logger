import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import '../../services/pdf_service.dart';

class EmployeeHistoryScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const EmployeeHistoryScreen({super.key, required this.employeeId, required this.employeeName});

  @override
  State<EmployeeHistoryScreen> createState() => _EmployeeHistoryScreenState();
}

class _EmployeeHistoryScreenState extends State<EmployeeHistoryScreen> {
  List<dynamic> _collections = [];
  bool _isLoading = true;
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedMode = 'all';
  String _selectedStatusFilter = 'all';
  final _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      final data = await ApiService.getEmployeeCollections(widget.employeeId, auth.user!.token!);
      setState(() => _collections = data);
    } catch (e) {
      print('History Fetch Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyQuickFilter(String type) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
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
    setState(() {});
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _collections.where((c) {
      // Date Filter
      bool matchesDate = true;
      if (_startDate != null && _endDate != null) {
        final date = DateTime.parse(c['date']);
        final d = DateTime(date.year, date.month, date.day);
        matchesDate = d.isAfter(_startDate!.subtract(const Duration(days: 1))) && 
                      d.isBefore(_endDate!.add(const Duration(days: 1)));
      }

      // Mode Filter
      bool matchesMode = true;
      if (_selectedMode != 'all') {
        matchesMode = c['payment_mode'].toString().toLowerCase() == _selectedMode;
      }

      // Status Filter
      bool matchesStatus = true;
      if (_selectedStatusFilter != 'all') {
        matchesStatus = (c['status'] ?? 'partial').toString().toLowerCase() == _selectedStatusFilter;
      }

      // Search Filter
      bool matchesSearch = true;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        matchesSearch = c['shop_name'].toString().toLowerCase().contains(query) || 
                        c['bill_no'].toString().toLowerCase().contains(query);
      }

      return matchesDate && matchesMode && matchesSearch && matchesStatus;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.cyanAccent),
            onPressed: () async {
              if (filtered.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No records to export')),
                );
                return;
              }
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Generating PDF Report...'), duration: Duration(seconds: 2)),
              );

              try {
                await PdfService.generateEmployeeReport(
                  employeeName: widget.employeeName,
                  collections: filtered,
                  startDate: _startDate,
                  endDate: _endDate,
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error generating PDF: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: Icon(
              Icons.tune_rounded, 
              color: (_startDate != null || _selectedMode != 'all') ? Colors.cyanAccent : Colors.white
            ),
            onPressed: _showFilterBottomSheet,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
        : RefreshIndicator(
            onRefresh: _fetchHistory,
            color: Colors.cyanAccent,
            backgroundColor: const Color(0xFF16213E),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search shop or bill no...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.cyanAccent, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty 
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = "");
                            },
                          )
                        : null,
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.05))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.cyanAccent, width: 1)),
                    ),
                  ),
                ),
                if (_startDate != null || _selectedMode != 'all')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.filter_list_rounded, color: Colors.cyanAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_selectedMode.toUpperCase()} • ${_startDate == null ? "All Time" : (_startDate == _endDate ? DateFormat('dd MMM').format(_startDate!) : "${DateFormat('dd MMM').format(_startDate!)} - ${DateFormat('dd MMM').format(_endDate!)}")}',
                            style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() { _startDate = null; _endDate = null; _selectedMode = 'all'; }),
                          child: const Text('Clear', style: TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: filtered.isEmpty 
                  ? _buildEmptyState()
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) => _buildRecordItem(filtered[index]),
                    ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildEmptyState() {
    return ListView( // Needs to be a listview for RefreshIndicator to work on empty list
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Center(
          child: Column(
            children: [
              Icon(Icons.search_off_rounded, size: 80, color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 16),
              const Text('No records found for these filters', style: TextStyle(color: Colors.white60)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecordItem(dynamic coll) {
    final date = DateTime.parse(coll['date']);
    return GestureDetector(
      onLongPress: () => _showEditBottomSheet(coll),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.receipt_long_rounded, color: Colors.cyanAccent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          coll['shop_name'], 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          softWrap: true,
                        ),
                      ),
                      if (coll['status'] == 'completed') ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 14),
                      ],
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: coll['status'] == 'completed' ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          (coll['status'] ?? 'PARTIAL').toString().toUpperCase(),
                          style: TextStyle(
                            color: coll['status'] == 'completed' ? Colors.greenAccent : Colors.orangeAccent,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Bill: ${coll['bill_no']} • ${DateFormat('dd MMM, hh:mm a').format(date)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  if (coll['bill_proof'] != null || coll['payment_proof'] != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (coll['bill_proof'] != null)
                          _buildProofChip('Bill Proof', coll['bill_proof']),
                        if (coll['payment_proof'] != null)
                          _buildProofChip('Payment Proof', coll['payment_proof']),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '₹${coll['amount']}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                Text(
                  coll['payment_mode'].toString().toUpperCase(),
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                IconButton(
                  onPressed: () => _confirmDelete(coll),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(dynamic coll) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete Record', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete the record for "${coll['shop_name']}"? This cannot be undone.', 
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final auth = Provider.of<AuthProvider>(context, listen: false);
              final success = await ApiService.deleteCollection(coll['id'], auth.user!.token!);
              if (success) {
                _fetchHistory(); // Refresh list
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record deleted successfully')));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete record'), backgroundColor: Colors.redAccent));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('DELETE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildProofChip(String label, String path) {
    return GestureDetector(
      onTap: () => _showImageViewer(path, label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.cyanAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.cyanAccent.withOpacity(0.2)),
        ),
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

  void _showImageViewer(String path, String title) {
    final serverBase = ApiService.baseUrl.replaceAll('/api', '');
    final imageUrl = path.startsWith('http') ? path : '$serverBase$path';
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(title, style: const TextStyle(color: Colors.white)),
              leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                imageUrl,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  padding: const EdgeInsets.all(40),
                  color: Colors.white.withOpacity(0.05),
                  child: const Column(
                    children: [
                      Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
                      SizedBox(height: 8),
                      Text('Failed to load image', style: TextStyle(color: Colors.white60)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
                    const Text('Filter History', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
                          setState(() {});
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
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () => _applyQuickFilter(label),
      backgroundColor: Colors.white.withOpacity(0.05),
      padding: EdgeInsets.zero,
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
                surface: Color(0xFF1A1A2E),
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            const SizedBox(height: 4),
            Text(
              date == null ? 'Select' : DateFormat('dd MMM').format(date),
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditBottomSheet(dynamic coll) {
    final billController = TextEditingController(text: coll['bill_no']);
    final shopController = TextEditingController(text: coll['shop_name']);
    final amountController = TextEditingController(text: coll['amount'].toString());
    String mode = coll['payment_mode'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
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
                const Text('Edit Record', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Update the collection details below', style: TextStyle(color: Colors.white38, fontSize: 14)),
                const SizedBox(height: 32),
                _buildStyledEditField(billController, 'Bill Number', Icons.receipt_long_rounded),
                const SizedBox(height: 16),
                _buildStyledEditField(shopController, 'Shop Name', Icons.storefront_rounded),
                const SizedBox(height: 16),
                _buildStyledEditField(amountController, 'Amount (₹)', Icons.currency_rupee_rounded, isNumber: true),
                const SizedBox(height: 24),
                const Text('PAYMENT MODE', style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: ['cash', 'upi', 'cheque'].map((m) {
                    final isSelected = mode == m;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() => mode = m),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              m.toUpperCase(),
                              style: TextStyle(color: isSelected ? const Color(0xFF1A1A2E) : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      final auth = Provider.of<AuthProvider>(context, listen: false);
                      final success = await ApiService.updateCollection(
                        coll['id'].toString(),
                        {
                          'bill_no': billController.text,
                          'shop_name': shopController.text,
                          'amount': double.parse(amountController.text),
                          'payment_mode': mode,
                        },
                        auth.user!.token!,
                      );
                      if (success && mounted) {
                        Navigator.pop(context);
                        _fetchHistory();
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: const Color(0xFF1A1A2E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: const Text('SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyledEditField(TextEditingController controller, String label, IconData icon, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: Colors.cyanAccent, size: 20),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.cyanAccent)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
      ),
    );
  }
}
