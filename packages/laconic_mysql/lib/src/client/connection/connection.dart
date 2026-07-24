import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:laconic_mysql/src/client/connection/command_executor.dart';
import 'package:laconic_mysql/src/client/connection/handshake_runner.dart';
import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/command/query_commands.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';
import 'package:laconic_mysql/src/client/result/prepared_statement.dart';
import 'package:laconic_mysql/src/client/result/result_set.dart';
import 'package:laconic_mysql/src/client/transport/packet_transport.dart';

enum _MysqlConnectionState {
  fresh,
  waitInitialHandshake,
  initialHandshakeResponseSend,
  connectionEstablished,
  waitingCommandResponse,
  quitCommandSend,
  closed,
}

/// Main class to interact with MySQL database
///
/// Use [MysqlConnection.createConnection] to create connection
class MysqlConnection {
  late final MysqlPacketTransport _transport;
  late final MysqlHandshakeRunner _handshake;
  late final MysqlCommandExecutor _commands;
  bool _connected = false;
  _MysqlConnectionState _state = _MysqlConnectionState.fresh;
  final String _collation;
  final List<void Function()> _onCloseCallbacks = [];
  bool _inTransaction = false;
  final Duration _connectTimeout;
  Object? _lastError;

  MysqlConnection._({
    required Socket socket,
    required String username,
    required String password,
    required String host,
    required String collation,
    bool secure = true,
    bool allowBadCertificates = false,
    SecurityContext? securityContext,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration commandTimeout = const Duration(seconds: 10),
    String? databaseName,
  }) : _connectTimeout = connectTimeout,
       _collation = collation {
    _transport = MysqlPacketTransport(
      socket: socket,
      onPacket: _processSocketData,
      onError: _handleTransportError,
      onDone: _handleSocketClose,
    );
    _handshake = MysqlHandshakeRunner(
      transport: _transport,
      username: username,
      password: password,
      host: host,
      databaseName: databaseName,
      secure: secure,
      allowBadCertificates: allowBadCertificates,
      securityContext: securityContext,
    );
    _commands = MysqlCommandExecutor(
      transport: _transport,
      timeout: commandTimeout,
      isConnected: () => _connected,
      waitUntilReady:
          () => _waitForState(_MysqlConnectionState.connectionEstablished),
      onStarted: () {
        _state = _MysqlConnectionState.waitingCommandResponse;
      },
      onCompleted: () {
        if (_state != _MysqlConnectionState.closed) {
          _state = _MysqlConnectionState.connectionEstablished;
        }
      },
      onFatalError: (error, stackTrace) {
        _forceClose(error: error, stackTrace: stackTrace);
      },
    );
  }

  /// Creates connection with provided options.
  ///
  /// Keep in mind, **this is async** function. So you need to await result.
  /// Don't forget to call [MysqlConnection.connect] to actually connect to database, or you will get errors.
  /// See examples directory for code samples.
  ///
  /// [host] host to connect to. Can be String or InternetAddress.
  /// [userName] database user name.
  /// [password] user password.
  /// [secure] If true - TLS will be used, if false - ordinary TCL connection.
  /// [databaseName] Optional database name to connect to.
  /// [collation] Optional collaction to use.
  ///
  /// By default after connection is established, this library executes query to switch connection charset and collation:
  ///
  /// ```
  /// SET @@collation_connection=$_collation, @@character_set_client=utf8mb4, @@character_set_connection=utf8mb4, @@character_set_results=utf8mb4
  /// ```
  static Future<MysqlConnection> createConnection({
    required dynamic host,
    required int port,
    required String userName,
    required String password,
    bool secure = true,
    bool allowBadCertificates = false,
    SecurityContext? securityContext,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration commandTimeout = const Duration(seconds: 10),
    String? databaseName,
    String collation = 'utf8mb4_general_ci',
  }) async {
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

    final Socket socket = await Socket.connect(
      host,
      port,
      timeout: connectTimeout,
    );

    if (socket.address.type != InternetAddressType.unix) {
      // no support for extensions on sockets
      socket.setOption(SocketOption.tcpNoDelay, true);
    }

    final client = MysqlConnection._(
      socket: socket,
      username: userName,
      password: password,
      host: host is InternetAddress ? host.address : host.toString(),
      databaseName: databaseName,
      secure: secure,
      allowBadCertificates: allowBadCertificates,
      securityContext: securityContext,
      connectTimeout: connectTimeout,
      commandTimeout: commandTimeout,
      collation: collation,
    );

    return client;
  }

  /// Returns true if this connection can be used to interact with database
  bool get connected {
    return _connected;
  }

  /// Registers callack to be executed when this connection is closed
  void onClose(void Function() callback) {
    _onCloseCallbacks.add(callback);
  }

  /// Initiate connection to database. To close connection, invoke [MysqlConnection.close] method.
  ///
  /// Default [timeoutMs] is 10000 milliseconds
  Future<void> connect({int? timeoutMs}) async {
    if (_state != _MysqlConnectionState.fresh) {
      throw MysqlClientException("Can not connect: status is not fresh");
    }

    final timeout =
        timeoutMs == null ? _connectTimeout : Duration(milliseconds: timeoutMs);

    _state = _MysqlConnectionState.waitInitialHandshake;
    _transport.expectIncomingSequence(0);
    _transport.start();

    // wait for connection established
    try {
      await Future.doWhile(() async {
        if (_lastError != null) {
          final err = _lastError;
          _forceClose();
          throw err!;
        }

        if (_state == _MysqlConnectionState.connectionEstablished) {
          return false;
        }

        if (_state == _MysqlConnectionState.closed) {
          throw const MysqlClientException(
            'Connection closed during authentication',
          );
        }

        await Future.delayed(const Duration(milliseconds: 25));
        return true;
      }).timeout(timeout);
    } catch (error, stackTrace) {
      _forceClose(error: error, stackTrace: stackTrace);
      rethrow;
    }

    // set connection charset
    await execute(
      'SET @@collation_connection=$_collation, @@character_set_client=utf8mb4, @@character_set_connection=utf8mb4, @@character_set_results=utf8mb4',
    );
  }

  void _handleTransportError(Object error, StackTrace stackTrace) {
    _lastError = error;
    _forceClose(error: error, stackTrace: stackTrace);
  }

  void _handleSocketClose() {
    if (_state == _MysqlConnectionState.closed) {
      return;
    }
    final error = const MysqlClientException(
      'MySQL socket closed before the current operation completed',
    );
    _lastError = error;
    _forceClose(error: error, stackTrace: StackTrace.current);
  }

  Future<void> _processSocketData(Uint8List data) async {
    if (_state == _MysqlConnectionState.closed) {
      // don't process any data if state is closed
      return;
    }

    if (_state == _MysqlConnectionState.waitInitialHandshake) {
      await _handshake.processInitialHandshake(data);
      _state = _MysqlConnectionState.initialHandshakeResponseSend;
      return;
    }

    if (_state == _MysqlConnectionState.initialHandshakeResponseSend) {
      if (await _handshake.processAuthenticationResponse(data)) {
        _state = _MysqlConnectionState.connectionEstablished;
        _connected = true;
      }

      return;
    }

    if (_state == _MysqlConnectionState.waitingCommandResponse) {
      await _commands.processResponse(data);
      return;
    }

    throw MysqlClientException(
      "Skipping socket data, because of connection bad state\nState: ${_state.name}\nData: $data",
    );
  }

  Future<MysqlResultSet> execute(
    String query, [
    Map<String, dynamic>? params,
    bool iterable = false,
  ]) {
    return _commands.execute(
      query,
      namedParameters: params,
      streaming: iterable,
    );
  }

  /// Execute [callback] inside database transaction
  ///
  /// If MysqlClientException is thrown inside [callback] function, transaction is rolled back
  Future<T> transactional<T>(
    FutureOr<T> Function(MysqlConnection conn) callback,
  ) async {
    // prevent double transaction
    if (_inTransaction) {
      throw MysqlClientException("Already in transaction");
    }
    _inTransaction = true;
    var started = false;
    try {
      await execute('START TRANSACTION');
      started = true;
      final result = await callback(this);
      await execute('COMMIT');
      return result;
    } catch (error, stackTrace) {
      if (started && connected) {
        try {
          await execute('ROLLBACK');
        } catch (rollbackError, rollbackStackTrace) {
          final transactionError = MysqlTransactionException(
            cause: error,
            causeStackTrace: stackTrace,
            rollbackCause: rollbackError,
            rollbackStackTrace: rollbackStackTrace,
          );
          _forceClose(error: transactionError, stackTrace: stackTrace);
          Error.throwWithStackTrace(transactionError, stackTrace);
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _inTransaction = false;
    }
  }

  Future<MysqlPreparedStatement> prepare(
    String query, [
    bool iterable = false,
  ]) {
    return _commands.prepare(query, streaming: iterable);
  }

  /// Close this connection gracefully
  ///
  /// This method is idempotent. If the connection is busy or authentication
  /// has not completed, the socket is force-closed after pending work is failed.
  Future<void> close() async {
    if (_state == _MysqlConnectionState.closed) {
      return;
    }

    if (_state == _MysqlConnectionState.connectionEstablished && _connected) {
      final packet = MysqlPacket(
        sequenceId: 0,
        payload: MysqlQuitCommand(),
        payloadLength: 0,
      );

      try {
        _transport.sendPacket(packet);
        await _transport.flush();
      } catch (_) {
        // The socket will be destroyed below even if graceful QUIT fails.
      }
    }

    _state = _MysqlConnectionState.quitCommandSend;
    await _closeSocketAndCallHandlers();
  }

  Future<void> _closeSocketAndCallHandlers() async {
    _markClosed(
      error: const MysqlClientException('MySQL connection was closed'),
      stackTrace: StackTrace.current,
    );

    try {
      await _transport.close();
    } catch (_) {
      // destroy() below is the final cleanup fallback.
    }
    _transport.destroy();
  }

  void _forceClose({Object? error, StackTrace? stackTrace}) {
    _markClosed(error: error, stackTrace: stackTrace);
    _transport.destroy();
  }

  void _markClosed({Object? error, StackTrace? stackTrace}) {
    if (_state == _MysqlConnectionState.closed) {
      if (error != null) {
        _commands.failPending(error, stackTrace ?? StackTrace.current);
      }
      return;
    }

    if (error != null) {
      _commands.failPending(error, stackTrace ?? StackTrace.current);
    } else {
      _commands.clearPending();
    }

    _state = _MysqlConnectionState.closed;
    _connected = false;
    _inTransaction = false;
    _transport.reset();

    final callbacks = List<void Function()>.of(_onCloseCallbacks);
    _onCloseCallbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  Future<void> _waitForState(_MysqlConnectionState state) async {
    if (_state == state) {
      return;
    }

    await Future.doWhile(() async {
      if (_state == state) {
        return false;
      }

      if (_state == _MysqlConnectionState.closed) {
        throw const MysqlClientException(
          'Connection closed while waiting for protocol state',
        );
      }

      await Future.delayed(Duration(microseconds: 100));
      return true;
    });
  }
}
