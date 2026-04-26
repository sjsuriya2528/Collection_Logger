import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/collection_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/employee/employee_dashboard.dart';
import 'screens/admin/admin_dashboard.dart';
import 'services/sync_service.dart';
import 'services/notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Only initialize Firebase on Mobile (Android/iOS)
  // Firebase FCM is not supported on Windows Desktop natively via this plugin
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await Firebase.initializeApp();
      await NotificationService.initialize();
    } catch (e) {
      print('Firebase initialization failed: $e');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CollectionProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'A C M',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        canvasColor: const Color(0xFF1A1A2E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyanAccent,
          brightness: Brightness.dark,
          surface: const Color(0xFF16213E),
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _syncStarted = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final collProvider = Provider.of<CollectionProvider>(context, listen: false);

    if (authProvider.isAuthenticated) {
      if (!_syncStarted) {
        SyncService.initialize(collProvider, authProvider);
        _syncStarted = true;
      }
      
      if (authProvider.user!.isAdmin) {
        if (Platform.isAndroid || Platform.isIOS) {
          NotificationService.registerDeviceToken();
        }
        return const AdminDashboard();
      } else {
        return const EmployeeDashboard();
      }
    }

    _syncStarted = false;
    return const LoginScreen();
  }
}
