class User {
  final String id;
  final String name;
  final String role;
  final String? token;

  User({
    required this.id,
    required this.name,
    required this.role,
    this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['user_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      role: json['role'] ?? 'employee',
      token: json['token'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'token': token,
    };
  }

  bool get isAdmin => role.toLowerCase() == 'admin';
}
