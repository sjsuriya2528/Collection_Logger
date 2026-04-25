import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../providers/auth_provider.dart';
import '../../providers/collection_provider.dart';
import '../../models/collection.dart';

class AddCollectionScreen extends StatefulWidget {
  const AddCollectionScreen({super.key});

  @override
  State<AddCollectionScreen> createState() => _AddCollectionScreenState();
}

class _AddCollectionScreenState extends State<AddCollectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _billController = TextEditingController();
  final _shopController = TextEditingController();
  final _amountController = TextEditingController();
  final _cashController = TextEditingController();
  final _upiController = TextEditingController();
  PaymentMode _selectedMode = PaymentMode.cash;
  String _selectedStatus = 'partial';
  File? _billProof;
  File? _paymentProof;
  final _picker = ImagePicker();

  Future<void> _pickImage(bool isBill) async {
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
              final picked = await _picker.pickImage(
                source: ImageSource.gallery, 
                maxWidth: 800,
                maxHeight: 800,
                imageQuality: 30,
              );
              if (picked != null) setState(() { if (isBill) _billProof = File(picked.path); else _paymentProof = File(picked.path); });
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded, color: Colors.cyanAccent),
            title: const Text('Take a Photo', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              final picked = await _picker.pickImage(
                source: ImageSource.camera, 
                maxWidth: 800,
                maxHeight: 800,
                imageQuality: 30,
              );
              if (picked != null) setState(() { if (isBill) _billProof = File(picked.path); else _paymentProof = File(picked.path); });
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final collProvider = Provider.of<CollectionProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Add Collection', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Collection Details',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Text(
                'Enter the bill information below',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 32),
              _buildTextField(
                controller: _billController,
                label: 'Bill Number',
                icon: Icons.receipt_long_rounded,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _shopController,
                label: 'Shop Name',
                icon: Icons.storefront_rounded,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _amountController,
                label: 'Amount Collected (₹)',
                icon: Icons.currency_rupee_rounded,
                keyboardType: TextInputType.number,
                isReadOnly: _selectedMode == PaymentMode.both,
              ),
              const SizedBox(height: 32),
              const Text(
                'Payment Mode',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              _buildPaymentModeSelector(),
              const SizedBox(height: 24),
              const Text(
                'Payment Status',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              _buildStatusSelector(),
              const SizedBox(height: 32),
              if (_selectedMode == PaymentMode.both) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _cashController,
                        label: 'Cash Portion (₹)',
                        icon: Icons.money_rounded,
                        keyboardType: TextInputType.number,
                        onChanged: (val) => _updateTotalFromSplit(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _upiController,
                        label: 'UPI Portion (₹)',
                        icon: Icons.account_balance_wallet_rounded,
                        keyboardType: TextInputType.number,
                        onChanged: (val) => _updateTotalFromSplit(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '* Total amount will be auto-calculated',
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ],

              const SizedBox(height: 32),
              
              // Conditional Proof Uploads
              if (_selectedStatus == 'completed') ...[
                _buildProofButton(
                  label: 'Upload Completed Bill Screenshot',
                  file: _billProof,
                  onTap: () => _pickImage(true),
                ),
                const SizedBox(height: 16),
              ],
              if (_selectedMode == PaymentMode.upi || _selectedMode == PaymentMode.both) ...[
                _buildProofButton(
                  label: 'Upload UPI/GPay Screenshot',
                  file: _paymentProof,
                  onTap: () => _pickImage(false),
                ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      // Validation for proofs
                      if (_selectedStatus == 'completed' && _billProof == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload bill screenshot')));
                        return;
                      }
                      if ((_selectedMode == PaymentMode.upi || _selectedMode == PaymentMode.both) && _paymentProof == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload payment screenshot')));
                        return;
                      }

                      final newColl = Collection(
                        employeeId: auth.user!.id,
                        billNo: _billController.text,
                        shopName: _shopController.text,
                        amount: double.parse(_amountController.text.isEmpty ? '0' : _amountController.text),
                        paymentMode: _selectedMode,
                        date: DateTime.now(),
                        status: _selectedStatus,
                        billProof: _billProof?.path,
                        paymentProof: _paymentProof?.path,
                        cashAmount: _selectedMode == PaymentMode.both ? double.parse(_cashController.text.isEmpty ? '0' : _cashController.text) : (_selectedMode == PaymentMode.cash ? double.parse(_amountController.text.isEmpty ? '0' : _amountController.text) : 0),
                        upiAmount: _selectedMode == PaymentMode.both ? double.parse(_upiController.text.isEmpty ? '0' : _upiController.text) : (_selectedMode == PaymentMode.upi ? double.parse(_amountController.text.isEmpty ? '0' : _amountController.text) : 0),
                      );
                      
                      await collProvider.addCollection(newColl, auth.user!.token);
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Collection recorded successfully'),
                            backgroundColor: Colors.cyanAccent,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: const Color(0xFF1A1A2E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('SUBMIT RECORD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSelector() {
    return Row(
      children: [
        _buildStatusChip('partial', 'Partial Paid', Icons.pending_actions_rounded),
        const SizedBox(width: 12),
        _buildStatusChip('completed', 'Completed', Icons.check_circle_outline_rounded),
      ],
    );
  }

  Widget _buildStatusChip(String value, String label, IconData icon) {
    final isSelected = _selectedStatus == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedStatus = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF1A1A2E) : Colors.white60, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF1A1A2E) : Colors.white60,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateTotalFromSplit() {
    double cash = double.tryParse(_cashController.text) ?? 0;
    double upi = double.tryParse(_upiController.text) ?? 0;
    _amountController.text = (cash + upi).toString();
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    Function(String)? onChanged,
    bool isReadOnly = false,
  }) {
    return TextFormField(
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

  Widget _buildPaymentModeSelector() {
    return Row(
      children: PaymentMode.values.map((mode) {
        final isSelected = _selectedMode == mode;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedMode = mode;
                if (mode != PaymentMode.both) {
                  _cashController.clear();
                  _upiController.clear();
                }
              });
            },
            child: Container(
              margin: EdgeInsets.only(
                right: mode == PaymentMode.both ? 0 : 4,
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.1),
                ),
              ),
              child: Center(
                child: Text(
                  mode.name.toUpperCase(),
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF1A1A2E) : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
