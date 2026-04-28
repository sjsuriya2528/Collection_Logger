import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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
        matchesDate = date.isAfter(_startDate!.subtract(const Duration(days: 1))) && 
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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(coll['shop_name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        const Spacer(),
                        Text(DateFormat('dd MMM, hh:mm a').format(date.toLocal()), style: const TextStyle(color: Colors.white30, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 12, color: Colors.cyanAccent),
                        const SizedBox(width: 4),
                        Text(coll['employee_name'] ?? 'Unknown', style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                        const SizedBox(width: 12),
                        const Icon(Icons.confirmation_number_outlined, size: 12, color: Colors.white30),
                        const SizedBox(width: 4),
                        Text('Bill #${coll['bill_no']}', style: const TextStyle(color: Colors.white30, fontSize: 12)),
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
    final amountController = TextEditingController(text: coll['amount'].toString());
    final shopController = TextEditingController(text: coll['shop_name']);
    final billController = TextEditingController(text: coll['bill_no']);
    String mode = coll['payment_mode'];
    String status = coll['status'] ?? 'partial';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit Collection', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: shopController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Shop Name', Icons.storefront),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: billController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Bill No', Icons.confirmation_number),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Amount', Icons.currency_rupee),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Payment Mode', style: TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: ['cash', 'upi', 'cheque', 'both'].map((m) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(m.toUpperCase()),
                    selected: mode == m,
                    onSelected: (s) => setSheetState(() => mode = m),
                    backgroundColor: Colors.white.withOpacity(0.05),
                    selectedColor: Colors.cyanAccent,
                    labelStyle: TextStyle(color: mode == m ? Colors.black : Colors.white, fontSize: 10),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Mark as Completed', style: TextStyle(color: Colors.white, fontSize: 14)),
                value: status == 'completed',
                onChanged: (v) => setSheetState(() => status = v ? 'completed' : 'partial'),
                activeColor: Colors.cyanAccent,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    final auth = Provider.of<AuthProvider>(context, listen: false);
                    final fields = {
                      'shop_name': shopController.text,
                      'bill_no': billController.text,
                      'amount': amountController.text,
                      'payment_mode': mode,
                      'status': status,
                    };
                    final result = await ApiService.updateCollection(coll['id'], fields, auth.user!.token!);
                    if (result != null) {
                      Navigator.pop(context);
                      _fetchData();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated successfully')));
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: const Text('SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.cyanAccent, size: 20),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.cyanAccent)),
      filled: true,
      fillColor: Colors.white.withOpacity(0.02),
    );
  }
}
