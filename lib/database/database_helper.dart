import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/collection.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('collection_logger.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE collections (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        bill_no TEXT NOT NULL,
        shop_name TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_mode TEXT NOT NULL,
        date TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'partial',
        bill_proof TEXT,
        payment_proof TEXT,
        cash_amount REAL DEFAULT 0,
        upi_amount REAL DEFAULT 0
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE collections ADD COLUMN status TEXT NOT NULL DEFAULT 'partial'");
      await db.execute("ALTER TABLE collections ADD COLUMN bill_proof TEXT");
      await db.execute("ALTER TABLE collections ADD COLUMN payment_proof TEXT");
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE collections ADD COLUMN cash_amount REAL DEFAULT 0");
      await db.execute("ALTER TABLE collections ADD COLUMN upi_amount REAL DEFAULT 0");
    }
  }

  // Collection CRUD
  Future<int> insertCollection(Collection collection) async {
    final db = await instance.database;
    return await db.insert(
      'collections',
      collection.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Collection>> getAllCollections() async {
    final db = await instance.database;
    final result = await db.query('collections', orderBy: 'date DESC');
    return result.map((json) => Collection.fromMap(json)).toList();
  }

  Future<List<Collection>> getEmployeeCollections(String employeeId) async {
    final db = await instance.database;
    final result = await db.query(
      'collections',
      where: 'employee_id = ?',
      whereArgs: [employeeId],
      orderBy: 'date DESC',
    );
    return result.map((json) => Collection.fromMap(json)).toList();
  }

  Future<List<Collection>> getUnsyncedCollections() async {
    final db = await instance.database;
    final result = await db.query(
      'collections',
      where: 'is_synced = ?',
      whereArgs: [0],
    );
    return result.map((json) => Collection.fromMap(json)).toList();
  }

  Future<int> markAsSynced(String id) async {
    final db = await instance.database;
    return await db.update(
      'collections',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCollection(String id) async {
    final db = await instance.database;
    return await db.delete(
      'collections',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
