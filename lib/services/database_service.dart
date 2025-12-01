import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import './location_service.dart';
import './sync_service.dart';
import '../models/task.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tasks.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5, // VERSÃO OFFLINE-FIRST
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';

    await db.execute(
      'CREATE TABLE tasks ('
      'id $idType, '
      'title $textType, '
      'description $textType, '
      'priority $textType, '
      'completed $intType, '
      'createdAt $textType, '
      'photoPath TEXT, '
      'completedAt TEXT, '
      'completedBy TEXT, '
      'latitude REAL, '
      'longitude REAL, '
      'locationName TEXT, '
      'isSynced INTEGER NOT NULL, '
      'lastModified TEXT NOT NULL'
      ')'
    );

    await db.execute(
      'CREATE TABLE sync_queue ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'taskId INTEGER NOT NULL, '
      'operation TEXT NOT NULL, '
      'payload TEXT, '
      'timestamp TEXT NOT NULL'
      ')'
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migração incremental para cada versão
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE tasks ADD COLUMN photoPath TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE tasks ADD COLUMN completedAt TEXT');
      await db.execute('ALTER TABLE tasks ADD COLUMN completedBy TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE tasks ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE tasks ADD COLUMN longitude REAL');
      await db.execute('ALTER TABLE tasks ADD COLUMN locationName TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE tasks ADD COLUMN isSynced INTEGER NOT NULL DEFAULT 1');
      await db.execute('ALTER TABLE tasks ADD COLUMN lastModified TEXT NOT NULL DEFAULT "${DateTime.now().toIso8601String()}"');
      
      await db.execute(
        'CREATE TABLE sync_queue ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'taskId INTEGER NOT NULL, '
        'operation TEXT NOT NULL, '
        'payload TEXT, '
        'timestamp TEXT NOT NULL'
        ')'
      );
    }
    print('✅ Banco migrado de v$oldVersion para v$newVersion');
  }

  // CRUD Methods
  Future<Task> create(Task task) async {
    final db = await instance.database;
    // O campo 'id' é AUTOINCREMENT, então não passamos no insert
    // Força a task a ser marcada como não sincronizada ao ser criada
    final taskToInsert = task.copyWith(isSynced: false, lastModified: DateTime.now());
    final id = await db.insert('tasks', taskToInsert.toMap()..remove('id'));
    
    // Adicionar à fila de sincronização
    final createdTask = taskToInsert.copyWith(id: id);
    SyncService().registerCreate(createdTask);
    
    return createdTask;
  }

  Future<Task?> read(int id) async {
    final db = await instance.database;
    final maps = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Task.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Task>> readAll() async {
    final db = await instance.database;
    const orderBy = 'createdAt DESC';
    final result = await db.query('tasks', orderBy: orderBy);
    return result.map((map) => Task.fromMap(map)).toList();
  }

  Future<int> update(Task task) async {
    final db = await instance.database;
    // Força a task a ser marcada como não sincronizada ao ser atualizada
    final taskToUpdate = task.copyWith(isSynced: false, lastModified: DateTime.now());
    
    // Adicionar à fila de sincronização
    SyncService().registerUpdate(taskToUpdate);
    
    return db.update(
      'tasks',
      taskToUpdate.toMap(),
      where: 'id = ?',
      whereArgs: [taskToUpdate.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await instance.database;
    // Adicionar à fila de sincronização
    SyncService().registerDelete(id);
    
    return await db.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Custom Methods
  Future<List<Task>> getTasksNearLocation({
    required double latitude,
    required double longitude,
    required double radiusInMeters,
  }) async {
    // final db = await instance.database; // Não usado diretamente na lógica de filtro em Dart
    
    // A query SQL para calcular a distância e filtrar é complexa e ineficiente
    // em SQLite sem extensões. A abordagem mais simples é buscar todas as tarefas
    // com coordenadas e filtrar no Dart.
    final allTasks = await readAll();
    
    final nearbyTasks = allTasks.where((task) {
      if (!task.hasLocation) return false;
      
      // Cálculo de distância usando a função do geolocator
      final distance = LocationService.instance.calculateDistance(
        latitude,
        longitude,
        task.latitude!,
        task.longitude!,
      );
      
      return distance <= radiusInMeters;
    }).toList();
    
    // Ordenar por distância (mais próximas primeiro)
    nearbyTasks.sort((a, b) {
      final distA = LocationService.instance.calculateDistance(
        latitude,
        longitude,
        a.latitude!,
        a.longitude!,
      );
      final distB = LocationService.instance.calculateDistance(
        latitude,
        longitude,
        b.latitude!,
        b.longitude!,
      );
      return distA.compareTo(distB);
    });
    
    return nearbyTasks;
  }
}
