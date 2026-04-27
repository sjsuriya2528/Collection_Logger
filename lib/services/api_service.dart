import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/collection.dart';

class ApiService {
  // Use this for local testing (Ensure phone and PC are on same Wi-Fi)
  //static const String baseUrl = 'http://172.19.75.227:3000';
  
  // Use this for production
  static const String baseUrl = 'https://collection.acmagencies.store';

  static String getImageUrl(String path) {
    if (path.startsWith('http')) return path;
    final serverBase = baseUrl.replaceAll('/api', '');
    return '$serverBase$path';
  }

  static Future<void> requestOTP(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/forgot-password'),
      body: jsonEncode({'email': email}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to send OTP');
    }
  }

  static Future<void> verifyOTP(String email, String otp) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/verify-otp'),
      body: jsonEncode({'email': email, 'otp': otp}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Invalid OTP');
    }
  }

  static Future<void> resetPassword(String email, String otp, String newPassword) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/reset-password'),
      body: jsonEncode({'email': email, 'otp': otp, 'newPassword': newPassword}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Reset failed');
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
    if (collection.billProof != null) {
      if (collection.billProof!.startsWith('http') || collection.billProof!.startsWith('/uploads')) {
        request.fields['bill_proof'] = collection.billProof!;
      } else {
        request.files.add(await http.MultipartFile.fromPath('billProof', collection.billProof!));
      }
    }
    
    if (collection.paymentProof != null) {
      if (collection.paymentProof!.startsWith('http') || collection.paymentProof!.startsWith('/uploads')) {
        request.fields['payment_proof'] = collection.paymentProof!;
      } else {
        request.files.add(await http.MultipartFile.fromPath('paymentProof', collection.paymentProof!));
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body);
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
      throw Exception(jsonDecode(response.body)['message'] ?? 'Failed to send OTP');
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
      throw Exception(jsonDecode(response.body)['message'] ?? 'Change failed');
    }
  }

  static Future<Map<String, dynamic>> signup(String name, String email, String password, String role, {String? adminSecretCode}) async {
    try {
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
        Uri.parse('$baseUrl/api/auth/login'),
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


  static Future<List<dynamic>> getEmployees(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/employees'),
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
        Uri.parse('$baseUrl/api/collections/mine'),
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
        Uri.parse('$baseUrl/api/collections/employee/$employeeId'),
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

  static Future<Map<String, dynamic>?> updateCollection(
    String collectionId, 
    Map<String, String> fields, 
    String token,
    {String? billProofPath, String? paymentProofPath}
  ) async {
    try {
      final request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/api/collections/$collectionId'));
      request.headers['Authorization'] = 'Bearer $token';
      
      // Add text fields
      request.fields.addAll(fields);
      
      // Add files if provided, or preserve existing URLs
      if (billProofPath != null) {
        if (billProofPath.startsWith('http') || billProofPath.startsWith('/uploads')) {
          request.fields['bill_proof'] = billProofPath;
        } else {
          request.files.add(await http.MultipartFile.fromPath('bill_proof', billProofPath));
        }
      }
      
      if (paymentProofPath != null) {
        if (paymentProofPath.startsWith('http') || paymentProofPath.startsWith('/uploads')) {
          request.fields['payment_proof'] = paymentProofPath;
        } else {
          request.files.add(await http.MultipartFile.fromPath('payment_proof', paymentProofPath));
        }
      }
      
      final response = await request.send();
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        return jsonDecode(respStr);
      }
      return null;
    } catch (e) {
      print('Update Collection Error: $e');
      return null;
    }
  }

  static Future<bool> deleteCollection(String collectionId, String token) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/collections/$collectionId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Delete Collection Error: $e');
      return false;
    }
  }
  static Future<Map<String, dynamic>> getAdminDashboard(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/dashboard'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load admin dashboard');
    }
  }
}
