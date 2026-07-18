import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

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
    if (kIsWeb) {
      // Use web factory for sqflite on the web
      var factory = databaseFactoryFfiWeb;
      return await factory.openDatabase(
        'attendease.db',
        options: OpenDatabaseOptions(
          version: 4, // ✅ UPGRADED TO VERSION 3
          onConfigure: _onConfigure,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade, // ✅ ADDED UPGRADE LOGIC
        ),
      );
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'attendease.db');

    return await openDatabase(
      path,
      version: 4, // ✅ UPGRADED TO VERSION 3
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
    if (oldVersion < 4) {
      // Rebuild attendance_records to allow 'NU' in the status CHECK constraint
      await db.execute('ALTER TABLE attendance_records RENAME TO _ar_old');
      await db.execute('''
        CREATE TABLE attendance_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timetable_entry_id INTEGER NOT NULL,
          date TEXT NOT NULL,
          status TEXT CHECK(status IN ('P','A','NU')) NOT NULL,
          UNIQUE(timetable_entry_id, date),
          FOREIGN KEY (timetable_entry_id)
            REFERENCES timetable(id)
            ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        INSERT INTO attendance_records (id, timetable_entry_id, date, status)
        SELECT id, timetable_entry_id, date, status FROM _ar_old
      ''');
      await db.execute('DROP TABLE _ar_old');
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
        status TEXT CHECK(status IN ('P','A','NU')) NOT NULL,
        UNIQUE(timetable_entry_id, date),
        FOREIGN KEY (timetable_entry_id)
          REFERENCES timetable(id)
          ON DELETE CASCADE
      )
    ''');
  }
}
