import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import '../../services/pdf_service.dart';
import '../common/pdf_preview_screen.dart';
import '../employee/add_collection_screen.dart';
import '../common/full_screen_image_viewer.dart';
import '../../models/collection.dart';

class EmployeeHistoryScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const EmployeeHistoryScreen({super.key, required this.employeeId, required this.employeeName});

  @override
  State<EmployeeHistoryScreen> createState() => _EmployeeHistoryScreenState();
}

class _EmployeeHistoryScreenState extends State<EmployeeHistoryScreen> {
  final ScrollController _scrollController = ScrollController();
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

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      final data = await ApiService.getEmployeeCollections(widget.employeeId, auth.user!.token!)
          .timeout(const Duration(seconds: 10), onTimeout: () => []);
      _collections = data;
      
      final Map<String, int> finCounts = {};
      final Map<String, int> finNumbers = {};
      
      final sortedColls = List.from(_collections)..sort((a, b) {
        String dA = a['date'].toString();
        String dB = b['date'].toString();
        if (!dA.contains('Z') && !dA.contains('+')) dA += 'Z';
        if (!dB.contains('Z') && !dB.contains('+')) dB += 'Z';
        return (DateTime.tryParse(dA) ?? DateTime(0)).compareTo(DateTime.tryParse(dB) ?? DateTime(0));
      });

      for (var c in sortedColls) {
        if ((c['status'] ?? 'partial').toString().toLowerCase().trim() == 'completed') {
          final shopKey = c['shop_name']?.toString().trim().toLowerCase() ?? "";
          if (shopKey.isEmpty) continue;

          // Parse date
          String dStr = c['date'].toString();
          if (!dStr.contains('Z') && !dStr.contains('+')) dStr += 'Z';
          final date = DateTime.tryParse(dStr)?.toLocal() ?? DateTime(0);
          final dateDay = '${date.year}-${date.month}-${date.day}';

          // A settlement = group_id if grouped, otherwise the specific calendar day
          final gId = c['group_id']?.toString() ?? '';
          final settlementKey = gId.isNotEmpty
              ? '${shopKey}__group__$gId'
              : '${shopKey}__date__$dateDay';

          // Assign FIN per unique settlement, not per individual bill
          finCounts.putIfAbsent(settlementKey, () {
            final shopSettlementCount = finCounts.keys
                .where((k) => k.startsWith('${shopKey}__'))
                .length;
            return shopSettlementCount + 1;
          });
          finNumbers[c['id'].toString()] = finCounts[settlementKey]!;
        }
      }

      _collectionFinNumbers = finNumbers;
      
      _updateFilteredData();
    } catch (e) {
      print('History Fetch Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<dynamic> _cachedFiltered = [];
  int _outletCount = 0;
  double _totalAmount = 0;
  double _cashTotal = 0;
  double _upiTotal = 0;
  double _chequeTotal = 0;
  Map<String, int> _collectionFinNumbers = {};

  void _updateFilteredData() {
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

    double total = 0;
    double cash = 0;
    double upi = 0;
    double cheque = 0;
    final Map<String, int> finCounts = {};
    final Map<String, List<dynamic>> tempGrouped = {};

    for (var c in filtered) {
      final amt = double.tryParse(c['amount'].toString()) ?? 0;
      final mode = c['payment_mode'].toString().toLowerCase();
      
      final gId = c['group_id']?.toString();
      final dateStr = c['date'].toString();
      final key = (gId != null && gId.isNotEmpty) 
        ? gId 
        : "${c['shop_name']}_$dateStr";
      if (!tempGrouped.containsKey(key)) tempGrouped[key] = [];
      tempGrouped[key]!.add(c);
      total += amt;
      if (mode == 'cash') cash += amt;
      else if (mode == 'upi') upi += amt;
      else if (mode == 'cheque') cheque += amt;
      else if (mode == 'both') {
        cash += double.tryParse((c['cash_amount'] ?? 0).toString()) ?? 0;
        upi += double.tryParse((c['upi_amount'] ?? 0).toString()) ?? 0;
      }

      if ((c['status'] ?? 'partial').toString().toLowerCase().trim() == 'completed') {
        final key = c['shop_name']?.toString().trim().toLowerCase() ?? "";
        if (key.isNotEmpty) finCounts[key] = (finCounts[key] ?? 0) + 1;
      }
    }

    setState(() {
      _cachedFiltered = filtered;
      _outletCount = tempGrouped.length;
      _totalAmount = total;
      _cashTotal = cash;
      _upiTotal = upi;
      _chequeTotal = cheque;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _fetchHistory,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.cyanAccent),
              onPressed: () async {
              if (_cachedFiltered.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No records to export')),
                );
                return;
              }
              
              // Show loading overlay
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => PopScope(
                  canPop: false,
                  child: AlertDialog(
                    backgroundColor: const Color(0xFF16213E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    content: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 3),
                          const SizedBox(height: 20),
                          const Text(
                            'Generating PDF Report...',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_cachedFiltered.length} records',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              // Yield the event loop so the dialog can render before heavy synchronous work blocks the UI thread
              await Future.delayed(const Duration(milliseconds: 150));

              try {
                final pdfBytes = await PdfService.generateEmployeeReport(
                  employeeName: widget.employeeName,
                  collections: _cachedFiltered,
                  startDate: _startDate,
                  endDate: _endDate,
                );

                if (mounted) {
                  Navigator.pop(context); // Close loading dialog
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PdfPreviewScreen(
                        pdfBytes: pdfBytes,
                        fileName: '${widget.employeeName}_Report.pdf',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context); // Close loading dialog
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
                _buildSummaryHeader(_totalAmount, _cashTotal, _upiTotal, _chequeTotal, _outletCount),
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
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      _searchQuery = val;
                      _updateFilteredData();
                    },
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
                              _searchQuery = "";
                              _updateFilteredData();
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
                    : _cachedFiltered.isEmpty
                      ? _buildEmptyState()
                      : Builder(
                          builder: (context) {
                            // Grouping logic for Admin view
                            final Map<String, List<dynamic>> grouped = {};
                            for (var c in _cachedFiltered) {
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

                            return Scrollbar(
                              thumbVisibility: Platform.isWindows || Platform.isMacOS || Platform.isLinux,
                              controller: _scrollController,
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: groupIds.length,
                                itemBuilder: (context, index) {
                                  final gid = groupIds[index];
                                  final items = grouped[gid]!;
                                  return _buildGroupedItem(gid, items);
                                },
                              ),
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
    
    // FIN = number of completed bills within this card/group
    final completedCount = items.where((c) =>
      (c['status'] ?? 'partial').toString().toLowerCase().trim() == 'completed'
    ).length;
    
    String? sharedPaymentProof;
    if (isGroup) {
      final proofItems = items.where((element) => element['payment_mode'].toString().toLowerCase() != 'cash').toList();
      if (proofItems.length > 1) {
        final firstP = proofItems.first['payment_proof'];
        if (firstP != null && firstP.toString().trim().isNotEmpty && proofItems.every((element) => element['payment_proof'] == firstP)) {
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  first['shop_name'].toString(), 
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                              if (completedCount > 0) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.greenAccent.withOpacity(0.3), width: 0.5),
                                      ),
                                      child: Text(
                                        '$completedCount FIN',
                                        style: const TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                            ],
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
                            _buildProofChip('PAYMENT PROOF', [sharedPaymentProof!]),
                          ] else if (!isGroup && ((first['bill_proof'] != null && first['bill_proof'].toString().trim().isNotEmpty) || (first['payment_proof'] != null && first['payment_proof'].toString().trim().isNotEmpty))) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (first['bill_proof'] != null && first['bill_proof'].toString().trim().isNotEmpty) 
                                  _buildProofChip('BILL', first['bill_proof'].toString().split(',').where((e) => e.trim().isNotEmpty).toList()),
                                if (first['payment_proof'] != null && first['payment_proof'].toString().trim().isNotEmpty) 
                                  _buildProofChip('PAY', [first['payment_proof'].toString()]),
                              ],
                            ),
                          ],
                          if (isGroup) ...[
                             const SizedBox(height: 8),
                          ] else ...[
                             const SizedBox(height: 12),
                             Row(
                               children: [
                                 IconButton(
                                   padding: EdgeInsets.zero,
                                   constraints: const BoxConstraints(),
                                   icon: const Icon(Icons.edit_rounded, size: 16, color: Colors.white38),
                                   onPressed: () => _showEditScreen(first),
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
            ...items.asMap().entries.map((entry) => _buildSubBillItem(entry.value, sharedPaymentProof, items, entry.key)).toList(),
            
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
                      _buildProofChip('VIEW', [sharedPaymentProof!]),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubBillItem(dynamic coll, String? sharedPaymentProof, List<dynamic> allItems, int index) {
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
              // Individual bill proofs
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if ((coll['billProof'] ?? coll['bill_proof']) != null && (coll['billProof'] ?? coll['bill_proof']).toString().trim().isNotEmpty)
                      _buildProofChip('BILL', (coll['billProof'] ?? coll['bill_proof']).toString().split(',').where((e) => e.trim().isNotEmpty).toList()),
                    
                    if ((coll['paymentProof'] ?? coll['payment_proof']) != null && 
                        (coll['paymentProof'] ?? coll['payment_proof']).toString().trim().isNotEmpty &&
                        (coll['paymentProof'] ?? coll['payment_proof']) != sharedPaymentProof)
                      _buildProofChip('PAY', [(coll['paymentProof'] ?? coll['payment_proof']).toString()]),
                  ],
                ),
              ),
               const Spacer(),
               IconButton(
                 padding: EdgeInsets.zero,
                 constraints: const BoxConstraints(),
                 icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.white38),
                 onPressed: () {
                   Navigator.push(
                     context, 
                     MaterialPageRoute(
                       builder: (context) => AddCollectionScreen(
                         initialItems: allItems.map((i) => Collection.fromMap(i)).toList(),
                         initialIndex: index,
                       )
                     )
                   ).then((_) => _fetchHistory());
                 },
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

  void _confirmDelete(dynamic coll, {List<dynamic>? items}) {
    final bool isGroup = items != null;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(isGroup ? 'Delete Entire Group?' : 'Delete Record', style: const TextStyle(color: Colors.white)),
        content: Text(
          isGroup 
            ? 'This will delete all ${items.length} records in this group. This cannot be undone.'
            : 'Are you sure you want to delete the record for "${coll['shop_name']}"? This cannot be undone.', 
          style: const TextStyle(color: Colors.white70)
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final auth = Provider.of<AuthProvider>(context, listen: false);
              
              if (isGroup) {
                bool allSuccess = true;
                for (var item in items) {
                  final success = await ApiService.deleteCollection(item['id'], auth.user!.token!);
                  if (!success) allSuccess = false;
                }
                if (allSuccess) {
                  _fetchHistory();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group deleted successfully')));
                }
              } else {
                final success = await ApiService.deleteCollection(coll['id'], auth.user!.token!);
                if (success) {
                  _fetchHistory();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record deleted successfully')));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete record'), backgroundColor: Colors.redAccent));
                }
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

  Widget _buildProofChip(String label, List<String> paths) {
    return GestureDetector(
      onTap: () => _showImageViewer(paths, label),
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

  void _showImageViewer(List<String> paths, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImageViewer(paths: paths, title: title),
      ),
    );
  }

  void _showFilterBottomSheet() {
    // Use temp variables so canceling doesn't apply half-changes
    DateTime? tempStart = _startDate;
    DateTime? tempEnd = _endDate;
    String tempMode = _selectedMode;
    String tempStatus = _selectedStatusFilter;

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
                        final isSelected = tempStatus == s;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setModalState(() => tempStatus = s),
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
                          final isSelected = tempMode == m;
                          return GestureDetector(
                            onTap: () => setModalState(() => tempMode = m),
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
                        Expanded(child: _buildDateTile('Start Date', tempStart, (d) => setModalState(() => tempStart = d))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildDateTile('End Date', tempEnd, (d) => setModalState(() => tempEnd = d))),
                      ],
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          // Commit temp values to parent state and re-filter
                          setState(() {
                            _startDate = tempStart;
                            _endDate = tempEnd;
                            _selectedMode = tempMode;
                            _selectedStatusFilter = tempStatus;
                          });
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

  void _showEditScreen(dynamic collMap) {
    final coll = Collection.fromMap(collMap as Map<String, dynamic>);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddCollectionScreen(initialItems: [coll])),
    ).then((_) => _fetchHistory());
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

  Widget _buildSummaryHeader(double total, double cash, double upi, double cheque, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
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
                          if (_startDate != null && _endDate != null && 
                              _startDate!.year == DateTime.now().year && _startDate!.month == DateTime.now().month && _startDate!.day == DateTime.now().day &&
                              _endDate!.year == DateTime.now().year && _endDate!.month == DateTime.now().month && _endDate!.day == DateTime.now().day &&
                              _selectedMode == 'all' && _selectedStatusFilter == 'all') ...[
                            const SizedBox(height: 4),
                            Text('No of Outlets: $count', style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ],
                      ),
                      const Icon(Icons.account_balance_wallet_rounded, color: Colors.cyanAccent, size: 32),
                    ],
                  ),
                ),
              ),
            ],
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


}
