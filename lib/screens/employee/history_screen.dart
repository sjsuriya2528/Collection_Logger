import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/collection_provider.dart';
import '../../models/collection.dart';
import '../../services/api_service.dart';
import 'add_collection_screen.dart';
import '../common/full_screen_image_viewer.dart';

class CollectionHistoryScreen extends StatefulWidget {
  const CollectionHistoryScreen({super.key});

  @override
  State<CollectionHistoryScreen> createState() => _CollectionHistoryScreenState();
}
class _CollectionHistoryScreenState extends State<CollectionHistoryScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedMode = 'all';
  String _selectedStatusFilter = 'all';
  final _searchController = TextEditingController();
  String _searchQuery = "";
  final Set<String> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day);
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
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final collProvider = Provider.of<CollectionProvider>(context);
    
    final filteredCollections = collProvider.collections.where((c) {
      // Date Filter
      bool matchesDate = true;
      if (_startDate != null && _endDate != null) {
        final rawDate = c.date;
        final localDate = rawDate.toLocal();
        final d = DateTime(localDate.year, localDate.month, localDate.day);
        matchesDate = d.isAfter(_startDate!.subtract(const Duration(days: 1))) && 
                      d.isBefore(_endDate!.add(const Duration(days: 1)));
      }

      // Mode Filter
      bool matchesMode = true;
      if (_selectedMode != 'all') {
        final mode = c.paymentMode.name.toLowerCase();
        matchesMode = mode == _selectedMode || (_selectedMode == 'upi' && mode == 'both');
      }

      // Status Filter
      bool matchesStatus = true;
      if (_selectedStatusFilter != 'all') {
        matchesStatus = c.status.toLowerCase() == _selectedStatusFilter;
      }

      // Search Filter
      bool matchesSearch = true;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        matchesSearch = c.shopName.toLowerCase().contains(query) || 
                        c.billNo.toLowerCase().contains(query);
      }

      return matchesDate && matchesMode && matchesSearch && matchesStatus;
    }).toList();

    // Summary Calculations
    final totalAmount = filteredCollections.fold(0.0, (sum, c) => sum + c.amount);
    final cashTotal = filteredCollections.fold(0.0, (s, c) => s + (c.paymentMode == PaymentMode.cash ? c.amount : (c.paymentMode == PaymentMode.both ? c.cashAmount : 0)));
    final upiTotal = filteredCollections.fold(0.0, (s, c) => s + (c.paymentMode == PaymentMode.upi ? c.amount : (c.paymentMode == PaymentMode.both ? c.upiAmount : 0)));
    final chequeTotal = filteredCollections.where((c) => c.paymentMode == PaymentMode.cheque).fold(0.0, (s, c) => s + c.amount);



    // Feature: n FIN (Completed bills count per shop)
    final Map<String, int> shopFinCounts = {};
    for (var c in filteredCollections) {
      if (c.status.toLowerCase().trim() == 'completed') {
        final key = c.shopName.trim().toLowerCase();
        shopFinCounts[key] = (shopFinCounts[key] ?? 0) + 1;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('History', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              Icons.tune_rounded, 
              color: (_startDate != null || _selectedMode != 'all') ? Colors.cyanAccent : Colors.white
            ),
            onPressed: () => _showFilterBottomSheet(),
          ),
        ],
      ),
      body: Column(
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
          
          // Summary Header
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
          Expanded(
            child: filteredCollections.isEmpty
              ? _buildEmptyState()
              : Builder(
                  builder: (context) {
                    final Map<String, List<Collection>> grouped = {};
                    for (var c in filteredCollections) {
                      final String timeKey = DateFormat('yyyyMMddHHmm').format(c.date);
                      final key = (c.groupId != null && c.groupId!.isNotEmpty) 
                        ? c.groupId! 
                        : "${c.shopName}_$timeKey";
                      if (!grouped.containsKey(key)) grouped[key] = [];
                      grouped[key]!.add(c);
                    }
                    final groupIds = grouped.keys.toList();
                    groupIds.sort((a, b) {
                      final dateA = grouped[a]!.first.date;
                      final dateB = grouped[b]!.first.date;
                      return dateB.compareTo(dateA);
                    });

                    return RefreshIndicator(
                      color: Colors.cyanAccent,
                      backgroundColor: const Color(0xFF1A1A2E),
                      onRefresh: () async {
                        final auth = Provider.of<AuthProvider>(context, listen: false);
                        final provider = Provider.of<CollectionProvider>(context, listen: false);
                        await provider.pullFromServer(auth.user!.token!, auth.user!.id.toString());
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.all(20),
                        physics: const AlwaysScrollableScrollPhysics(), // Ensures swipe works even if list is short
                        itemCount: groupIds.length,
                        itemBuilder: (context, index) {
                          final gid = groupIds[index];
                          final items = grouped[gid]!;
                          return _buildGroupedItem(gid, items, shopFinCounts);
                        },
                      ),
                    );
                  },
                ),
          ),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 80, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          const Text('No records found for these filters', style: TextStyle(color: Colors.white60)),
        ],
      ),
    );
  }

  Widget _buildGroupedItem(String groupId, List<Collection> items, Map<String, int> shopFinCounts) {
    final first = items.first;
    final bool isGroup = items.length > 1;
    final bool isExpanded = _expandedGroups.contains(groupId);
    final totalGroupAmount = items.fold(0.0, (sum, c) => sum + c.amount);
    // For unified payments, check if all items share the same paymentProof
    String? sharedPaymentProof;
    if (isGroup) {
      final proofItems = items.where((element) => element.paymentMode != PaymentMode.cash).toList();
      if (proofItems.isNotEmpty) {
        final firstP = proofItems.first.paymentProof;
        if (firstP != null && proofItems.every((element) => element.paymentProof == firstP)) {
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
          // Main Header Card
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
                                first.paymentMode.name.toUpperCase(),
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
                                  first.shopName, 
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                              if (shopFinCounts[first.shopName.trim().toLowerCase()] != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.greenAccent.withOpacity(0.3), width: 0.5),
                                  ),
                                  child: Text(
                                    '${shopFinCounts[first.shopName.trim().toLowerCase()]} FIN',
                                    style: const TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isGroup 
                              ? '${items.length} Bills • ${DateFormat('dd MMM, hh:mm a').format(first.date)}'
                              : '${first.billNo} • ${DateFormat('dd MMM, hh:mm a').format(first.date)}',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          if (sharedPaymentProof != null) ...[
                            const SizedBox(height: 8),
                            _buildProofChip('PAYMENT PROOF', sharedPaymentProof),
                          ] else if (!isGroup && (first.billProof != null || first.paymentProof != null)) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (first.billProof != null) _buildProofChip('BILL', first.billProof!),
                                if (first.paymentProof != null) ...[
                                  if (first.billProof != null) const SizedBox(width: 8),
                                  _buildProofChip('PAY', first.paymentProof!),
                                ],
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
                                   onPressed: () => Navigator.push(
                                     context,
                                     MaterialPageRoute(builder: (context) => AddCollectionScreen(initialItems: [first])),
                                   ),
                                 ),
                                 const SizedBox(width: 16),
                                 IconButton(
                                   padding: EdgeInsets.zero,
                                   constraints: const BoxConstraints(),
                                   icon: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent.withOpacity(0.7)),
                                   onPressed: () => _showDeleteConfirmation(first),
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
                        if (!isGroup && first.status.toLowerCase().trim() == 'completed')
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
          
          // Expanded Bills List
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

  Widget _buildSubBillItem(Collection coll, String? sharedPaymentProof, List<Collection> allItems, int index) {
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
                    Text('Bill #${coll.billNo}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      coll.paymentMode.name.toLowerCase() == 'both'
                        ? 'Mode: BOTH (Cash: ₹${coll.cashAmount.toInt()} + UPI: ₹${coll.upiAmount.toInt()})'
                        : 'Mode: ${coll.paymentMode.name.toUpperCase()}',
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
                  if (coll.status.toLowerCase().trim() == 'completed')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _buildStatusIcon(false),
                    ),
                  Text(
                    '₹${coll.amount.toInt()}',
                    style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (coll.billProof != null) _buildProofChip('BILL', coll.billProof!),
              if (coll.paymentProof != null && coll.paymentProof != sharedPaymentProof) ...[ 
                const SizedBox(width: 8),
                _buildProofChip('PAY', coll.paymentProof!),
              ],
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.white38),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddCollectionScreen(
                      initialItems: allItems, // Pass the whole group
                      initialIndex: index,     // Focus on this specific bill
                    )
                  ),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent.withOpacity(0.7)),
                onPressed: () => _showDeleteConfirmation(coll),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(Collection coll) {
    return _buildGroupedItem(coll.id, [coll], {});
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImageViewer(path: path, title: title),
      ),
    );
  }

  Widget _buildSummaryHeader(double total, double cash, double upi, double cheque) {
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
  void _showDeleteConfirmation(Collection? coll, {List<Collection>? items}) {
    final bool isGroup = items != null;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(isGroup ? 'Delete Entire Group?' : 'Delete Record?', style: const TextStyle(color: Colors.white)),
        content: Text(
          isGroup 
            ? 'This will delete all ${items.length} records in this group. Action cannot be undone.'
            : 'Are you sure you want to delete bill #${coll!.billNo}?', 
          style: const TextStyle(color: Colors.white70)
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(context);
              final auth = Provider.of<AuthProvider>(context, listen: false);
              final provider = Provider.of<CollectionProvider>(context, listen: false);
              
              if (isGroup) {
                bool allSuccess = true;
                for (var item in items) {
                  final success = await ApiService.deleteCollection(item.id, auth.user!.token!);
                  if (!success) allSuccess = false;
                }
                if (allSuccess) {
                  await provider.pullFromServer(auth.user!.token!, auth.user!.id.toString());
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group deleted'), backgroundColor: Colors.green));
                }
              } else {
                final success = await ApiService.deleteCollection(coll!.id, auth.user!.token!);
                if (success) {
                  await provider.pullFromServer(auth.user!.token!, auth.user!.id.toString());
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record deleted'), backgroundColor: Colors.green));
                }
              }
            },
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }
}
