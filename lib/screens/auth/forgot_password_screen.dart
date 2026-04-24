import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  
  int _step = 1; // 1: Email, 2: OTP, 3: New Password
  bool _isLoading = false;

  Future<void> _requestOTP() async {
    setState(() => _isLoading = true);
    try {
      await ApiService.requestOTP(_emailController.text.trim());
      setState(() => _step = 2);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP sent to your email')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOTP() async {
    setState(() => _isLoading = true);
    try {
      await ApiService.verifyOTP(_emailController.text.trim(), _otpController.text.trim());
      setState(() => _step = 3);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    setState(() => _isLoading = true);
    try {
      await ApiService.resetPassword(
        _emailController.text.trim(),
        _otpController.text.trim(),
        _passwordController.text.trim(),
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset successfully!')));
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _step == 1 ? 'Forgot Password?' : (_step == 2 ? 'Verify OTP' : 'New Password'),
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _step == 1 
                ? 'Enter your email to receive a 6-digit reset code.' 
                : (_step == 2 ? 'Enter the code sent to ${_emailController.text}' : 'Enter your new secure password.'),
              style: const TextStyle(color: Colors.white60, fontSize: 16),
            ),
            const SizedBox(height: 48),
            if (_step == 1) _buildEmailStep(),
            if (_step == 2) _buildOTPStep(),
            if (_step == 3) _buildPasswordStep(),
            const SizedBox(height: 100), // Space for keyboard
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : (_step == 1 ? _requestOTP : (_step == 2 ? _verifyOTP : _resetPassword)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: const Color(0xFF1A1A2E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator() 
                  : Text(_step == 1 ? 'SEND CODE' : (_step == 2 ? 'VERIFY CODE' : 'RESET PASSWORD'), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return _buildTextField(_emailController, 'Email Address', Icons.email_outlined, autofocus: true);
  }

  Widget _buildOTPStep() {
    return _buildTextField(_otpController, '6-Digit OTP', Icons.lock_clock_outlined, isNumber: true, autofocus: true);
  }

  Widget _buildPasswordStep() {
    return _buildTextField(_passwordController, 'New Password', Icons.lock_outline_rounded, isPassword: true, autofocus: true);
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPassword = false, bool isNumber = false, bool autofocus = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      autofocus: autofocus,
      keyboardType: isNumber ? TextInputType.number : (isPassword ? TextInputType.visiblePassword : TextInputType.emailAddress),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: Colors.cyanAccent),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.cyanAccent)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
      ),
    );
  }
}
