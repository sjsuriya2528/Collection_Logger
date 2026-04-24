import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/collection.dart';

class ApiService {
  // Replace '192.168.1.XX' with your computer's actual local IP address
  static const String baseUrl = 'https://collectionlogger-production.up.railway.app/api'; 

  static Future<void> requestOTP(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      body: jsonEncode({'email': email}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to send OTP');
    }
  }

  static Future<void> verifyOTP(String email, String otp) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/verify-otp'),
      body: jsonEncode({'email': email, 'otp': otp}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Invalid OTP');
    }
  }

  static Future<void> resetPassword(String email, String otp, String newPassword) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      body: jsonEncode({'email': email, 'otp': otp, 'newPassword': newPassword}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Reset failed');
    }
  }

  static Future<void> addCollection(Collection collection, String token) async {
    final uri = Uri.parse('$baseUrl/collections');
    var request = http.MultipartRequest('POST', uri);
    
    request.headers['Authorization'] = 'Bearer $token';
    
    // Add text fields
    request.fields['id'] = collection.id;
    request.fields['bill_no'] = collection.billNo;
    request.fields['shop_name'] = collection.shopName;
    request.fields['amount'] = collection.amount.toString();
    request.fields['payment_mode'] = collection.paymentMode.name;
    request.fields['date'] = collection.date.toIso8601String();
    request.fields['status'] = collection.status;

    // Add files if they exist (local paths)
    if (collection.billProof != null && !collection.billProof!.startsWith('http')) {
      request.files.add(await http.MultipartFile.fromPath('billProof', collection.billProof!));
    }
    if (collection.paymentProof != null && !collection.paymentProof!.startsWith('http')) {
      request.files.add(await http.MultipartFile.fromPath('paymentProof', collection.paymentProof!));
    }

    final response = await request.send();
    if (response.statusCode != 201 && response.statusCode != 200) {
      final respStr = await response.stream.bytesToString();
      throw Exception('Failed to sync: $respStr');
    }
  }

  static Future<void> requestChangeOTP(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/request-change-otp'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to send OTP');
    }
  }

  static Future<void> changePassword(String token, String otp, String newPassword) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/change-password'),
      body: jsonEncode({'otp': otp, 'newPassword': newPassword}),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Change failed');
    }
  }

  static Future<Map<String, dynamic>> signup(String name, String email, String password, String role) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/signup'),
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'role': role
        }),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(jsonDecode(response.body)['message'] ?? 'Signup failed');
      }
    } catch (e) {
      print('Signup Error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        body: jsonEncode({'email': email, 'password': password}),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Login Error: ${response.statusCode} - ${response.body}');
        throw Exception('Login failed: ${response.body}');
      }
    } catch (e) {
      print('Network Error: $e');
      rethrow;
    }
  }

  static Future<bool> syncCollection(Collection collection, String token) async {
    try {
      await addCollection(collection, token);
      return true;
    } catch (e) {
      print('Sync Error: $e');
      return false;
    }
  }

  static Future<List<dynamic>> getEmployees(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/employees'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return [];
  }

  static Future<List<dynamic>> getMyCollections(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/collections/mine'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch my collections');
      }
    } catch (e) {
      print('Fetch Error: $e');
      throw e;
    }
  }

  static Future<List<dynamic>> getEmployeeCollections(String employeeId, String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/collections/employee/$employeeId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load employee history');
      }
    } catch (e) {
      print('Get Employee History Error: $e');
      rethrow;
    }
  }

  static Future<bool> updateCollection(String collectionId, Map<String, dynamic> updates, String token) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/collections/$collectionId'),
        body: jsonEncode(updates),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update Collection Error: $e');
      return false;
    }
  static Future<bool> deleteCollection(String collectionId, String token) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/collections/$collectionId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Delete Collection Error: $e');
      return false;
    }
  }
}
