import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class SqfliteConfig {
  SqfliteConfig._();

  static final SqfliteConfig instance = SqfliteConfig._();
  static Database? _database;

  static const String databaseName = 'ems.db';
  static const int databaseVersion = 2;
  static const String dailyDriversTripTicketTable = 'daily_drivers_trip_ticket';
  static const String pendingTripTicketSyncTable = 'pending_trip_ticket_sync';

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, databaseName);

    return openDatabase(
      path,
      version: databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
			CREATE TABLE $dailyDriversTripTicketTable (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				departure_time TEXT,
				arrival_time_destination TEXT,
				departure_time_destination TEXT,
				arrival_time_office TEXT,
				odometer_end REAL,
				odometer_start REAL,
				distance_travelled REAL,
				fuel_balance_before REAL,
				fuel_issued_regional REAL,
				fuel_purchased_trip REAL,
				fuel_issued_nia REAL,
				fuel_total REAL,
				fuel_used REAL,
				fuel_balance_after REAL,
				gear_oil_liters REAL,
				engine_oil_liters REAL,
				grease_kgs REAL,
				remarks TEXT
			)
		''');

    await _createPendingSyncTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createPendingSyncTable(db);
    }
  }

  Future<void> _createPendingSyncTable(Database db) async {
    await db.execute('''
			CREATE TABLE IF NOT EXISTS $pendingTripTicketSyncTable (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				transportation_request_form_id INTEGER NOT NULL,
				payload_json TEXT NOT NULL,
				created_at INTEGER NOT NULL
			)
		''');
  }

  Future<int> queuePendingTripTicket({
    required int transportationRequestFormId,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;

    return db.insert(pendingTripTicketSyncTable, {
      'transportation_request_form_id': transportationRequestFormId,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingTripTickets() async {
    final db = await database;
    final rows = await db.query(
      pendingTripTicketSyncTable,
      orderBy: 'created_at ASC',
    );

    return rows
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  Future<void> removePendingTripTicket(int id) async {
    final db = await database;
    await db.delete(
      pendingTripTicketSyncTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Map<String, dynamic> decodePendingPayload(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
