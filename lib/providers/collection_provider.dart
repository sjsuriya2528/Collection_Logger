import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/collection.dart';
import '../database/database_helper.dart';
import '../services/api_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class CollectionProvider with ChangeNotifier {
  List<Collection> _collections = [];
  bool _isLoading = false;

  List<Collection> get collections => _collections;
  bool get isLoading => _isLoading;

  double _todayTotal = 0;
  Map<String, double> _modeBreakdown = {
    'Cash': 0,
    'UPI': 0,
    'Cheque': 0,
  };
  Map<String, int> _shopFinCounts = {};
  Map<String, int> _collectionFinNumbers = {};

  double get todayTotal => _todayTotal;
  Map<String, double> get modeBreakdown => _modeBreakdown;
  Map<String, int> get shopFinCounts => _shopFinCounts;
  Map<String, int> get collectionFinNumbers => _collectionFinNumbers;

  Future<void> _updateCalculations() async {
    final result = await compute(_performCalculations, {
      'collections': _collections,
      'today': DateTime.now(),
    });

    _todayTotal = result.todayTotal;
    _modeBreakdown = result.modeBreakdown;
    _shopFinCounts = result.shopFinCounts;
    _collectionFinNumbers = result.collectionFinNumbers;
  }

  static CalculationResult _performCalculations(Map<String, dynamic> params) {
    final List<Collection> colls = params['collections'];
    final DateTime today = params['today'];
    
    double total = 0;
    double cash = 0;
    double upi = 0;
    double cheque = 0;
    final Map<String, int> finCounts = {};
    final Map<String, int> finNumbers = {};

    // Sort ascending by date to assign sequential FINs
    final sortedColls = List<Collection>.from(colls)..sort((a, b) => a.date.compareTo(b.date));

    for (var c in sortedColls) {
      if (c.date.year == today.year && 
          c.date.month == today.month && 
          c.date.day == today.day) {
        total += c.amount;
        if (c.paymentMode == PaymentMode.cash) cash += c.amount;
        else if (c.paymentMode == PaymentMode.upi) upi += c.amount;
        else if (c.paymentMode == PaymentMode.cheque) cheque += c.amount;
        else if (c.paymentMode == PaymentMode.both) {
          cash += c.cashAmount;
          upi += c.upiAmount;
        }
      }

      if (c.status.toLowerCase().trim() == 'completed') {
        final key = c.shopName.trim().toLowerCase();
        finCounts[key] = (finCounts[key] ?? 0) + 1;
        finNumbers[c.id] = finCounts[key]!;
      }
    }

    return CalculationResult(
      todayTotal: total,
      modeBreakdown: {'Cash': cash, 'UPI': upi, 'Cheque': cheque},
      shopFinCounts: finCounts,
      collectionFinNumbers: finNumbers,
    );
  }

  Future<void> fetchCollections(String employeeId, {String? token}) async {
    _isLoading = true;
    notifyListeners();
    
    // 1. Load from local DB first for speed
    _collections = await DatabaseHelper.instance.getEmployeeCollections(employeeId);
    await _updateCalculations();
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
    await syncAllPending(token);
  }

  Future<void> pullFromServer(String token, String employeeId) async {
    try {
      final serverData = await ApiService.getMyCollections(token);
      final List<String> serverIds = serverData.map((d) => d['id'].toString()).toList();
      
      final localCollections = await DatabaseHelper.instance.getEmployeeCollections(employeeId);
      
      for (var local in localCollections) {
        if (local.isSynced && !serverIds.contains(local.id)) {
          await DatabaseHelper.instance.deleteCollection(local.id);
        }
      }

      for (var data in serverData) {
        final coll = Collection.fromMap({
          ...data,
          'is_synced': 1 
        });
        await DatabaseHelper.instance.insertCollection(coll);
      }
      
      _collections = await DatabaseHelper.instance.getEmployeeCollections(employeeId);
      await _updateCalculations();
      notifyListeners();
    } catch (e) {
      print('Pull Sync Error: $e');
    }
  }

  Future<void> addCollection(Collection collection, String? token, {bool syncImmediately = true}) async {
    await DatabaseHelper.instance.insertCollection(collection);
    _collections.insert(0, collection);
    await _updateCalculations();
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
      await _updateCalculations();
      notifyListeners();
    }
  }

  Future<void> deleteCollection(String id) async {
    await DatabaseHelper.instance.deleteCollection(id);
    _collections.removeWhere((c) => c.id == id);
    await _updateCalculations();
    notifyListeners();
  }

  Future<void> _syncOne(
    Collection collection, 
    String token, 
    Map<String, Future<String?>> uploadRegistry
  ) async {
    Future<String?> uploadMultiple(String? pathsStr, String type) async {
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

    String? bp = await uploadMultiple(collection.billProof, 'bill');
    String? pp = await uploadMultiple(collection.paymentProof, 'payment');

    Collection toSync = collection.copyWith(billProof: bp, paymentProof: pp);

    final response = await ApiService.syncCollection(toSync, token);
    if (response != null) {
      await DatabaseHelper.instance.markAsSynced(
        collection.id, 
        billProof: bp, 
        paymentProof: pp
      );

      final index = _collections.indexWhere((c) => c.id == collection.id);
      if (index != -1) {
        _collections[index] = _collections[index].copyWith(
          isSynced: true,
          billProof: bp,
          paymentProof: pp,
        );
        await _updateCalculations();
        notifyListeners();
      }
    }
  }

  Future<void> syncAllPending(String token) async {
    final results = await Connectivity().checkConnectivity();
    if (results.isEmpty || results.first == ConnectivityResult.none) return;

    final unsynced = await DatabaseHelper.instance.getUnsyncedCollections();
    if (unsynced.isEmpty) return;
    
    final Map<String, Future<String?>> uploadRegistry = {};
    await Future.wait(unsynced.map((coll) => _syncOne(coll, token, uploadRegistry)));
  }
}

class CalculationResult {
  final double todayTotal;
  final Map<String, double> modeBreakdown;
  final Map<String, int> shopFinCounts;
  final Map<String, int> collectionFinNumbers;
  CalculationResult({
    required this.todayTotal, 
    required this.modeBreakdown, 
    required this.shopFinCounts,
    required this.collectionFinNumbers,
  });
}
