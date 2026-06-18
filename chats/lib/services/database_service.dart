import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'pchats.db');
    debugPrint('[DB] opening at $path');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE users (
            uid        TEXT    PRIMARY KEY,
            handle     TEXT,
            name       TEXT,
            photo_url  TEXT,
            public_key TEXT,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE app_password (
            id            INTEGER PRIMARY KEY CHECK (id = 1),
            password_hash TEXT    NOT NULL
          )
        ''');
      },
    );
  }

  // ── Users ───────────────────────────────────────────────────────────────────

  Future<void> upsertUser({
    required String uid,
    String? handle,
    String? name,
    String? photoUrl,
    String? publicKey,
  }) async {
    final db = await _database;
    await db.insert(
      'users',
      {
        'uid': uid,
        'handle': handle,
        'name': name,
        'photo_url': photoUrl,
        'public_key': publicKey,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getUser(String uid) async {
    final db = await _database;
    final rows = await db.query('users', where: 'uid = ?', whereArgs: [uid]);
    return rows.isEmpty ? null : rows.first;
  }

  // ── Password (SHA-256 hashed) ────────────────────────────────────────────────

  static String _hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  Future<bool> hasPassword() async {
    final db = await _database;
    final rows = await db.query('app_password', limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> setPassword(String plainPassword) async {
    final db = await _database;
    await db.insert(
      'app_password',
      {'id': 1, 'password_hash': _hashPassword(plainPassword)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> verifyPassword(String plainPassword) async {
    final db = await _database;
    final rows = await db.query('app_password', limit: 1);
    if (rows.isEmpty) return false;
    final stored = rows.first['password_hash'] as String;
    return stored == _hashPassword(plainPassword);
  }

  Future<void> close() async => _db?.close();
}
