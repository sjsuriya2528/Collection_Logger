import 'package:flutter/material.dart';
import '../models/collection.dart';
import '../database/database_helper.dart';
import '../services/api_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class CollectionProvider with ChangeNotifier {
  List<Collection> _collections = [];
  bool _isLoading = false;

  List<Collection> get collections => _collections;
  bool get isLoading => _isLoading;

  double get todayTotal {
    final today = DateTime.now();
    return _collections
        .where((c) => 
            c.date.year == today.year && 
            c.date.month == today.month && 
            c.date.day == today.day)
        .fold(0.0, (sum, item) => sum + item.amount);
  }

  Map<String, double> get modeBreakdown {
    final today = DateTime.now();
    final todayColls = _collections.where((c) => 
            c.date.year == today.year && 
            c.date.month == today.month && 
            c.date.day == today.day);
    
    return {
      'Cash': todayColls.fold(0.0, (s, c) => s + (c.paymentMode == PaymentMode.cash ? c.amount : (c.paymentMode == PaymentMode.both ? c.cashAmount : 0))),
      'UPI': todayColls.fold(0.0, (s, c) => s + (c.paymentMode == PaymentMode.upi ? c.amount : (c.paymentMode == PaymentMode.both ? c.upiAmount : 0))),
      'Cheque': todayColls.where((c) => c.paymentMode == PaymentMode.cheque).fold(0.0, (s, i) => s + i.amount),
    };
  }

  Future<void> fetchCollections(String employeeId, {String? token}) async {
    _isLoading = true;
    notifyListeners();
    
    // 1. Load from local DB first for speed
    _collections = await DatabaseHelper.instance.getEmployeeCollections(employeeId);
    _isLoading = false;
    notifyListeners();

    // 2. Try to sync any pending collections
    if (token != null) {
      await syncPendingCollections(token);
      // 3. Pull latest from server (updates Admin edits)
      await pullFromServer(token, employeeId);
    }
  }

  Future<void> syncPendingCollections(String token) async {
    // Consolidation: Use the new robust parallel sync method
    await syncAllPending(token);
  }

  Future<void> pullFromServer(String token, String employeeId) async {
    try {
      final serverData = await ApiService.getMyCollections(token);
      final List<String> serverIds = serverData.map((d) => d['id'].toString()).toList();
      
      // 1. Get all local synced records
      final localCollections = await DatabaseHelper.instance.getEmployeeCollections(employeeId);
      
      // 2. Identify records that are local but NOT on server (and were already synced)
      for (var local in localCollections) {
        if (local.isSynced && !serverIds.contains(local.id)) {
          print('Cleanup: Record ${local.id} not found on server. Deleting locally...');
          await DatabaseHelper.instance.deleteCollection(local.id);
        }
      }

      // 3. Upsert server records into local DB
      for (var data in serverData) {
        final coll = Collection.fromMap({
          ...data,
          'is_synced': 1 
        });
        await DatabaseHelper.instance.insertCollection(coll);
      }
      
      // 4. Final UI update
      _collections = await DatabaseHelper.instance.getEmployeeCollections(employeeId);
      notifyListeners();
    } catch (e) {
      print('Pull Sync Error: $e');
    }
  }

  Future<void> addCollection(Collection collection, String? token, {bool syncImmediately = true}) async {
    await DatabaseHelper.instance.insertCollection(collection);
    _collections.insert(0, collection);
    notifyListeners();
 
    if (token != null && syncImmediately) {
      syncAllPending(token);
    }
  }

  Future<void> updateCollection(Collection updated) async {
    await DatabaseHelper.instance.insertCollection(updated);
    final index = _collections.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      _collections[index] = updated;
      notifyListeners();
    }
  }

  Future<void> deleteCollection(String id) async {
    await DatabaseHelper.instance.deleteCollection(id);
    _collections.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  Future<void> _syncOne(
    Collection collection, 
    String token, 
    Map<String, Future<String?>> uploadRegistry
  ) async {
    print('Sync: Processing collection ${collection.id} (Bill: ${collection.billNo})...');
    
    // Helper to upload files only once if shared across multiple records in this batch
    Future<String?> upload(String? path, String type) async {
      if (path == null || path.startsWith('http') || path.startsWith('/uploads')) return path;
      
      // If this file path is already being uploaded, wait for THAT future.
      if (!uploadRegistry.containsKey(path)) {
        uploadRegistry[path] = ApiService.uploadFile(path, token, type);
      }
      return uploadRegistry[path];
    }

    // Wait for proof uploads to complete (reusing futures if paths are identical)
    String? bp = await upload(collection.billProof, 'bill');
    String? pp = await upload(collection.paymentProof, 'payment');


    // Create a version with server URLs
    Collection toSync = collection.copyWith(billProof: bp, paymentProof: pp);

    final response = await ApiService.syncCollection(toSync, token);
    if (response != null) {
      print('Sync: Successfully synced record ${collection.id}');
      
      // Persist the server URLs to the local database as well
      await DatabaseHelper.instance.markAsSynced(
        collection.id, 
        billProof: bp, 
        paymentProof: pp
      );

      final index = _collections.indexWhere((c) => c.id == collection.id);
      if (index != -1) {
        // Update the in-memory state with server URLs so "VIEW" buttons appear/work
        _collections[index] = _collections[index].copyWith(
          isSynced: true,
          billProof: bp,
          paymentProof: pp,
        );
        notifyListeners();
      }
    } else {
      print('Sync: Failed to upload ${collection.id}. Will retry later.');
    }
  }

  Future<void> syncAllPending(String token) async {
    final results = await Connectivity().checkConnectivity();
    if (results.isEmpty || results.first == ConnectivityResult.none) return;

    final unsynced = await DatabaseHelper.instance.getUnsyncedCollections();
    if (unsynced.isEmpty) return;

    print('Sync: Starting parallel batch sync for ${unsynced.length} records...');
    
    // The uploadRegistry stores the FUTURE of each unique file path's upload.
    // Multiple records sharing the same path will wait for the same Future.
    final Map<String, Future<String?>> uploadRegistry = {};
    
    await Future.wait(unsynced.map((coll) => _syncOne(coll, token, uploadRegistry)));
    print('Sync: Batch sync completed.');
  }

}
