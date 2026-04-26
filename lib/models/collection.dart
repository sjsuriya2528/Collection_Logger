import 'package:uuid/uuid.dart';

enum PaymentMode { cash, upi, cheque, both }

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
  final double cashAmount;
  final double upiAmount;
  final String? groupId;

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
    this.cashAmount = 0,
    this.upiAmount = 0,
    this.groupId,
  }) : id = id ?? const Uuid().v4();

  factory Collection.fromMap(Map<String, dynamic> map) {
    DateTime parsedDate = DateTime.parse(map['date'].toString()).toLocal();

    return Collection(
      id: map['id'],
      employeeId: map['employee_id']?.toString() ?? '',
      billNo: (map['bill_no'] ?? map['billNo'] ?? '').toString(),
      shopName: map['shop_name'] ?? map['shopName'] ?? '',
      amount: double.tryParse((map['amount'] ?? 0).toString()) ?? 0,
      paymentMode: PaymentMode.values.firstWhere(
        (e) => e.name.toLowerCase() == (map['payment_mode'] ?? map['paymentMode']).toString().toLowerCase(),
        orElse: () => PaymentMode.cash,
      ),
      date: parsedDate,
      isSynced: map['is_synced'] == 1 || map['is_synced'] == true,
      status: map['status'] ?? 'partial',
      billProof: map['bill_proof'] ?? map['billProof'],
      paymentProof: map['payment_proof'] ?? map['paymentProof'],
      cashAmount: double.tryParse((map['cash_amount'] ?? map['cashAmount'] ?? 0).toString()) ?? 0,
      upiAmount: double.tryParse((map['upi_amount'] ?? map['upiAmount'] ?? 0).toString()) ?? 0,
      groupId: map['group_id'] ?? map['groupId'],
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
      'cash_amount': cashAmount,
      'upi_amount': upiAmount,
      'group_id': groupId,
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
      'group_id': groupId,
    };
  }
}
