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
    // checkConnectivity() retorna Future<ConnectivityResult> na versão antiga
    final result = await _connectivity.checkConnectivity();
    _updateConnectionStatus(result);
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    final isConnected = result == ConnectivityResult.mobile ||
                        result == ConnectivityResult.wifi ||
                        result == ConnectivityResult.ethernet;
    
    if (_hasConnection != isConnected) {
      _hasConnection = isConnected;
      _connectionStatusController.add(_hasConnection);
      if (kDebugMode) {
        print('Connectivity Status Changed: ${_hasConnection ? 'Online' : 'Offline'}');
      }
    }
  }

  void dispose() {
    _connectionStatusController.close();
  }
}
