class ShopBalance {
  final int? id;
  final String shopName;
  final double amount;
  final DateTime? updatedAt;

  ShopBalance({
    this.id,
    required this.shopName,
    required this.amount,
    this.updatedAt,
  });

  factory ShopBalance.fromJson(Map<String, dynamic> json) {
    return ShopBalance(
      id: json['id'],
      shopName: json['shop_name'] ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shop_name': shopName,
      'amount': amount,
    };
  }
}
