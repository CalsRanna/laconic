import 'dart:async';
import 'dart:collection';

import 'package:mysql_client/mysql_client.dart';

/// Lightweight MySQL connection pool with safe borrow/release semantics.
///
/// Unlike [MySQLConnectionPool.withConnection] in `mysql_client` 0.0.27,
/// this pool always returns connections to the idle list in a `finally`
/// block, so SQL errors (or any thrown exception) cannot leak connection
/// slots and exhaust the pool.
class MysqlPool {
  final String host;
  final int port;
  final String userName;
  final String _password;
  final int maxConnections;
  final String? databaseName;
  final bool secure;
  final String collation;
  final int timeoutMs;

  /// Called when a connection is removed from the pool (closed or discarded).
  /// Used by [MysqlDriver] to invalidate prepared-statement cache entries.
  final void Function(MySQLConnection conn)? onConnectionRemoved;

  final List<MySQLConnection> _active = [];
  final List<MySQLConnection> _idle = [];
  final Queue<Completer<void>> _waiters = Queue();

  bool _closed = false;

  MysqlPool({
    required this.host,
    required this.port,
    required this.userName,
    required String password,
    required this.maxConnections,
    this.databaseName,
    this.secure = true,
    this.collation = 'utf8_general_ci',
    this.timeoutMs = 10000,
    this.onConnectionRemoved,
  }) : _password = password;

  int get activeConnectionsQty => _active.length;
  int get idleConnectionsQty => _idle.length;
  int get allConnectionsQty => activeConnectionsQty + idleConnectionsQty;

  /// Borrows a connection, runs [callback], and always releases the connection
  /// back to the pool (or discards it if closed), even when [callback] throws.
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

  /// Runs [callback] inside a database transaction on a pooled connection.
  Future<T> transactional<T>(
    FutureOr<T> Function(MySQLConnection conn) callback,
  ) {
    return withConnection((conn) => conn.transactional(callback));
  }

  Future<void> close() async {
    _closed = true;
    // Unblock any waiters so they fail fast instead of hanging.
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('MysqlPool is closed'));
      }
    }

    final all = [..._idle, ..._active];
    _idle.clear();
    _active.clear();

    for (final conn in all) {
      try {
        await conn.close();
      } catch (_) {
        // Best-effort close; ignore secondary failures during shutdown.
      }
      onConnectionRemoved?.call(conn);
    }
  }

  Future<MySQLConnection> _acquire() async {
    if (_closed) {
      throw StateError('MysqlPool is closed');
    }

    while (true) {
      // Prefer reusing an idle connection that is still open.
      while (_idle.isNotEmpty) {
        final conn = _idle.removeAt(0);
        if (!conn.connected) {
          onConnectionRemoved?.call(conn);
          continue;
        }
        _active.add(conn);
        return conn;
      }

      if (allConnectionsQty < maxConnections) {
        final conn = await _createConnection();
        _active.add(conn);
        return conn;
      }

      // Pool is at capacity: wait until a connection is released.
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;

      if (_closed) {
        throw StateError('MysqlPool is closed');
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
    );

    await conn.connect(timeoutMs: timeoutMs);

    conn.onClose(() {
      _idle.remove(conn);
      _active.remove(conn);
      onConnectionRemoved?.call(conn);
      _notifyWaiter();
    });

    return conn;
  }

  void _release(MySQLConnection conn) {
    // Connection may already have been removed by onClose.
    final wasActive = _active.remove(conn);
    if (!wasActive) {
      _notifyWaiter();
      return;
    }

    if (_closed || !conn.connected) {
      onConnectionRemoved?.call(conn);
      _notifyWaiter();
      return;
    }

    _idle.add(conn);
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
