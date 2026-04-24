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
  PaymentMode _selectedMode = PaymentMode.cash;
  String _selectedStatus = 'partial';
  File? _billProof;
  File? _paymentProof;
  final _picker = ImagePicker();

  Future<void> _pickImage(bool isBill) async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (pickedFile != null) {
      setState(() {
        if (isBill) {
          _billProof = File(pickedFile.path);
        } else {
          _paymentProof = File(pickedFile.path);
        }
      });
    }
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
              
              // Conditional Proof Uploads
              if (_selectedStatus == 'completed') ...[
                _buildProofButton(
                  label: 'Upload Completed Bill Screenshot',
                  file: _billProof,
                  onTap: () => _pickImage(true),
                ),
                const SizedBox(height: 16),
              ],
              if (_selectedMode == PaymentMode.upi) ...[
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
                      if (_selectedMode == PaymentMode.upi && _paymentProof == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload payment screenshot')));
                        return;
                      }

                      final newColl = Collection(
                        employeeId: auth.user!.id,
                        billNo: _billController.text,
                        shopName: _shopController.text,
                        amount: double.parse(_amountController.text),
                        paymentMode: _selectedMode,
                        date: DateTime.now(),
                        status: _selectedStatus,
                        billProof: _billProof?.path,
                        paymentProof: _paymentProof?.path,
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
    TextInputType keyboardType = TextInputType.text
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
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
            onTap: () => setState(() => _selectedMode = mode),
            child: Container(
              margin: EdgeInsets.only(
                right: mode == PaymentMode.cheque ? 0 : 8,
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
