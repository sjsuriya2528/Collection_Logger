import 'package:uuid/uuid.dart';

enum PaymentMode { cash, upi, cheque }

class Collection {
  final String id;
  final String employeeId;
  final String billNo;
  final String shopName;
  final double amount;
  final PaymentMode paymentMode;
  final DateTime date;
  final bool isSynced;
  final String status; // 'partial' or 'completed'
  final String? billProof;
  final String? paymentProof;

  Collection({
    String? id,
    required this.employeeId,
    required this.billNo,
    required this.shopName,
    required this.amount,
    required this.paymentMode,
    required this.date,
    this.isSynced = false,
    this.status = 'partial',
    this.billProof,
    this.paymentProof,
  }) : id = id ?? const Uuid().v4();

  factory Collection.fromMap(Map<String, dynamic> map) {
    return Collection(
      id: map['id'],
      employeeId: map['employee_id'].toString(),
      billNo: map['bill_no'].toString(),
      shopName: map['shop_name'],
      amount: double.parse(map['amount'].toString()),
      paymentMode: PaymentMode.values.firstWhere(
        (e) => e.name.toLowerCase() == map['payment_mode'].toString().toLowerCase(),
        orElse: () => PaymentMode.cash,
      ),
      date: DateTime.parse(map['date']),
      isSynced: map['is_synced'] == 1 || map['is_synced'] == true,
      status: map['status'] ?? 'partial',
      billProof: map['bill_proof'],
      paymentProof: map['payment_proof'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employee_id': employeeId,
      'bill_no': billNo,
      'shop_name': shopName,
      'amount': amount,
      'payment_mode': paymentMode.name,
      'date': date.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
      'status': status,
      'bill_proof': billProof,
      'payment_proof': paymentProof,
    };
  }

  Map<String, dynamic> toJson() {
    // API might expect different keys or formats
    return {
      'id': id,
      'employee_id': employeeId,
      'bill_no': billNo,
      'shop_name': shopName,
      'amount': amount,
      'payment_mode': paymentMode.name,
      'date': date.toIso8601String(),
    };
  }
}
