import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/collection_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/employee/employee_dashboard.dart';
import 'screens/admin/admin_dashboard.dart';
import 'services/sync_service.dart';
import 'services/notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:local_notifier/local_notifier.dart';
import 'database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

import 'package:workmanager/workmanager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'models/user.dart';
import 'services/api_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty || results.first == ConnectivityResult.none) {
        return Future.value(false); 
      }

      if (Platform.isWindows) {
        databaseFactory = databaseFactoryFfi;
        sqfliteFfiInit();
      }

      final unsynced = await DatabaseHelper.instance.getUnsyncedCollections();
      if (unsynced.isEmpty) {
        return Future.value(true);
      }

      const storage = FlutterSecureStorage();
      final userDataStr = await storage.read(key: 'user');
      if (userDataStr == null) return Future.value(false);
      
      final user = User.fromJson(jsonDecode(userDataStr));
      if (user.token == null) return Future.value(false);

      final Map<String, Future<String?>> uploadRegistry = {};
      
      for (var collection in unsynced) {
        String? bp = await _uploadMultiple(collection.billProof, 'bill', user.token!, uploadRegistry);
        String? pp = await _uploadMultiple(collection.paymentProof, 'payment', user.token!, uploadRegistry);

        final toSync = collection.copyWith(billProof: bp, paymentProof: pp);
        final response = await ApiService.syncCollection(toSync, user.token!);
        
        if (response != null) {
          await DatabaseHelper.instance.markAsSynced(
            collection.id, 
            billProof: bp, 
            paymentProof: pp
          );
          
          final delayHours = DateTime.now().difference(collection.date).inHours;
          if (delayHours >= 2) {
            await ApiService.sendAdminAlert(
              '⚠️ Delayed Sync Alert',
              'Employee \${user.name} just synced a collection of ₹\${collection.amount} for \${collection.shopName}. This was originally recorded offline \$delayHours hours ago.',
              user.token!
            );
          }
        }
      }
      return Future.value(true);
    } catch (e) {
      print('Background Sync Error: \$e');
      try {
        const storage = FlutterSecureStorage();
        final userDataStr = await storage.read(key: 'user');
        if (userDataStr != null) {
          final user = User.fromJson(jsonDecode(userDataStr));
          if (user.token != null) {
            final errorMsg = e.toString();
            final safeError = errorMsg.length > 50 ? errorMsg.substring(0, 50) + '...' : errorMsg;
            await ApiService.sendAdminAlert(
              '🛑 App Issue Detected',
              'Background sync failed for employee \${user.name}. Error: \$safeError',
              user.token!
            );
          }
        }
      } catch (_) {}
      return Future.value(false);
    }
  });
}

Future<String?> _uploadMultiple(
  String? pathsStr, 
  String type, 
  String token, 
  Map<String, Future<String?>> uploadRegistry
) async {
  if (pathsStr == null || pathsStr.isEmpty) return pathsStr;
  final paths = pathsStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  final uploadedUrls = <String>[];
  
  for (var path in paths) {
    if (path.startsWith('http') || path.startsWith('/uploads')) {
      uploadedUrls.add(path);
    } else {
      if (!uploadRegistry.containsKey(path)) {
        uploadRegistry[path] = ApiService.uploadFile(path, token, type);
      }
      final url = await uploadRegistry[path];
      if (url != null) uploadedUrls.add(url);
    }
  }
  return uploadedUrls.isEmpty ? null : uploadedUrls.join(',');
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    databaseFactory = databaseFactoryFfi;
    sqfliteFfiInit();
    
    await localNotifier.setup(
      appName: 'ACM Collection Logger',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
  }

  // Only initialize Firebase and Workmanager on Mobile (Android/iOS)
  // Firebase FCM is not supported on Windows Desktop natively via this plugin
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await Firebase.initializeApp();
      await NotificationService.initialize();
      
      Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
      Workmanager().registerPeriodicTask(
        "sync-task-id",
        "syncPendingCollections",
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    } catch (e) {
      print('Initialization failed: $e');
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          navigatorKey.currentState?.maybePop();
        },
      },
      child: MaterialApp(
        navigatorKey: navigatorKey,
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
      ),
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
        return const AdminDashboard();
      } else {
        return const EmployeeDashboard();
      }
    }

    _syncStarted = false;
    return const LoginScreen();
  }
}
