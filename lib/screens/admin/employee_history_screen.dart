import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import '../../services/pdf_service.dart';
import '../common/pdf_preview_screen.dart';

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
  final Set<String> _expandedGroups = {};

  DateTime _parseDate(dynamic date) {
    String dateStr = date.toString();
    if (!dateStr.contains('Z') && !dateStr.contains('+')) {
      dateStr += 'Z';
    }
    return DateTime.parse(dateStr).toLocal();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day);
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
        String dateStr = c['date'].toString();
        if (!dateStr.contains('Z') && !dateStr.contains('+')) {
          dateStr += 'Z';
        }
        final rawDate = DateTime.parse(dateStr);
        final localDate = rawDate.toLocal();
        final d = DateTime(localDate.year, localDate.month, localDate.day);
        matchesDate = d.isAfter(_startDate!.subtract(const Duration(days: 1))) && 
                      d.isBefore(_endDate!.add(const Duration(days: 1)));
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

      // Search Filter
      bool matchesSearch = true;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        matchesSearch = c['shop_name'].toString().toLowerCase().contains(query) || 
                        c['bill_no'].toString().toLowerCase().contains(query);
      }

      return matchesDate && matchesMode && matchesSearch && matchesStatus;
    }).toList();

    // Summary Calculations
    final totalAmount = filtered.fold(0.0, (sum, c) => sum + double.parse(c['amount'].toString()));
    final cashTotal = filtered.fold(0.0, (s, c) {
      final mode = c['payment_mode'].toString().toLowerCase();
      if (mode == 'cash') return s + double.parse(c['amount'].toString());
      if (mode == 'both') return s + double.parse((c['cash_amount'] ?? 0).toString());
      return s;
    });
    final upiTotal = filtered.fold(0.0, (s, c) {
      final mode = c['payment_mode'].toString().toLowerCase();
      if (mode == 'upi') return s + double.parse(c['amount'].toString());
      if (mode == 'both') return s + double.parse((c['upi_amount'] ?? 0).toString());
      return s;
    });
    final chequeTotal = filtered.where((c) => c['payment_mode'].toString().toLowerCase() == 'cheque').fold(0.0, (s, c) => s + double.parse(c['amount'].toString()));

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
                final pdf = await PdfService.generateEmployeeReport(
                  employeeName: widget.employeeName,
                  collections: filtered,
                  startDate: _startDate,
                  endDate: _endDate,
                );

                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PdfPreviewScreen(
                        pdf: pdf,
                        fileName: '${widget.employeeName}_Report.pdf',
                      ),
                    ),
                  );
                }
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
      body: RefreshIndicator(
            onRefresh: _fetchHistory,
            color: Colors.cyanAccent,
            backgroundColor: const Color(0xFF16213E),
            child: Column(
              children: [
                _buildSummaryHeader(totalAmount, cashTotal, upiTotal, chequeTotal),
                if (_startDate != null || _selectedMode != 'all' || _selectedStatusFilter != 'all')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
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
                          onTap: () => setState(() { 
                            _startDate = null; 
                            _endDate = null; 
                            _selectedMode = 'all'; 
                            _selectedStatusFilter = 'all';
                          }),
                          child: const Text('Clear', style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
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
                Expanded(
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                    : filtered.isEmpty
                      ? _buildEmptyState()
                      : Builder(
                          builder: (context) {
                            // Grouping logic for Admin view
                            final Map<String, List<dynamic>> grouped = {};
                            for (var c in filtered) {
                              final gId = c['group_id']?.toString();
                              final dateStr = c['date'].toString();
                              final key = (gId != null && gId.isNotEmpty) 
                                ? gId 
                                : "${c['shop_name']}_$dateStr";
                              if (!grouped.containsKey(key)) grouped[key] = [];
                              grouped[key]!.add(c);
                            }
                            final groupIds = grouped.keys.toList();
                            groupIds.sort((a, b) {
                              String dateAStr = grouped[a]!.first['date'].toString();
                              String dateBStr = grouped[b]!.first['date'].toString();
                              if (!dateAStr.contains('Z') && !dateAStr.contains('+')) dateAStr += 'Z';
                              if (!dateBStr.contains('Z') && !dateBStr.contains('+')) dateBStr += 'Z';
                              
                              final dateA = DateTime.parse(dateAStr);
                              final dateB = DateTime.parse(dateBStr);
                              return dateB.compareTo(dateA);
                            });

                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: groupIds.length,
                              itemBuilder: (context, index) {
                                final gid = groupIds[index];
                                final items = grouped[gid]!;
                                return _buildGroupedItem(gid, items);
                              },
                            );
                          },
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

  Widget _buildGroupedItem(String groupId, List<dynamic> items) {
    final first = items.first;
    final bool isGroup = items.length > 1;
    final bool isExpanded = _expandedGroups.contains(groupId);
    final totalGroupAmount = items.fold(0.0, (sum, c) => sum + (double.tryParse(c['amount'].toString()) ?? 0));
    
    String? sharedPaymentProof;
    if (isGroup) {
      final proofItems = items.where((element) => element['payment_mode'].toString().toLowerCase() != 'cash').toList();
      if (proofItems.isNotEmpty) {
        final firstP = proofItems.first['payment_proof'];
        if (firstP != null && proofItems.every((element) => element['payment_proof'] == firstP)) {
          sharedPaymentProof = firstP;
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (isGroup) {
                  setState(() {
                    if (isExpanded) _expandedGroups.remove(groupId);
                    else _expandedGroups.add(groupId);
                  });
                }
              },
              borderRadius: BorderRadius.circular(24),
              splashColor: Colors.cyanAccent.withOpacity(0.1),
              highlightColor: Colors.cyanAccent.withOpacity(0.05),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Column(
                      children: [
                        if (!isGroup) 
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 0.5),
                              ),
                              child: Text(
                                first['payment_mode'].toString().toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.greenAccent, 
                                  fontSize: 7, 
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isGroup ? Icons.layers_rounded : Icons.storefront_rounded, 
                            color: Colors.cyanAccent
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            first['shop_name'].toString(), 
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isGroup 
                              ? '${items.length} Bills • ${DateFormat('dd MMM, hh:mm a').format(_parseDate(first['date']))}'
                              : '${first['bill_no']} • ${DateFormat('dd MMM, hh:mm a').format(_parseDate(first['date']))}',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          if (sharedPaymentProof != null) ...[
                            const SizedBox(height: 8),
                            _buildProofChip('PAYMENT PROOF', sharedPaymentProof),
                          ] else if (!isGroup && (first['bill_proof'] != null || first['payment_proof'] != null)) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (first['bill_proof'] != null) _buildProofChip('BILL', first['bill_proof']),
                                if (first['payment_proof'] != null) ...[
                                  if (first['bill_proof'] != null) const SizedBox(width: 8),
                                  _buildProofChip('PAY', first['payment_proof']),
                                ],
                              ],
                            ),
                          ],
                          if (!isGroup) ...[
                             const SizedBox(height: 12),
                             Row(
                               children: [
                                 IconButton(
                                   padding: EdgeInsets.zero,
                                   constraints: const BoxConstraints(),
                                   icon: const Icon(Icons.edit_rounded, size: 16, color: Colors.white38),
                                   onPressed: () => _showEditDialog(first),
                                 ),
                                 const SizedBox(width: 16),
                                 IconButton(
                                   padding: EdgeInsets.zero,
                                   constraints: const BoxConstraints(),
                                   icon: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent.withOpacity(0.7)),
                                   onPressed: () => _confirmDelete(first),
                                 ),
                               ],
                             ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Status Icon at Top Right (Only for single records)
                        if (!isGroup && (first['status'] ?? 'partial').toString().toLowerCase().trim() == 'completed')
                          _buildStatusIcon(true)
                        else
                          const SizedBox(height: 24), // Placeholder for alignment

                        const SizedBox(height: 4),
                        // Total Amount
                        Text(
                          '₹${totalGroupAmount.toInt()}',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),

                        if (isGroup) ...[
                          const SizedBox(height: 4),
                          Icon(
                            isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                            color: Colors.white38,
                            size: 20,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          if (isExpanded && isGroup) ...[
            const Divider(color: Colors.white10, height: 1),
            ...items.map((coll) => _buildSubBillItem(coll, sharedPaymentProof)).toList(),
            
            if (sharedPaymentProof != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.cyanAccent.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_scanner_rounded, color: Colors.cyanAccent, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Unified Payment Proof', style: TextStyle(color: Colors.white70, fontSize: 12))),
                      _buildProofChip('VIEW', sharedPaymentProof),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubBillItem(dynamic coll, String? sharedPaymentProof) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bill #${coll['bill_no']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      coll['payment_mode'].toString().toLowerCase() == 'both'
                        ? 'Mode: BOTH (Cash: ₹${(double.tryParse(coll['cash_amount'].toString()) ?? 0).toInt()} + UPI: ₹${(double.tryParse(coll['upi_amount'].toString()) ?? 0).toInt()})'
                        : 'Mode: ${coll['payment_mode'].toString().toUpperCase()}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if ((coll['status'] ?? 'partial').toString().toLowerCase().trim() == 'completed')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _buildStatusIcon(false),
                    ),
                  Text(
                    '₹${(double.tryParse(coll['amount'].toString()) ?? 0).toInt()}',
                    style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (coll['bill_proof'] != null) _buildProofChip('BILL', coll['bill_proof']),
              if (coll['payment_proof'] != null && coll['payment_proof'] != sharedPaymentProof) ...[ 
                const SizedBox(width: 8),
                _buildProofChip('PAY', coll['payment_proof']),
              ],
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.white38),
                onPressed: () => _showEditDialog(coll),
              ),
              const SizedBox(width: 16),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent.withOpacity(0.7)),
                onPressed: () => _confirmDelete(coll),
              ),
            ],
          ),
        ],
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

  Widget _buildStatusIcon(bool isLarge) {
    return Container(
      padding: EdgeInsets.all(isLarge ? 4 : 2),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.greenAccent.withOpacity(0.3), width: 1),
      ),
      child: Icon(
        Icons.check_rounded,
        color: Colors.greenAccent,
        size: isLarge ? 14 : 10,
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
    final imageUrl = ApiService.getImageUrl(path);
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
                leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: InteractiveViewer(
                      panEnabled: true,
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(40.0),
                              child: CircularProgressIndicator(color: Colors.cyanAccent),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Container(
                          padding: const EdgeInsets.all(40),
                          color: Colors.white.withOpacity(0.05),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
                              SizedBox(height: 8),
                              Text('Failed to load image', style: TextStyle(color: Colors.white60)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
    final cashController = TextEditingController(text: (coll['cash_amount'] ?? 0).toString());
    final upiController = TextEditingController(text: (coll['upi_amount'] ?? 0).toString());
    String mode = coll['payment_mode'].toString().toLowerCase();
    String status = coll['status'] ?? 'partial';
    String? billProof = coll['bill_proof'];
    String? paymentProof = coll['payment_proof'];
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickImg(bool isBill) async {
              showModalBottomSheet(
                context: context,
                backgroundColor: const Color(0xFF1A1A2E),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (context) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.photo_library_rounded, color: Colors.cyanAccent),
                      title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
                      onTap: () async {
                        Navigator.pop(context);
                        final picked = await picker.pickImage(
                          source: ImageSource.gallery, 
                          maxWidth: 800,
                          maxHeight: 800,
                          imageQuality: 30,
                        );
                        if (picked != null) setModalState(() { if (isBill) billProof = picked.path; else paymentProof = picked.path; });
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.camera_alt_rounded, color: Colors.cyanAccent),
                      title: const Text('Take a Photo', style: TextStyle(color: Colors.white)),
                      onTap: () async {
                        Navigator.pop(context);
                        final picked = await picker.pickImage(
                          source: ImageSource.camera, 
                          maxWidth: 800,
                          maxHeight: 800,
                          imageQuality: 30,
                        );
                        if (picked != null) setModalState(() { if (isBill) billProof = picked.path; else paymentProof = picked.path; });
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            }

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
                    const Text('Edit Record', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Update the collection details below', style: TextStyle(color: Colors.white38, fontSize: 14)),
                    const SizedBox(height: 32),
                    _buildStyledEditField(billController, 'Bill Number', Icons.receipt_long_rounded, isNumber: true),
                    const SizedBox(height: 16),
                    _buildStyledEditField(shopController, 'Shop Name', Icons.storefront_rounded),
                    const SizedBox(height: 16),
                    _buildStyledEditField(amountController, 'Amount (₹)', Icons.currency_rupee_rounded, isNumber: true, isReadOnly: mode == 'both'),
                    if (mode == 'both') ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildStyledEditField(cashController, 'Cash portion', Icons.money, isNumber: true, onChanged: (v) {
                            double c = double.tryParse(v) ?? 0;
                            double u = double.tryParse(upiController.text) ?? 0;
                            amountController.text = (c + u).toString();
                          })),
                          const SizedBox(width: 12),
                          Expanded(child: _buildStyledEditField(upiController, 'UPI portion', Icons.account_balance_wallet, isNumber: true, onChanged: (v) {
                            double u = double.tryParse(v) ?? 0;
                            double c = double.tryParse(cashController.text) ?? 0;
                            amountController.text = (c + u).toString();
                          })),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Text('PAYMENT MODE', style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: ['cash', 'upi', 'cheque', 'both'].map((m) {
                        final isSelected = mode == m;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setModalState(() {
                              mode = m;
                              if (m != 'upi' && m != 'both' && m != 'cheque') paymentProof = null;
                              if (m != 'both') {
                                cashController.text = '0';
                                upiController.text = '0';
                              }
                            }),
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
                    const SizedBox(height: 24),
                    const Text('PAYMENT STATUS', style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: ['partial', 'completed'].map((s) {
                        final isSelected = status == s;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setModalState(() {
                              status = s;
                              if (s != 'completed') billProof = null;
                            }),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? (s == 'completed' ? Colors.greenAccent : Colors.orangeAccent) : Colors.white.withOpacity(0.05),
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
                    const SizedBox(height: 32),
                    
                    if (status == 'completed') ...[
                      _buildEditProofButton(
                        label: 'Completed Bill Screenshot',
                        path: billProof,
                        onTap: () => pickImg(true),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (mode == 'upi' || mode == 'both' || mode == 'cheque') ...[
                      _buildEditProofButton(
                        label: 'Payment Screenshot / Cheque Photo',
                        path: paymentProof,
                        onTap: () => pickImg(false),
                      ),
                      const SizedBox(height: 16),
                    ],

                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: isSaving ? null : () async {
                          setModalState(() => isSaving = true);
                          try {
                            final auth = Provider.of<AuthProvider>(context, listen: false);
                            final updatedData = await ApiService.updateCollection(
                              coll['id'].toString(),
                              {
                                'bill_no': billController.text,
                                'shop_name': shopController.text,
                                'amount': amountController.text,
                                'payment_mode': mode,
                                'status': status,
                                'cash_amount': mode == 'both' ? cashController.text : (mode == 'cash' ? amountController.text : '0'),
                                'upi_amount': mode == 'both' ? upiController.text : (mode == 'upi' ? amountController.text : '0'),
                              },
                              auth.user!.token!,
                              billProofPath: billProof,
                              paymentProofPath: paymentProof,
                            );
                            if (updatedData != null && mounted) {
                              Navigator.pop(context);
                              _fetchHistory();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Changes saved successfully')));
                            } else if (mounted) {
                              setModalState(() => isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save changes')));
                            }
                          } catch (e) {
                            if (mounted) {
                              setModalState(() => isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent, 
                          foregroundColor: const Color(0xFF1A1A2E), 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          disabledBackgroundColor: Colors.cyanAccent.withOpacity(0.3),
                        ),
                        child: isSaving 
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Color(0xFF1A1A2E), strokeWidth: 2))
                          : const Text('SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStyledEditField(TextEditingController controller, String label, IconData icon, {bool isNumber = false, bool isReadOnly = false, Function(String)? onChanged}) {
    return TextField(
      key: ValueKey('edit_$label'),
      controller: controller,
      readOnly: isReadOnly,
      onChanged: onChanged,
      keyboardType: isNumber ? TextInputType.phone : TextInputType.text,
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

  Widget _buildEditProofButton({required String label, String? path, required VoidCallback onTap}) {
    final bool hasFile = path != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hasFile ? Colors.green.withOpacity(0.1) : Colors.cyanAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                hasFile ? Icons.check_circle_rounded : Icons.add_a_photo_rounded,
                color: hasFile ? Colors.greenAccent : Colors.cyanAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(
                    hasFile ? 'File selected' : 'Tap to upload screenshot',
                    style: TextStyle(color: hasFile ? Colors.greenAccent : Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryHeader(double total, double cash, double upi, double cheque) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.cyanAccent.withOpacity(0.1), Colors.blueAccent.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Collection', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    Text('₹${total.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Icon(Icons.account_balance_wallet_rounded, color: Colors.cyanAccent, size: 32),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSummaryCard('Cash', cash, Colors.orangeAccent),
              const SizedBox(width: 8),
              _buildSummaryCard('UPI', upi, Colors.greenAccent),
              const SizedBox(width: 8),
              _buildSummaryCard('Cheque', cheque, Colors.purpleAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, double amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                '₹${amount.toInt()}', 
                style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(dynamic coll) {
    final billController = TextEditingController(text: coll['bill_no']);
    final shopController = TextEditingController(text: coll['shop_name']);
    final amountController = TextEditingController(text: coll['amount'].toString());
    final cashController = TextEditingController(text: (coll['cash_amount'] ?? 0).toString());
    final upiController = TextEditingController(text: (coll['upi_amount'] ?? 0).toString());
    String mode = coll['payment_mode'];
    String status = coll['status'] ?? 'partial';
    String? billProof = coll['bill_proof'];
    String? paymentProof = coll['payment_proof'];
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickImg(bool isBill) async {
              showModalBottomSheet(
                context: context,
                backgroundColor: const Color(0xFF1A1A2E),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (context) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.photo_library_rounded, color: Colors.cyanAccent),
                      title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
                      onTap: () async {
                        Navigator.pop(context);
                        final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 30);
                        if (picked != null) setModalState(() { if (isBill) billProof = picked.path; else paymentProof = picked.path; });
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.camera_alt_rounded, color: Colors.cyanAccent),
                      title: const Text('Take a Photo', style: TextStyle(color: Colors.white)),
                      onTap: () async {
                        Navigator.pop(context);
                        final picked = await picker.pickImage(source: ImageSource.camera, maxWidth: 800, maxHeight: 800, imageQuality: 30);
                        if (picked != null) setModalState(() { if (isBill) billProof = picked.path; else paymentProof = picked.path; });
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            }

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
                    const Text('Edit Record (Admin)', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 32),
                    _buildAdminEditField(billController, 'Bill No', Icons.numbers, isNumber: true),
                    const SizedBox(height: 16),
                    _buildAdminEditField(shopController, 'Shop Name', Icons.store),
                    const SizedBox(height: 16),
                    _buildAdminEditField(amountController, 'Total Amount', Icons.currency_rupee, isNumber: true, isReadOnly: mode == 'both'),
                    if (mode == 'both') ...[
                       const SizedBox(height: 16),
                       Row(children: [
                         Expanded(child: _buildAdminEditField(cashController, 'Cash', Icons.money, isNumber: true, onChanged: (v) {
                            double c = double.tryParse(v) ?? 0;
                            double u = double.tryParse(upiController.text) ?? 0;
                            amountController.text = (c + u).toString();
                         })),
                         const SizedBox(width: 12),
                         Expanded(child: _buildAdminEditField(upiController, 'UPI', Icons.account_balance, isNumber: true, onChanged: (v) {
                            double u = double.tryParse(v) ?? 0;
                            double c = double.tryParse(cashController.text) ?? 0;
                            amountController.text = (c + u).toString();
                         })),
                       ]),
                    ],
                    
                    const SizedBox(height: 24),
                    const Text('PAYMENT MODE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['cash', 'upi', 'cheque', 'both'].map((m) {
                          final isSel = mode == m;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(m.toUpperCase()),
                              selected: isSel,
                              onSelected: (s) => setModalState(() {
                                mode = m;
                                if (m != 'upi' && m != 'both' && m != 'cheque') paymentProof = null;
                                if (m != 'both') {
                                  cashController.text = '0';
                                  upiController.text = '0';
                                }
                              }),
                              backgroundColor: Colors.white.withOpacity(0.05),
                              selectedColor: Colors.cyanAccent,
                              labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 24),
                    const Text('STATUS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: ['partial', 'completed'].map((s) {
                        final isSel = status == s;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setModalState(() {
                              status = s;
                              if (s != 'completed') billProof = null;
                            }),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isSel ? (s == 'completed' ? Colors.greenAccent : Colors.orangeAccent) : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(child: Text(s.toUpperCase(), style: TextStyle(color: isSel ? const Color(0xFF1A1A2E) : Colors.white60, fontSize: 12, fontWeight: FontWeight.bold))),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 24),
                    if ((status == 'completed') || (mode == 'upi' || mode == 'both' || mode == 'cheque')) ...[
                      const Text('PROOFS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (status == 'completed') ...[
                        _buildEditProofButton(label: 'Bill Proof', path: billProof, onTap: () => pickImg(true)),
                        const SizedBox(height: 12),
                      ],
                      if (mode == 'upi' || mode == 'both' || mode == 'cheque') ...[
                        _buildEditProofButton(label: 'Payment Proof', path: paymentProof, onTap: () => pickImg(false)),
                      ],
                    ],

                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: const Color(0xFF1A1A2E),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: isSaving ? null : () async {
                          setModalState(() => isSaving = true);
                          final auth = Provider.of<AuthProvider>(context, listen: false);
                          
                          final fields = {
                            'bill_no': billController.text,
                            'shop_name': shopController.text,
                            'amount': amountController.text,
                            'payment_mode': mode,
                            'status': status,
                            'cash_amount': mode == 'both' ? cashController.text : (mode == 'cash' ? amountController.text : '0'),
                            'upi_amount': mode == 'both' ? upiController.text : (mode == 'upi' ? amountController.text : '0'),
                          };

                          final result = await ApiService.updateCollection(
                            coll['id'], 
                            fields, 
                            auth.user!.token!,
                            billProofPath: billProof,
                            paymentProofPath: paymentProof,
                          );

                          if (result != null) {
                            _fetchHistory();
                            Navigator.pop(context);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated successfully')));
                          } else {
                            setModalState(() => isSaving = false);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Update failed'), backgroundColor: Colors.redAccent));
                          }
                        },
                        child: isSaving 
                          ? const CircularProgressIndicator(color: Color(0xFF1A1A2E))
                          : const Text('SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAdminEditField(TextEditingController controller, String label, IconData icon, {bool isNumber = false, bool isReadOnly = false, Function(String)? onChanged}) {
    return TextField(
      controller: controller,
      readOnly: isReadOnly,
      keyboardType: isNumber ? TextInputType.phone : TextInputType.text,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.cyanAccent, size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.cyanAccent)),
      ),
    );
  }

  Widget _buildAdminModeSelector(String current, Function(String) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PAYMENT MODE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: ['cash', 'upi', 'cheque', 'both'].map((m) {
            final isSel = current == m;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(m),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSel ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: Text(m.toUpperCase(), style: TextStyle(color: isSel ? Colors.black : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAdminStatusSelector(String current, Function(String) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('STATUS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: ['partial', 'completed'].map((s) {
            final isSel = current == s;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(s),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSel ? Colors.cyanAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSel ? Colors.cyanAccent : Colors.transparent),
                  ),
                  child: Center(child: Text(s.toUpperCase(), style: TextStyle(color: isSel ? Colors.cyanAccent : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
