import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DBHelper {
  DBHelper._internal();
  static final DBHelper instance = DBHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'attendease.db');

    return await openDatabase(
      path,
      version: 3, // ✅ UPGRADED TO VERSION 3
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade, // ✅ ADDED UPGRADE LOGIC
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  // ✅ SAFELY ADD THE SEMESTER COLUMN TO EXISTING DATABASES
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE subjects ADD COLUMN semester INTEGER NOT NULL DEFAULT 1',
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1️⃣ SUBJECTS (NOW WITH SEMESTER)
    await db.execute('''
      CREATE TABLE subjects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        required_percent REAL NOT NULL,
        semester INTEGER NOT NULL DEFAULT 1 
      )
    ''');

    // 2️⃣ TIMETABLE (LECTURES)
    await db.execute('''
      CREATE TABLE timetable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day_of_week INTEGER NOT NULL,
        subject_id INTEGER NOT NULL,
        lecture_order INTEGER NOT NULL,
        FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE
      )
    ''');

    // 3️⃣ ATTENDANCE
    await db.execute('''
      CREATE TABLE attendance_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timetable_entry_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        status TEXT CHECK(status IN ('P','A')) NOT NULL,
        UNIQUE(timetable_entry_id, date),
        FOREIGN KEY (timetable_entry_id)
          REFERENCES timetable(id)
          ON DELETE CASCADE
      )
    ''');
  }
}
