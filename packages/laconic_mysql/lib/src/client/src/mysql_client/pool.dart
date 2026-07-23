import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'connection.dart';

/// Class to create and safely manage a pool of database connections.
class MySQLConnectionPool {
  final String host;
  final int port;
  final String userName;
  final String _password;
  final int maxConnections;
  final String? databaseName;
  final bool secure;
  final String collation;
  final Duration connectTimeout;
  final Duration commandTimeout;
  final SecurityContext? securityContext;
  final bool allowBadCertificates;

  /// Called when a connection is removed from the pool (closed or discarded).
  final void Function(MySQLConnection conn)? onConnectionRemoved;

  final List<MySQLConnection> _activeConnections = [];
  final List<MySQLConnection> _idleConnections = [];
  final Queue<Completer<void>> _waiters = Queue();

  int _pendingConnections = 0;
  bool _closed = false;

  /// Creates a new pool.
  ///
  /// Almost all parameters are identical to [MySQLConnection.createConnection].
  /// Pass [maxConnections] to set the maximum number of connections.
  /// [connectTimeout] bounds socket creation and authentication.
  /// [commandTimeout] bounds each command executed on a connection.
  MySQLConnectionPool({
    required this.host,
    required this.port,
    required this.userName,
    required String password,
    required this.maxConnections,
    this.databaseName,
    this.secure = true,
    this.collation = 'utf8_general_ci',
    this.connectTimeout = const Duration(seconds: 10),
    this.commandTimeout = const Duration(seconds: 10),
    this.securityContext,
    this.allowBadCertificates = false,
    this.onConnectionRemoved,
  }) : _password = password {
    if (maxConnections <= 0) {
      throw ArgumentError.value(
        maxConnections,
        'maxConnections',
        'must be greater than zero',
      );
    }
    if (connectTimeout <= Duration.zero) {
      throw ArgumentError.value(
        connectTimeout,
        'connectTimeout',
        'must be greater than zero',
      );
    }
    if (commandTimeout <= Duration.zero) {
      throw ArgumentError.value(
        commandTimeout,
        'commandTimeout',
        'must be greater than zero',
      );
    }
  }

  /// Number of connections currently borrowed from the pool.
  int get activeConnectionsQty => _activeConnections.length;

  /// Number of connected, idle connections ready to be borrowed.
  int get idleConnectionsQty => _idleConnections.length;

  /// Total number of active and idle connections.
  int get allConnectionsQty => activeConnectionsQty + idleConnectionsQty;

  int get _allocatedConnectionsQty => allConnectionsQty + _pendingConnections;

  /// Borrows a connection and always returns it after [callback] completes.
  Future<T> withConnection<T>(
    FutureOr<T> Function(MySQLConnection conn) callback,
  ) async {
    final conn = await _acquire();
    try {
      return await callback(conn);
    } finally {
      _release(conn);
    }
  }

  /// Runs [callback] inside a transaction on a pooled connection.
  Future<T> transactional<T>(
    FutureOr<T> Function(MySQLConnection conn) callback,
  ) {
    return withConnection((conn) => conn.transactional(callback));
  }

  /// Closes every connection and rejects pending connection requests.
  Future<void> close() async {
    _closed = true;

    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('MySQLConnectionPool is closed'));
      }
    }

    final allConnections = [..._idleConnections, ..._activeConnections];
    _idleConnections.clear();
    _activeConnections.clear();

    await Future.wait(allConnections.map((conn) => conn.close()));
  }

  Future<MySQLConnection> _acquire() async {
    if (_closed) {
      throw StateError('MySQLConnectionPool is closed');
    }

    while (true) {
      while (_idleConnections.isNotEmpty) {
        final conn = _idleConnections.removeAt(0);
        if (!conn.connected) {
          onConnectionRemoved?.call(conn);
          continue;
        }
        _activeConnections.add(conn);
        return conn;
      }

      if (_allocatedConnectionsQty < maxConnections) {
        _pendingConnections++;
        try {
          final conn = await _createConnection();
          if (_closed) {
            await conn.close();
            throw StateError('MySQLConnectionPool is closed');
          }
          _activeConnections.add(conn);
          return conn;
        } finally {
          _pendingConnections--;
          _notifyWaiter();
        }
      }

      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;

      if (_closed) {
        throw StateError('MySQLConnectionPool is closed');
      }
    }
  }

  Future<MySQLConnection> _createConnection() async {
    final conn = await MySQLConnection.createConnection(
      host: host,
      port: port,
      userName: userName,
      password: _password,
      databaseName: databaseName,
      secure: secure,
      collation: collation,
      securityContext: securityContext,
      allowBadCertificates: allowBadCertificates,
      connectTimeout: connectTimeout,
      commandTimeout: commandTimeout,
    );

    try {
      await conn.connect();
    } catch (_) {
      await conn.close();
      rethrow;
    }

    conn.onClose(() {
      _idleConnections.remove(conn);
      _activeConnections.remove(conn);
      onConnectionRemoved?.call(conn);
      _notifyWaiter();
    });

    return conn;
  }

  void _release(MySQLConnection conn) {
    final wasActive = _activeConnections.remove(conn);
    if (!wasActive) {
      _notifyWaiter();
      return;
    }

    if (_closed) {
      if (conn.connected) {
        unawaited(conn.close());
      } else {
        onConnectionRemoved?.call(conn);
      }
      _notifyWaiter();
      return;
    }

    if (!conn.connected) {
      onConnectionRemoved?.call(conn);
      _notifyWaiter();
      return;
    }

    _idleConnections.add(conn);
    _notifyWaiter();
  }

  void _notifyWaiter() {
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.complete();
        return;
      }
    }
  }
}
