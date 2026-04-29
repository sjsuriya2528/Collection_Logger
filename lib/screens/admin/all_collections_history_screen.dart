import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/pdf_service.dart';
import '../common/pdf_preview_screen.dart';

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
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      final data = await ApiService.getAllCollections(auth.user!.token!);
      setState(() {
        _allCollections = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  List<dynamic> get _filteredCollections {
    return _allCollections.where((c) {
      final date = DateTime.parse(c['date']);
      bool matchesDate = true;
      if (_startDate != null && _endDate != null) {
        matchesDate = !date.isBefore(_startDate!) && 
                      date.isBefore(_endDate!.add(const Duration(days: 1)));
      }
      
      final query = _searchController.text.toLowerCase();
      bool matchesSearch = c['shop_name'].toString().toLowerCase().contains(query) ||
                          c['bill_no'].toString().toLowerCase().contains(query) ||
                          (c['employee_name'] ?? '').toString().toLowerCase().contains(query);
      
      return matchesDate && matchesSearch;
    }).toList()..sort((a, b) => b['date'].compareTo(a['date']));
  }

  double get _totalAmount => _filteredCollections.fold(0, (sum, item) => sum + (double.tryParse(item['amount'].toString()) ?? 0));
  double get _cashAmount => _filteredCollections.where((e) => e['payment_mode'] == 'cash').fold(0, (sum, item) => sum + (double.tryParse(item['amount'].toString()) ?? 0));
  double get _upiAmount => _filteredCollections.where((e) => e['payment_mode'] == 'upi').fold(0, (sum, item) => sum + (double.tryParse(item['amount'].toString()) ?? 0));
  double get _chequeAmount => _filteredCollections.where((e) => e['payment_mode'] == 'cheque').fold(0, (sum, item) => sum + (double.tryParse(item['amount'].toString()) ?? 0));

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
              : _filteredCollections.isEmpty 
                ? const Center(child: Text('No records found', style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredCollections.length,
                    itemBuilder: (context, index) => _buildCollectionCard(_filteredCollections[index]),
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
        ? await PdfService.generateEmployeeWiseReport(collections: _filteredCollections, startDate: _startDate, endDate: _endDate)
        : await PdfService.generateCollectionWiseReport(collections: _filteredCollections, startDate: _startDate, endDate: _endDate);
      
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
            onChanged: (v) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search shop, bill or employee...',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.search, color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildDateChip(
                  _startDate == null ? 'Start Date' : DateFormat('dd MMM').format(_startDate!),
                  () => _selectDate(true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDateChip(
                  _endDate == null ? 'End Date' : DateFormat('dd MMM').format(_endDate!),
                  () => _selectDate(false),
                ),
              ),
              if (_startDate != null || _endDate != null)
                IconButton(
                  onPressed: () => setState(() { _startDate = null; _endDate = null; }),
                  icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.05))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.cyanAccent),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => start ? _startDate = picked : _endDate = picked);
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
                    Text(
                      coll['shop_name'], 
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
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
          if (coll['bill_proof'] != null || coll['payment_proof'] != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (coll['bill_proof'] != null) _buildProofChip('BILL', coll['bill_proof']),
                if (coll['payment_proof'] != null) ...[
                  const SizedBox(width: 8),
                  _buildProofChip('PAY', coll['payment_proof']),
                ],
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _showEditDialog(coll),
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

  Widget _buildProofChip(String label, String path) {
    return GestureDetector(
      onTap: () => _showImageViewer(path, label),
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

  void _showImageViewer(String path, String title) {
    final imageUrl = ApiService.getImageUrl(path);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                        return const Center(child: Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator(color: Colors.cyanAccent)));
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

  void _showEditDialog(dynamic coll) {
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
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 24, left: 24, right: 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 24),
                    const Text('Edit Collection (Admin)', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 32),
                    _buildAdminEditField(billController, 'Bill Number', Icons.numbers, isNumber: true),
                    const SizedBox(height: 16),
                    _buildAdminEditField(shopController, 'Shop Name', Icons.storefront_rounded),
                    const SizedBox(height: 16),
                    _buildAdminEditField(amountController, 'Total Amount', Icons.currency_rupee, isNumber: true, isReadOnly: mode == 'both'),
                    
                    if (mode == 'both') ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
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
                        ],
                      ),
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
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
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
                            _fetchData();
                            Navigator.pop(context);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated successfully')));
                          } else {
                            setModalState(() => isSaving = false);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Update failed'), backgroundColor: Colors.redAccent));
                          }
                        },
                        child: isSaving ? const CircularProgressIndicator(color: Colors.black) : const Text('SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 32),
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
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.cyanAccent, size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.cyanAccent)),
      ),
    );
  }

  Widget _buildEditProofButton({required String label, String? path, required VoidCallback onTap}) {
    final bool hasFile = path != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.1))),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: hasFile ? Colors.green.withOpacity(0.1) : Colors.cyanAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(hasFile ? Icons.check_circle_rounded : Icons.add_a_photo_rounded, color: hasFile ? Colors.greenAccent : Colors.cyanAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(hasFile ? 'Image attached' : 'Tap to upload screenshot', style: TextStyle(color: hasFile ? Colors.greenAccent : Colors.white38, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
