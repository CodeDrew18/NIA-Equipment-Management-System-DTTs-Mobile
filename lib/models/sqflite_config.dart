import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class SqfliteConfig {
  SqfliteConfig._();

  static final SqfliteConfig instance = SqfliteConfig._();
  static Database? _database;

  static const String databaseName = 'ems.db';
  static const int databaseVersion = 1;
  static const String dailyDriversTripTicketTable = 'daily_drivers_trip_ticket';

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, databaseName);

    return openDatabase(path, version: databaseVersion, onCreate: _onCreate);
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
  }
}
