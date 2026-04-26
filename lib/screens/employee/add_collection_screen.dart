import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/collection.dart';
import '../../providers/auth_provider.dart';
import '../../providers/collection_provider.dart';

class BillEntry {
  final TextEditingController billNoController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController cashController = TextEditingController();
  final TextEditingController upiController = TextEditingController();
  PaymentMode mode = PaymentMode.cash;
  String status = 'Partial';
  String? billProof;
  String? paymentProof;

  void dispose() {
    billNoController.dispose();
    amountController.dispose();
    cashController.dispose();
    upiController.dispose();
  }
}

class AddCollectionScreen extends StatefulWidget {
  const AddCollectionScreen({super.key});

  @override
  State<AddCollectionScreen> createState() => _AddCollectionScreenState();
}

class _AddCollectionScreenState extends State<AddCollectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopController = TextEditingController();
  final List<BillEntry> _bills = [BillEntry()];
  String? _sharedPaymentProof;
  bool _isSubmitting = false;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _shopController.dispose();
    for (var bill in _bills) {
      bill.dispose();
    }
    super.dispose();
  }

  void _addBill() {
    setState(() {
      _bills.add(BillEntry());
    });
  }

  void _removeBill(int index) {
    if (_bills.length > 1) {
      setState(() {
        _bills[index].dispose();
        _bills.removeAt(index);
      });
    }
  }

  bool _needsSharedPaymentProof() {
    final proofRequiredBills = _bills.where((b) => b.mode != PaymentMode.cash).toList();
    return proofRequiredBills.length > 1;
  }

  bool _isMixedModes() {
    // We no longer restrict mixed modes from using unified proof, 
    // but we keep this for specific UI checks if needed.
    return false; 
  }

  Future<void> _pickImage(Function(String) onPicked) async {
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
              final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 30);
              if (picked != null) onPicked(picked.path);
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded, color: Colors.cyanAccent),
            title: const Text('Take a Photo', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              final picked = await _picker.pickImage(source: ImageSource.camera, maxWidth: 800, maxHeight: 800, imageQuality: 30);
              if (picked != null) onPicked(picked.path);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_bills.any((b) => b.amountController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter amounts for all bills')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final collProvider = Provider.of<CollectionProvider>(context, listen: false);
      final shopName = _shopController.text;
      final batchGroupId = const Uuid().v4();
      final now = DateTime.now(); // We use a consistent time for the whole batch
      
      for (var bill in _bills) {
        String? billProof = bill.billProof;
        String? paymentProof = bill.paymentProof;
        
        if (_needsSharedPaymentProof() && (bill.mode == PaymentMode.upi || bill.mode == PaymentMode.cheque || bill.mode == PaymentMode.both)) {
          paymentProof = _sharedPaymentProof;
        }

        final collection = Collection(
          id: const Uuid().v4(),
          employeeId: auth.user!.id,
          billNo: bill.billNoController.text,
          shopName: shopName,
          amount: double.parse(bill.amountController.text),
          paymentMode: bill.mode,
          date: now,
          status: bill.status,
          billProof: billProof,
          paymentProof: paymentProof,
          cashAmount: bill.mode == PaymentMode.both ? (double.tryParse(bill.cashController.text) ?? 0) : 0,
          upiAmount: bill.mode == PaymentMode.both ? (double.tryParse(bill.upiController.text) ?? 0) : 0,
          groupId: batchGroupId,
        );

        await collProvider.addCollection(collection, auth.user!.token, syncImmediately: false);
      }

      // Trigger a single batch sync for all added bills
      if (auth.user!.token != null) {
        collProvider.syncAllPending(auth.user!.token!);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully added collections!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Add Collections', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('SHOP INFORMATION', Icons.store_rounded),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _shopController,
                label: 'Shop Name',
                icon: Icons.storefront_rounded,
              ),
              const SizedBox(height: 32),
              
              _buildSectionTitle('BILL DETAILS', Icons.receipt_long_rounded),
              const SizedBox(height: 12),
              
              ..._bills.asMap().entries.map((entry) => _buildBillCard(entry.key, entry.value)),
              
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _addBill,
                  icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.cyanAccent),
                  label: const Text('ADD ANOTHER BILL', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    backgroundColor: Colors.cyanAccent.withOpacity(0.05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              _buildProofSection(),
              const SizedBox(height: 40),
              
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: const Color(0xFF1A1A2E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSubmitting 
                    ? const CircularProgressIndicator(color: Color(0xFF1A1A2E))
                    : const Text('SUBMIT ALL COLLECTIONS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildBillCard(int index, BillEntry bill) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Bill #${index + 1}', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 14)),
              if (index > 0)
                IconButton(
                  onPressed: () => _removeBill(index),
                  icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTextField(controller: bill.billNoController, label: 'Bill Number', icon: Icons.numbers_rounded),
          const SizedBox(height: 16),
          _buildTextField(controller: bill.amountController, label: 'Amount Collected', icon: Icons.currency_rupee_rounded, keyboardType: TextInputType.number, onChanged: (v) => setState(() {})),
          const SizedBox(height: 24),
          _buildSectionTitle('PAYMENT MODE', Icons.payments_rounded),
          const SizedBox(height: 12),
          _buildModeSelector(bill),
          if (bill.mode == PaymentMode.both) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _buildTextField(controller: bill.cashController, label: 'Cash', icon: Icons.money, keyboardType: TextInputType.number, onChanged: (v) {
                double c = double.tryParse(v) ?? 0;
                double u = double.tryParse(bill.upiController.text) ?? 0;
                bill.amountController.text = (c + u).toString();
                setState(() {});
              })),
              const SizedBox(width: 12),
              Expanded(child: _buildTextField(controller: bill.upiController, label: 'UPI', icon: Icons.qr_code_rounded, keyboardType: TextInputType.number, onChanged: (v) {
                double u = double.tryParse(v) ?? 0;
                double c = double.tryParse(bill.cashController.text) ?? 0;
                bill.amountController.text = (c + u).toString();
                setState(() {});
              })),
            ]),
          ],
          const SizedBox(height: 24),
          _buildSectionTitle('BILL STATUS', Icons.check_circle_outline_rounded),
          const SizedBox(height: 12),
          _buildStatusSelector(bill),
          if (_isMixedModes() || bill.status == 'Completed' || (bill.mode != PaymentMode.cash && !_needsSharedPaymentProof()))
            _buildIndividualBillProofs(bill),
        ],
      ),
    );
  }

  Widget _buildIndividualBillProofs(BillEntry bill) {
    bool showBillProof = bill.status == 'Completed';
    bool showPaymentProof = bill.mode != PaymentMode.cash && (!_needsSharedPaymentProof() || _isMixedModes());
    if (!showBillProof && !showPaymentProof) return const SizedBox.shrink();
    return Column(
      children: [
        const SizedBox(height: 24),
        _buildSectionTitle('BILL PROOFS', Icons.camera_alt_rounded),
        const SizedBox(height: 12),
        Row(children: [
          if (showBillProof) Expanded(child: _buildProofButton(label: 'Bill Photo', file: bill.billProof != null ? File(bill.billProof!) : null, onTap: () => _pickImage((path) => setState(() => bill.billProof = path)))),
          if (showBillProof && showPaymentProof) const SizedBox(width: 12),
          if (showPaymentProof) Expanded(child: _buildProofButton(label: 'Payment Proof', file: bill.paymentProof != null ? File(bill.paymentProof!) : null, onTap: () => _pickImage((path) => setState(() => bill.paymentProof = path)))),
        ]),
      ],
    );
  }

  Widget _buildProofSection() {
    bool needsSharedPayment = _needsSharedPaymentProof() && !_isMixedModes();
    if (!needsSharedPayment) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('SHARED PAYMENT PROOF', Icons.qr_code_scanner_rounded),
        const SizedBox(height: 12),
        _buildProofButton(label: 'Unified Payment Proof', file: _sharedPaymentProof != null ? File(_sharedPaymentProof!) : null, onTap: () => _pickImage((path) => setState(() => _sharedPaymentProof = path))),
      ],
    );
  }

  Widget _buildModeSelector(BillEntry bill) => Container(
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
    child: Row(children: PaymentMode.values.map((mode) {
      bool isSelected = bill.mode == mode;
      return Expanded(child: GestureDetector(
        onTap: () => setState(() => bill.mode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: isSelected ? Colors.cyanAccent : Colors.transparent, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Icon(Icons.payment, color: isSelected ? const Color(0xFF1A1A2E) : Colors.white60, size: 16),
            Text(mode.name.toUpperCase(), style: TextStyle(color: isSelected ? const Color(0xFF1A1A2E) : Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
          ]),
        ),
      ));
    }).toList()),
  );

  Widget _buildStatusSelector(BillEntry bill) {
    return Row(
      children: ['Partial', 'Completed'].map((s) {
        bool isSelected = bill.status == s;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => bill.status = s),
            child: Container(
              margin: EdgeInsets.only(
                right: s == 'Partial' ? 8 : 0,
                left: s == 'Completed' ? 8 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? Colors.cyanAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.1)),
              ),
              child: Center(
                child: Text(
                  s,
                  style: TextStyle(
                    color: isSelected ? Colors.cyanAccent : Colors.white60,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    Function(String)? onChanged,
    bool isReadOnly = false,
  }) {
    return TextFormField(
      key: ValueKey(label),
      controller: controller,
      readOnly: isReadOnly,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: Colors.cyanAccent),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.cyanAccent),
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
      ),
      validator: (value) => value!.isEmpty ? 'Field required' : null,
    );
  }

  Widget _buildProofButton({required String label, File? file, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1), style: BorderStyle.solid),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: file != null ? Colors.green.withOpacity(0.1) : Colors.cyanAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                file != null ? Icons.check_circle_rounded : Icons.add_a_photo_rounded,
                color: file != null ? Colors.greenAccent : Colors.cyanAccent,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(
                    file != null ? 'Screenshot selected' : 'Tap to upload screenshot',
                    style: TextStyle(color: file != null ? Colors.greenAccent : Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (file != null) const Icon(Icons.edit_rounded, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.cyanAccent, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.cyanAccent,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
