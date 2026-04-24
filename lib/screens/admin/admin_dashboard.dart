import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/collection_provider.dart';
import '../../services/api_service.dart';
import 'employee_history_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  List<dynamic> _employees = [];
  Map<String, dynamic> _summary = {'today_total': 0, 'breakdown': []};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchEmployees(),
      _fetchDashboardSummary(),
    ]);
    setState(() => _isLoading = false);
  }

  Future<void> _fetchEmployees() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final emps = await ApiService.getEmployees(auth.user!.token!);
    _employees = emps;
  }

  Future<void> _fetchDashboardSummary() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/admin/dashboard'),
        headers: {'Authorization': 'Bearer ${auth.user!.token}'},
      );
      if (response.statusCode == 200) {
        _summary = jsonDecode(response.body);
      }
    } catch (e) {
      print('Dashboard Summary Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo.png', height: 28),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                'A C M', 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_reset_rounded, color: Colors.white70),
            onPressed: () => _showChangePasswordSheet(context, auth.user!.token!),
            tooltip: 'Change Password',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _refreshAll,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
        : RefreshIndicator(
            onRefresh: _refreshAll,
            color: Colors.cyanAccent,
            backgroundColor: const Color(0xFF16213E),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(auth.user?.name ?? 'Admin'),
                  const SizedBox(height: 24),
                  _buildAdminSummary(),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Employees',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const Icon(Icons.leaderboard_rounded, color: Colors.cyanAccent, size: 20),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _employees.length,
                    itemBuilder: (context, index) {
                      final emp = _employees[index];
                      return _buildEmployeeCard(emp, index);
                    },
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
    );
  }
  Widget _buildHeader(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left section: Accent + Name
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 4,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(color: Colors.cyanAccent.withOpacity(0.5), blurRadius: 8),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hello, $name 👋',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        'Admin Console'.toUpperCase(),
                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withOpacity(0.05),
            child: const Icon(Icons.admin_panel_settings_outlined, color: Colors.white70, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminSummary() {
    final breakdown = _summary['breakdown'] as List? ?? [];
    
    double getModeTotal(String mode) {
      final item = breakdown.firstWhere((e) => e['payment_mode'] == mode.toLowerCase(), orElse: () => null);
      return item != null ? double.parse(item['total'].toString()) : 0.0;
    }

    return Column(
      children: [
        // Total Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            children: [
              const Text('TOTAL REVENUE TODAY', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '₹${_summary['today_total']}',
                  style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Mode Cards - Using a scrollable row with fixed aspect ratio cards
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _buildSmallModeCard('Cash', getModeTotal('Cash'), Icons.money_rounded, Colors.greenAccent),
              _buildSmallModeCard('UPI', getModeTotal('UPI'), Icons.qr_code_rounded, Colors.orangeAccent),
              _buildSmallModeCard('Cheque', getModeTotal('Cheque'), Icons.payments_rounded, Colors.lightBlueAccent),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSmallModeCard(String label, double amount, IconData icon, Color color) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '₹${amount.toInt()}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(dynamic emp, int index) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EmployeeHistoryScreen(employeeId: emp['user_id'].toString(), employeeName: emp['name']),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.cyanAccent.withOpacity(0.1),
              child: Text(emp['name'][0], style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                emp['name'], 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${emp['today_total'] ?? 0}',
                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const Text('TODAY', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(width: 12),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordSheet(BuildContext context, String token) {
    final otpController = TextEditingController();
    final newController = TextEditingController();
    int step = 1; // 1: Send OTP, 2: Verify & Reset
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24, right: 24, top: 24
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step == 1 ? 'Verify Identity' : 'New Password', 
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(step == 1 
                ? 'We will send a 6-digit OTP to your registered email.' 
                : 'Enter the OTP and your new secure password.',
                style: const TextStyle(color: Colors.white60, fontSize: 14)),
              const SizedBox(height: 24),
              if (step == 2) ...[
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: '6-Digit OTP',
                    labelStyle: const TextStyle(color: Colors.white60),
                    prefixIcon: const Icon(Icons.lock_clock_outlined, color: Colors.cyanAccent),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.cyanAccent)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    labelStyle: const TextStyle(color: Colors.white60),
                    prefixIcon: const Icon(Icons.vpn_key_outlined, color: Colors.cyanAccent),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.cyanAccent)),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    setSheetState(() => isLoading = true);
                    try {
                      if (step == 1) {
                        await ApiService.requestChangeOTP(token);
                        setSheetState(() {
                          step = 2;
                          isLoading = false;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP Sent! Check your email.')));
                      } else {
                        if (otpController.text.isEmpty || newController.text.isEmpty) return;
                        await ApiService.changePassword(token, otpController.text, newController.text);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated successfully!'), backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent));
                    } finally {
                      setSheetState(() => isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: const Color(0xFF1A1A2E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: isLoading 
                    ? const CircularProgressIndicator() 
                    : Text(step == 1 ? 'SEND OTP TO EMAIL' : 'UPDATE PASSWORD', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
