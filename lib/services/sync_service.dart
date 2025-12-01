import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/task.dart';
import 'database_service.dart';
import 'connectivity_service.dart';

// Modelo para a fila de sincronização
class SyncQueueItem {
  final int? id;
  final int taskId;
  final String operation; // 'CREATE', 'UPDATE', 'DELETE'
  final String? payload; // JSON string of the Task
  final DateTime timestamp;

  SyncQueueItem({
    this.id,
    required this.taskId,
    required this.operation,
    this.payload,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'taskId': taskId,
      'operation': operation,
      'payload': payload,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'] as int?,
      taskId: map['taskId'] as int,
      operation: map['operation'] as String,
      payload: map['payload'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseService _dbService = DatabaseService.instance;
  final ConnectivityService _connectivityService = ConnectivityService();
  
  bool _isSyncing = false;

  void initialize() {
    _connectivityService.connectionStatusStream.listen((isConnected) {
      if (isConnected) {
        _startSyncProcess();
      }
    });
  }

  // --- Fila de Sincronização (Local) ---

  Future<void> _addToSyncQueue(SyncQueueItem item) async {
    final db = await _dbService.database;
    await db.insert('sync_queue', item.toMap());
    if (kDebugMode) {
      print('Queue: Added ${item.operation} for Task ${item.taskId}');
    }
  }

  Future<List<SyncQueueItem>> _readSyncQueue() async {
    final db = await _dbService.database;
    final maps = await db.query('sync_queue', orderBy: 'timestamp ASC');
    return maps.map((map) => SyncQueueItem.fromMap(map)).toList();
  }

  Future<void> _removeFromSyncQueue(int id) async {
    final db = await _dbService.database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  // --- Lógica de Sincronização (Simulada) ---

  Future<void> _startSyncProcess() async {
    if (_isSyncing || !_connectivityService.hasConnection) return;

    _isSyncing = true;
    if (kDebugMode) {
      print('--- Starting Sync Process ---');
    }

    final queue = await _readSyncQueue();
    if (queue.isEmpty) {
      _isSyncing = false;
      if (kDebugMode) {
        print('--- Sync Process Finished: Queue Empty ---');
      }
      return;
    }

    for (final item in queue) {
      try {
        // Simulação de chamada de API
        await Future.delayed(const Duration(milliseconds: 500)); 
        
        // 1. Simular a obtenção da versão do servidor (para LWW)
        // Em um cenário real, você chamaria a API para obter a versão do servidor.
        // Aqui, vamos apenas simular que a sincronização foi bem-sucedida.
        
        Task? localTask;
        if (item.operation != 'DELETE') {
          localTask = Task.fromMap(jsonDecode(item.payload!));
        }

        // Simulação de LWW: Como estamos simulando, vamos assumir que a versão local
        // (que está na fila) é a que deve prevalecer, pois foi modificada offline.
        // Em um cenário real, você compararia item.timestamp com o timestamp do servidor.

        if (item.operation == 'CREATE' || item.operation == 'UPDATE') {
          // Simular o envio para o servidor e obter o ID do servidor (se for CREATE)
          // e a marcação como sincronizado.
          
          // Simular que o servidor retornou sucesso e a task está sincronizada
          final syncedTask = localTask!.copyWith(isSynced: true);
          
          // Atualizar o banco de dados local com a task sincronizada
          await _dbService.update(syncedTask);
          
        } else if (item.operation == 'DELETE') {
          // Simular o envio do DELETE para o servidor.
          // A tarefa já foi deletada localmente, apenas removemos da fila.
        }

        // 2. Remover da fila após sucesso
        await _removeFromSyncQueue(item.id!);
        if (kDebugMode) {
          print('Queue: Successfully synced and removed ${item.operation} for Task ${item.taskId}');
        }

      } catch (e) {
        if (kDebugMode) {
          print('Sync Error for Task ${item.taskId}: $e. Stopping sync.');
        }
        // Parar a sincronização no primeiro erro
        break; 
      }
    }

    _isSyncing = false;
    if (kDebugMode) {
      print('--- Sync Process Finished ---');
    }
  }
  
  // --- Métodos de Integração com DatabaseService ---
  
  // Estes métodos serão chamados pelo DatabaseService para garantir que
  // toda operação local seja registrada na fila.
  
  Future<void> registerCreate(Task task) async {
    final item = SyncQueueItem(
      taskId: task.id!,
      operation: 'CREATE',
      payload: jsonEncode(task.toMap()),
      timestamp: task.lastModified,
    );
    await _addToSyncQueue(item);
  }

  Future<void> registerUpdate(Task task) async {
    final item = SyncQueueItem(
      taskId: task.id!,
      operation: 'UPDATE',
      payload: jsonEncode(task.toMap()),
      timestamp: task.lastModified,
    );
    await _addToSyncQueue(item);
  }

  Future<void> registerDelete(int taskId) async {
    final item = SyncQueueItem(
      taskId: taskId,
      operation: 'DELETE',
      timestamp: DateTime.now(),
    );
    await _addToSyncQueue(item);
  }
  
  // Método auxiliar para verificar se há itens pendentes
  Future<bool> hasPendingSyncItems() async {
    final db = await _dbService.database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sync_queue'));
    return (count ?? 0) > 0;
  }
}
