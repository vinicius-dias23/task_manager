import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectionStatusController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  bool _hasConnection = true;
  bool get hasConnection => _hasConnection;

  void initialize() {
    // onConnectivityChanged retorna Stream<ConnectivityResult> na versão antiga
    _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    _checkInitialConnection();
  }

  Future<void> _checkInitialConnection() async {
    // SIMULAÇÃO: Sempre inicia como conectado
    _hasConnection = true;
    _connectionStatusController.add(_hasConnection);
    if (kDebugMode) {
      print('Connectivity Status: Online (SIMULADO)');
    }
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    // SIMULAÇÃO: Sempre retorna como conectado para permitir sincronização simulada
    final isConnected = true; // Simulado - sempre conectado
    
    if (_hasConnection != isConnected) {
      _hasConnection = isConnected;
      _connectionStatusController.add(_hasConnection);
      if (kDebugMode) {
        print('Connectivity Status Changed: ${_hasConnection ? 'Online' : 'Offline'} (SIMULADO)');
      }
    }
  }

  void dispose() {
    _connectionStatusController.close();
  }
}
