import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/collection.dart';
import '../../providers/auth_provider.dart';
import '../../providers/collection_provider.dart';
import '../../services/api_service.dart';

class BillEntry {
  String? id;
  final TextEditingController billNoController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController cashController = TextEditingController();
  final TextEditingController upiController = TextEditingController();
  PaymentMode mode = PaymentMode.cash;
  String status = 'Partial';
  List<String> billProofs = [];
  String? paymentProof;

  void dispose() {
    billNoController.dispose();
    amountController.dispose();
    cashController.dispose();
    upiController.dispose();
  }
}

class AddCollectionScreen extends StatefulWidget {
  final List<Collection>? initialItems;
  final int? initialIndex; // New: To scroll to specific bill
  const AddCollectionScreen({super.key, this.initialItems, this.initialIndex});

  @override
  State<AddCollectionScreen> createState() => _AddCollectionScreenState();
}

class _AddCollectionScreenState extends State<AddCollectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopController = TextEditingController();
  List<BillEntry> _bills = [BillEntry()];
  bool _isSubmitting = false;
  final _picker = ImagePicker();
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _billKeys = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      _shopController.text = widget.initialItems!.first.shopName;
      _bills = widget.initialItems!.map((item) {
        _billKeys.add(GlobalKey()); // Key for each card
        final entry = BillEntry();
        entry.id = item.id;
        entry.billNoController.text = item.billNo;
        entry.amountController.text = item.amount > 0 ? item.amount.toString().replaceAll(RegExp(r'\.0$'), '') : '';
        entry.mode = item.paymentMode;
        entry.status = item.status;
        entry.billProofs = item.billProofsList;
        entry.paymentProof = item.paymentProof;
        entry.cashController.text = item.cashAmount > 0 ? item.cashAmount.toString().replaceAll(RegExp(r'\.0$'), '') : '';
        entry.upiController.text = item.upiAmount > 0 ? item.upiAmount.toString().replaceAll(RegExp(r'\.0$'), '') : '';
        return entry;
      }).toList();

      // Scroll to specific bill after build
      if (widget.initialIndex != null && widget.initialIndex! < _bills.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToIndex(widget.initialIndex!);
        });
      }
    } else {
       _billKeys.add(GlobalKey());
    }
  }

  void _scrollToIndex(int index) {
    final context = _billKeys[index].currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context, 
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _shopController.dispose();
    _scrollController.dispose();
    for (var bill in _bills) {
      bill.dispose();
    }
    super.dispose();
  }

  void _addBill() {
    setState(() {
      _billKeys.add(GlobalKey());
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

  bool _isMixedModes() {
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
              final picked = await _picker.pickImage(
                source: ImageSource.gallery, 
                imageQuality: 85,
                maxWidth: 1800,
                maxHeight: 1800,
              );
              if (picked != null) onPicked(picked.path);
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded, color: Colors.cyanAccent),
            title: const Text('Take a Photo', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              final picked = await _picker.pickImage(
                source: ImageSource.camera, 
                imageQuality: 85,
                maxWidth: 1800,
                maxHeight: 1800,
              );
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingContext) => const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
    );

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final collProvider = Provider.of<CollectionProvider>(context, listen: false);
      final bool isEdit = widget.initialItems != null;
      final shopName = _shopController.text;
      final batchGroupId = isEdit ? (widget.initialItems!.first.groupId ?? const Uuid().v4()) : const Uuid().v4();
      final date = isEdit ? widget.initialItems!.first.date : DateTime.now();
      
      // If editing, we might need to handle records that were removed from the list
      if (isEdit) {
        final currentIds = _bills.map((b) => b.id).whereType<String>().toList();

        for (var oldItem in widget.initialItems!) {
          if (!currentIds.contains(oldItem.id)) {
            if (auth.user!.token != null) {
              await ApiService.deleteCollection(oldItem.id, auth.user!.token!);
            }
            await collProvider.deleteCollection(oldItem.id); 
          }
        }
      }

      for (int i = 0; i < _bills.length; i++) {
        final bill = _bills[i];
        String? billProof = bill.billProofs.join(',');
        String? paymentProof = bill.paymentProof;
        
        final id = bill.id ?? const Uuid().v4();
        
        final employeeId = isEdit 
            ? widget.initialItems!.firstWhere((item) => item.id == bill.id, orElse: () => widget.initialItems!.first).employeeId
            : auth.user!.id;

        final collection = Collection(
          id: id,
          employeeId: employeeId,
          billNo: bill.billNoController.text,
          shopName: shopName,
          amount: double.parse(bill.amountController.text),
          paymentMode: bill.mode,
          date: date,
          status: bill.status,
          billProof: billProof,
          paymentProof: paymentProof,
          cashAmount: bill.mode == PaymentMode.both ? (double.tryParse(bill.cashController.text) ?? 0) : 0,
          upiAmount: bill.mode == PaymentMode.both ? (double.tryParse(bill.upiController.text) ?? 0) : 0,
          groupId: batchGroupId,
          isSynced: false, // Mark as unsynced for re-upload
        );

        if (isEdit && bill.id != null) {
          await collProvider.updateCollection(collection);
        } else {
          await collProvider.addCollection(collection, auth.user!.token, syncImmediately: false);
        }
      }

      // Trigger a batch sync in the background (do NOT await it so the UI doesn't hang)
      if (auth.user!.token != null) {
        collProvider.syncAllPending(auth.user!.token!);
      }

      // Artificial 1 second delay for visual confirmation
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        Navigator.pop(context); // Go back to history
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEdit ? 'Collection updated!' : 'Successfully added collections!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
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
        title: Text(widget.initialItems != null ? 'Edit Collection' : 'Add Collections', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    : Text(widget.initialItems != null ? 'SAVE CHANGES' : 'SUBMIT ALL COLLECTIONS', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
      key: _billKeys[index],
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF22223B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
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
          _buildTextField(controller: bill.billNoController, label: 'Bill Number', icon: Icons.numbers_rounded, keyboardType: TextInputType.phone, isRequired: false),
          const SizedBox(height: 16),
          _buildTextField(controller: bill.amountController, label: 'Amount Collected', icon: Icons.currency_rupee_rounded, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) => setState(() {})),
          const SizedBox(height: 24),
          _buildSectionTitle('PAYMENT MODE', Icons.payments_rounded),
          const SizedBox(height: 12),
          _buildModeSelector(bill),
          if (bill.mode == PaymentMode.both) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _buildTextField(controller: bill.cashController, label: 'Cash', icon: Icons.money, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) {
                double c = double.tryParse(v) ?? 0;
                double u = double.tryParse(bill.upiController.text) ?? 0;
                bill.amountController.text = (c + u).toString();
                setState(() {});
              })),
              const SizedBox(width: 12),
              Expanded(child: _buildTextField(controller: bill.upiController, label: 'UPI', icon: Icons.qr_code_rounded, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) {
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
          _buildIndividualBillProofs(index, bill),
        ],
      ),
    );
  }

  void _showLinkDialog(int sourceIndex, dynamic pathData, bool isPaymentProof) {
    showDialog(
      context: context,
      builder: (context) {
        List<int> selectedIndices = [];
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
              title: Text('Link proof to other bills', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _bills.length,
                  itemBuilder: (context, i) {
                    if (i == sourceIndex) return const SizedBox.shrink();
                    // For payment proof, only show bills that aren't cash
                    if (isPaymentProof && _bills[i].mode == PaymentMode.cash) return const SizedBox.shrink();
                    
                    return CheckboxListTile(
                      title: Text('Bill #${i + 1} (${_bills[i].billNoController.text.isEmpty ? "No Bill #" : _bills[i].billNoController.text})', style: TextStyle(color: Colors.white70)),
                      value: selectedIndices.contains(i),
                      activeColor: Colors.cyanAccent,
                      checkColor: const Color(0xFF1A1A2E),
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) selectedIndices.add(i);
                          else selectedIndices.remove(i);
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text('CANCEL', style: TextStyle(color: Colors.white38))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: const Color(0xFF1A1A2E)),
                  onPressed: () {
                    setState(() {
                      for (var i in selectedIndices) {
                        if (isPaymentProof) _bills[i].paymentProof = pathData as String;
                        else _bills[i].billProofs = List.from(pathData as List<String>);
                      }
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Linked proof to ${selectedIndices.length} bills'), backgroundColor: Colors.cyanAccent));
                  },
                  child: Text('APPLY'),
                ),
              ],
            );
          }
        );
      },
    );
  }


  Widget _buildIndividualBillProofs(int index, BillEntry bill) {
    bool showBillProof = bill.status.toLowerCase() == 'completed';
    bool showPaymentProof = bill.mode != PaymentMode.cash;
    if (!showBillProof && !showPaymentProof) return const SizedBox.shrink();
    return Column(
      children: [
        const SizedBox(height: 24),
        _buildSectionTitle('PROOFS', Icons.camera_alt_rounded),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          if (showBillProof) Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProofButton(
                label: 'Bill Photo (${bill.billProofs.length})', 
                file: bill.billProofs.isNotEmpty ? File(bill.billProofs.last) : null, 
                onTap: () => _pickImage((path) => setState(() => bill.billProofs.add(path))),
                onLink: bill.billProofs.isEmpty ? null : () => _showLinkDialog(index, bill.billProofs, false),
              ),
              if (bill.billProofs.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: bill.billProofs.length + 1,
                    itemBuilder: (context, idx) {
                      if (idx == bill.billProofs.length) {
                        return GestureDetector(
                          onTap: () => _pickImage((path) => setState(() => bill.billProofs.add(path))),
                          child: Container(
                            width: 60,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24, style: BorderStyle.solid),
                            ),
                            child: const Center(
                              child: Icon(Icons.add, color: Colors.cyanAccent, size: 24),
                            ),
                          ),
                        );
                      }
                      final proof = bill.billProofs[idx];
                      final isLocal = !proof.startsWith('http') && !proof.startsWith('/uploads');
                      return Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                              image: DecorationImage(
                                image: isLocal ? FileImage(File(proof)) as ImageProvider : NetworkImage(ApiService.getImageUrl(proof)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2, right: 10,
                            child: GestureDetector(
                              onTap: () => setState(() => bill.billProofs.removeAt(idx)),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.close, size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          )),
          if (showBillProof && showPaymentProof) const SizedBox(width: 12),
          if (showPaymentProof) Expanded(child: _buildProofButton(
            label: 'Payment Proof', 
            file: (bill.paymentProof != null && bill.paymentProof!.isNotEmpty) ? File(bill.paymentProof!) : null, 
            onTap: () => _pickImage((path) => setState(() => bill.paymentProof = path)),
            onLink: (bill.paymentProof == null || bill.paymentProof!.isEmpty) ? null : () => _showLinkDialog(index, bill.paymentProof!, true),
          )),
        ]),
      ],
    );
  }


  Widget _buildModeSelector(BillEntry bill) => Container(
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
    child: Row(children: PaymentMode.values.map((mode) {
      bool isSelected = bill.mode == mode;
      return Expanded(child: GestureDetector(
        onTap: () => setState(() {
          bill.mode = mode;
          if (mode == PaymentMode.cash) {
            bill.paymentProof = null;
          }
        }),
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
        bool isSelected = bill.status.toLowerCase() == s.toLowerCase();
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              bill.status = s;
              if (s == 'Partial') {
                bill.billProofs.clear();
              }
            }),
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
    bool isRequired = true,
    bool isReadOnly = false,
  }) {
    return TextFormField(
      key: ValueKey(label),
      controller: controller,
      readOnly: isReadOnly,
      keyboardType: keyboardType,
      textInputAction: label == 'Shop Name' ? TextInputAction.next : TextInputAction.done,
      onChanged: (v) {
        if (onChanged != null) onChanged(v);
        setState(() {}); // For suffix icon visibility
      },
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: Colors.cyanAccent),
        suffixIcon: controller.text.isNotEmpty && !isReadOnly
          ? IconButton(
              icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 20),
              onPressed: () {
                controller.clear();
                if (onChanged != null) onChanged("");
                setState(() {});
              },
            )
          : null,
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
      validator: isRequired ? (value) => value!.isEmpty ? 'Field required' : null : null,
    );
  }

  Widget _buildProofButton({required String label, File? file, required VoidCallback onTap, VoidCallback? onLink}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1), style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: file != null ? Colors.green.withOpacity(0.1) : Colors.cyanAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    file != null ? Icons.check_circle_rounded : Icons.add_a_photo_rounded,
                    color: file != null ? Colors.greenAccent : Colors.cyanAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(
                        file != null ? 'Selected' : 'Tap to upload',
                        style: TextStyle(color: file != null ? Colors.greenAccent : Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (file != null && onLink != null) ...[
              const SizedBox(height: 8),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 4),
              InkWell(
                onTap: onLink,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.link_rounded, color: Colors.cyanAccent, size: 14),
                      const SizedBox(width: 4),
                      Text('LINK TO OTHERS', style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
            ]
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
