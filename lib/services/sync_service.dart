import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/collection_provider.dart';
import '../providers/auth_provider.dart';

class SyncService {
  static StreamSubscription<List<ConnectivityResult>>? _subscription;

  static void initialize(CollectionProvider collProvider, AuthProvider authProvider) {
    _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none && authProvider.isAuthenticated) {
        collProvider.syncAllPending(authProvider.user!.token!);
      }
    });

    // Also run periodic sync every 15 minutes if app is open
    Timer.periodic(const Duration(minutes: 15), (timer) {
      if (authProvider.isAuthenticated) {
        collProvider.syncAllPending(authProvider.user!.token!);
      }
    });
  }

  static void dispose() {
    _subscription?.cancel();
  }
}
