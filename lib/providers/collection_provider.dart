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
    final unsynced = await DatabaseHelper.instance.getUnsyncedCollections();
    if (unsynced.isEmpty) return;
    
    print('Sync: Found ${unsynced.length} pending collections. Starting background sync...');
    for (var coll in unsynced) {
      await _syncOne(coll, token);
    }
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

  Future<void> _syncOne(Collection collection, String token, [Map<String, String>? sessionFiles]) async {
    print('Sync: Uploading collection ${collection.id} (Bill: ${collection.billNo})...');
    
    // 1. Apply any already-uploaded URLs from this session
    Collection toSync = collection;
    if (sessionFiles != null) {
      String? bp = collection.billProof;
      String? pp = collection.paymentProof;
      bool mod = false;
      if (bp != null && sessionFiles.containsKey(bp)) { 
        print('Sync: Reusing URL for Bill Proof: $bp');
        bp = sessionFiles[bp]; 
        mod = true; 
      }
      if (pp != null && sessionFiles.containsKey(pp)) { 
        print('Sync: Reusing URL for Payment Proof: $pp');
        pp = sessionFiles[pp]; 
        mod = true; 
      }
      if (mod) {
        toSync = Collection.fromMap({...collection.toMap(), 'bill_proof': bp, 'payment_proof': pp});
      }
    }

    final response = await ApiService.syncCollection(toSync, token);
    if (response != null) {
      print('Sync: Successfully uploaded ${collection.id}');
      
      // 2. Record the server URLs in sessionFiles to avoid re-uploading same file
      if (sessionFiles != null) {
        // Check both underscore and camelCase to be safe
        String? serverBillUrl = response['bill_proof'] ?? response['billProof'];
        String? serverPaymentUrl = response['payment_proof'] ?? response['paymentProof'];

        if (collection.billProof != null && serverBillUrl != null) {
          print('Sync: Cached Bill Proof URL: $serverBillUrl');
          sessionFiles[collection.billProof!] = serverBillUrl;
        }
        if (collection.paymentProof != null && serverPaymentUrl != null) {
          print('Sync: Cached Payment Proof URL: $serverPaymentUrl');
          sessionFiles[collection.paymentProof!] = serverPaymentUrl;
        }
      }

      await DatabaseHelper.instance.markAsSynced(collection.id);
      final index = _collections.indexWhere((c) => c.id == collection.id);
      if (index != -1) {
        final updatedMap = _collections[index].toMap();
        updatedMap['is_synced'] = 1;
        _collections[index] = Collection.fromMap(updatedMap);
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

    print('Sync: Starting batch sync for ${unsynced.length} records...');
    final Map<String, String> sessionFiles = {};
    for (var coll in unsynced) {
      await _syncOne(coll, token, sessionFiles);
    }
  }
}
