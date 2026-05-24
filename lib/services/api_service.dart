import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/collection.dart';

class ApiService {
  // Use this for local testing (Ensure phone and PC are on same Wi-Fi)
  // static const String baseUrl = 'http://10.200.134.227:3000';
  
  // Use this for production
  static const String baseUrl = 'https://collection.acmagencies.store';

  static String getImageUrl(String path) {
    if (path.startsWith('http')) return path;
    final serverBase = baseUrl.replaceAll('/api', '');
    return '$serverBase$path';
  }

  // Optimized background JSON parsing
  static Future<dynamic> _parseJson(String body) async {
    return compute(jsonDecode, body);
  }

  static Future<void> requestOTP(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/forgot-password'),
      body: jsonEncode({'email': email}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception((await _parseJson(response.body))['message'] ?? 'Failed to send OTP');
    }
  }

  static Future<void> verifyOTP(String email, String otp) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/verify-otp'),
      body: jsonEncode({'email': email, 'otp': otp}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception((await _parseJson(response.body))['message'] ?? 'Invalid OTP');
    }
  }

  static Future<void> resetPassword(String email, String otp, String newPassword) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/reset-password'),
      body: jsonEncode({'email': email, 'otp': otp, 'newPassword': newPassword}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception((await _parseJson(response.body))['message'] ?? 'Reset failed');
    }
  }

  static Future<Map<String, dynamic>?> syncCollection(Collection collection, String token) async {
    final uri = Uri.parse('$baseUrl/api/collections');
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
    request.fields['cash_amount'] = collection.cashAmount.toString();
    request.fields['upi_amount'] = collection.upiAmount.toString();
    if (collection.groupId != null) {
      request.fields['group_id'] = collection.groupId!;
    }

    // Add files if they exist (local paths) or add as string if already a URL
    if (collection.billProof != null && collection.billProof!.trim().isNotEmpty) {
      List<String> urls = [];
      for (final proof in collection.billProofsList) {
        if (proof.startsWith('http') || proof.startsWith('/uploads')) {
          urls.add(proof);
        } else {
          request.files.add(await http.MultipartFile.fromPath('billProof', proof));
        }
      }
      if (urls.isNotEmpty) request.fields['bill_proof'] = urls.join(',');
    } else {
      request.fields['bill_proof'] = '';
    }
    
    if (collection.paymentProof != null && collection.paymentProof!.trim().isNotEmpty) {
      if (collection.paymentProof!.startsWith('http') || collection.paymentProof!.startsWith('/uploads')) {
        request.fields['payment_proof'] = collection.paymentProof!;
      } else {
        request.files.add(await http.MultipartFile.fromPath('payment_proof', collection.paymentProof!));
      }
    } else {
      request.fields['payment_proof'] = '';
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 201 || response.statusCode == 200) {
      return await _parseJson(response.body);
    } else {
      print('Sync Error: ${response.body}');
      return null;
    }
  }

  static Future<void> requestChangeOTP(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/request-change-otp'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception((await _parseJson(response.body))['message'] ?? 'Failed to send OTP');
    }
  }

  static Future<void> changePassword(String token, String otp, String newPassword) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/change-password'),
      body: jsonEncode({'otp': otp, 'newPassword': newPassword}),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception((await _parseJson(response.body))['message'] ?? 'Change failed');
    }
  }

  static Future<String?> uploadFile(String filePath, String token, String type) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'));
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['type'] = type; // 'bill' or 'payment'
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return (await _parseJson(response.body))['url'];
      }
      return null;
    } catch (e) {
      print('Upload Error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> signup(String name, String email, String password, String role, {String? adminSecretCode}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/signup'),
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'role': role,
        'admin_secret_code': adminSecretCode,
      }),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return await _parseJson(response.body);
    } else {
      throw Exception((await _parseJson(response.body))['message'] ?? 'Signup failed');
    }
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      body: jsonEncode({'email': email, 'password': password}),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return await _parseJson(response.body);
    } else {
      throw Exception('Login failed: ${response.body}');
    }
  }

  static Future<List<dynamic>> getEmployees(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/employees'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return await _parseJson(response.body);
    }
    return [];
  }

  static Future<List<dynamic>> getMyCollections(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/collections/mine'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return await _parseJson(response.body);
    } else {
      throw Exception('Failed to fetch my collections');
    }
  }

  static Future<void> logout(String token, {String? fcmToken}) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/auth/logout'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'token': fcmToken}),
      );
    } catch (e) {
      print('Logout API Error: $e');
    }
  }

  static Future<List<dynamic>> getEmployeeCollections(String employeeId, String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/collections/employee/$employeeId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return await _parseJson(response.body);
    } else {
      throw Exception('Failed to load employee history');
    }
  }

  static Future<Map<String, dynamic>?> updateCollection(
    String collectionId, 
    Map<String, String> fields, 
    String token,
    {String? billProofPath, String? paymentProofPath}
  ) async {
    final request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/api/collections/$collectionId'));
    request.headers['Authorization'] = 'Bearer $token';
    request.fields.addAll(fields);
    
    if (billProofPath != null) {
      List<String> urls = [];
      if (billProofPath.trim().isNotEmpty) {
        for (final proof in billProofPath.split(',').where((e) => e.trim().isNotEmpty)) {
          if (proof.startsWith('http') || proof.startsWith('/uploads')) {
            urls.add(proof);
          } else {
            request.files.add(await http.MultipartFile.fromPath('bill_proof', proof));
          }
        }
      }
      request.fields['bill_proof'] = urls.join(',');
    }
    
    if (paymentProofPath != null) {
      if (paymentProofPath.trim().isEmpty) {
        request.fields['payment_proof'] = '';
      } else if (paymentProofPath.startsWith('http') || paymentProofPath.startsWith('/uploads')) {
        request.fields['payment_proof'] = paymentProofPath;
      } else {
        request.files.add(await http.MultipartFile.fromPath('payment_proof', paymentProofPath));
      }
    }
    
    final response = await request.send();
    if (response.statusCode == 200) {
      final respStr = await response.stream.bytesToString();
      return await _parseJson(respStr);
    }
    return null;
  }

  static Future<bool> deleteCollection(String collectionId, String token) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/collections/$collectionId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return response.statusCode == 200;
  }

  static Future<Map<String, dynamic>> getAdminDashboard(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/dashboard'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return await _parseJson(response.body);
    } else {
      throw Exception('Failed to load admin dashboard');
    }
  }

  static Future<List<dynamic>> getAllCollections(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/collections'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return await _parseJson(response.body);
    } else {
      throw Exception('Failed to load all collections');
    }
  }
}

