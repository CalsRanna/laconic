import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:laconic_mysql/src/client/exception.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/mysql_column_type.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/mysql_comm_packet.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/mysql_packet.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_auth_switch_request.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_auth_switch_response.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_binary_result_set.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_binary_result_set_row.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_column_count.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_column_definition.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_eof.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_error.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_extra_auth_data.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_extra_auth_data_response.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_handshake_response_41.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_initial_handshake.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_ok.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_result_set.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_result_set_row.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_ssl_request.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_stmt_prepare_ok.dart';

enum _MySQLConnectionState {
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
/// Use [MySQLConnection.createConnection] to create connection
class MySQLConnection {
  Socket _socket;
  bool _connected = false;
  StreamSubscription<Uint8List>? _socketSubscription;
  _MySQLConnectionState _state = _MySQLConnectionState.fresh;
  final String _username;
  final String _password;
  final String _host;
  final String _collation;
  final String? _databaseName;
  Future<void> Function(Uint8List data)? _responseCallback;
  void Function(Object error, StackTrace stackTrace)? _pendingOperationFailure;
  Timer? _pendingOperationTimer;
  Future<void> _socketProcessing = Future.value();
  final List<void Function()> _onCloseCallbacks = [];
  bool _inTransaction = false;
  final bool _secure;
  final bool _allowBadCertificates;
  final SecurityContext? _securityContext;
  final Duration _connectTimeout;
  final List<int> _incompleteBufferData = [];
  final BytesBuilder _logicalPacketData = BytesBuilder(copy: false);
  int? _logicalPacketSequence;
  int? _expectedIncomingSequence;
  bool _socketPausedForBackpressure = false;
  Object? _lastError;
  int _serverCapabilities = 0;
  String? _activeAuthPluginName;
  final int _timeoutMs;

  MySQLConnection._({
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
  }) : _socket = socket,
       _username = username,
       _password = password,
       _host = host,
       _databaseName = databaseName,
       _secure = secure,
       _allowBadCertificates = allowBadCertificates,
       _securityContext = securityContext,
       _connectTimeout = connectTimeout,
       _timeoutMs = commandTimeout.inMilliseconds,
       _collation = collation;

  /// Creates connection with provided options.
  ///
  /// Keep in mind, **this is async** function. So you need to await result.
  /// Don't forget to call [MySQLConnection.connect] to actually connect to database, or you will get errors.
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
  static Future<MySQLConnection> createConnection({
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

    final client = MySQLConnection._(
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

  /// Initiate connection to database. To close connection, invoke [MySQLConnection.close] method.
  ///
  /// Default [timeoutMs] is 10000 milliseconds
  Future<void> connect({int? timeoutMs}) async {
    if (_state != _MySQLConnectionState.fresh) {
      throw MySQLClientException("Can not connect: status is not fresh");
    }

    final timeout =
        timeoutMs == null ? _connectTimeout : Duration(milliseconds: timeoutMs);

    _state = _MySQLConnectionState.waitInitialHandshake;
    _expectIncomingSequence(0);

    _listenToSocket();

    // wait for connection established
    try {
      await Future.doWhile(() async {
        if (_lastError != null) {
          final err = _lastError;
          _forceClose();
          throw err!;
        }

        if (_state == _MySQLConnectionState.connectionEstablished) {
          return false;
        }

        if (_state == _MySQLConnectionState.closed) {
          throw const MySQLClientException(
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

  void _listenToSocket() {
    _socketSubscription = _socket.listen(
      (data) {
        _socketProcessing = _socketProcessing
            .then((_) async {
              for (final chunk in _splitPackets(data)) {
                await _processSocketData(chunk);
              }
            })
            .catchError((Object error, StackTrace stackTrace) {
              _lastError = error;
              _forceClose(error: error, stackTrace: stackTrace);
            });
      },
      onError: (Object error, StackTrace stackTrace) {
        _lastError = error;
        _forceClose(error: error, stackTrace: stackTrace);
      },
      onDone: () {
        unawaited(_socketProcessing.whenComplete(() => _handleSocketClose()));
      },
      cancelOnError: false,
    );
  }

  void _handleSocketClose() {
    if (_state == _MySQLConnectionState.closed) {
      return;
    }
    final error = const MySQLClientException(
      'MySQL socket closed before the current operation completed',
    );
    _lastError = error;
    _forceClose(error: error, stackTrace: StackTrace.current);
  }

  Future<void> _processSocketData(Uint8List data) async {
    if (_state == _MySQLConnectionState.closed) {
      // don't process any data if state is closed
      return;
    }

    if (_state == _MySQLConnectionState.waitInitialHandshake) {
      await _processInitialHandshake(data);
      return;
    }

    if (_state == _MySQLConnectionState.initialHandshakeResponseSend) {
      // check for auth switch request
      try {
        final authSwitchPacket = MySQLPacket.decodeAuthSwitchRequestPacket(
          data,
        );

        final payload =
            authSwitchPacket.payload as MySQLPacketAuthSwitchRequest;

        _activeAuthPluginName = payload.authPluginName;

        switch (payload.authPluginName) {
          case 'mysql_native_password':
            final responsePayload =
                MySQLPacketAuthSwitchResponse.createWithNativePassword(
                  password: _password,
                  challenge: payload.authPluginData.sublist(0, 20),
                );
            final responsePacket = MySQLPacket(
              sequenceID: authSwitchPacket.sequenceID + 1,
              payload: responsePayload,
              payloadLength: 0,
            );

            _socket.add(responsePacket.encode());
            _expectIncomingSequence(responsePacket.sequenceID + 1);
            return;
          case 'caching_sha2_password':
            final responsePayload =
                MySQLPacketAuthSwitchResponse.createWithCachingSha2Password(
                  password: _password,
                  challenge: payload.authPluginData.sublist(0, 20),
                );
            final responsePacket = MySQLPacket(
              sequenceID: authSwitchPacket.sequenceID + 1,
              payload: responsePayload,
              payloadLength: 0,
            );

            _socket.add(responsePacket.encode());
            _expectIncomingSequence(responsePacket.sequenceID + 1);
            return;
          default:
            throw MySQLClientException(
              "Unsupported auth plugin name: ${payload.authPluginName}",
            );
        }
      } catch (e) {
        // not auth switch request packet, continue packet processing
      }

      MySQLPacket packet;

      try {
        packet = MySQLPacket.decodeGenericPacket(data);
      } catch (e) {
        rethrow;
      }

      if (packet.payload is MySQLPacketExtraAuthData) {
        assert(_activeAuthPluginName != null);

        if (_activeAuthPluginName != 'caching_sha2_password') {
          throw MySQLClientException(
            "Unexpected auth plugin name $_activeAuthPluginName, while receiving MySQLPacketExtraAuthData packet",
          );
        }

        if (_secure == false) {
          throw MySQLClientException(
            "Auth plugin caching_sha2_password is supported only with secure connections. Pass secure: true or use another auth method",
          );
        }

        final payload = packet.payload as MySQLPacketExtraAuthData;
        final status = payload.pluginData.codeUnitAt(0);

        if (status == 3) {
          // server has password cache. just ignore
          return;
        } else if (status == 4) {
          // send password to the server
          final authExtraDataResponse = MySQLPacket(
            sequenceID: packet.sequenceID + 1,
            payload: MySQLPacketExtraAuthDataResponse(
              data: Uint8List.fromList(utf8.encode(_password)),
            ),
            payloadLength: 0,
          );

          _socket.add(authExtraDataResponse.encode());
          _expectIncomingSequence(authExtraDataResponse.sequenceID + 1);
          return;
        } else {
          throw MySQLClientException("Unsupported extra auth data: $data");
        }
      }

      if (packet.isErrorPacket()) {
        final errorPayload = packet.payload as MySQLPacketError;
        throw MySQLServerException(
          errorPayload.errorMessage,
          errorPayload.errorCode,
        );
      }

      if (packet.isOkPacket()) {
        _state = _MySQLConnectionState.connectionEstablished;
        _connected = true;
      }

      return;
    }

    if (_state == _MySQLConnectionState.waitingCommandResponse) {
      await _processCommandResponse(data);
      return;
    }

    throw MySQLClientException(
      "Skipping socket data, because of connection bad state\nState: ${_state.name}\nData: $data",
    );
  }

  Iterable<Uint8List> _splitPackets(Uint8List data) sync* {
    if (_incompleteBufferData.isNotEmpty) {
      final tmp = Uint8List.fromList(_incompleteBufferData + data.toList());
      data = tmp;
      _incompleteBufferData.clear();
    }

    Uint8List view = data;

    while (true) {
      // if packet size is less then 4 bytes, we can not even detect payload length and total packet size
      // so just append data to incomplete buffer
      if (view.length < 4) {
        _incompleteBufferData.addAll(view);
        break;
      }

      final packetLength = MySQLPacket.getPacketLength(view);

      if (view.lengthInBytes < packetLength) {
        // incomplete packet
        _incompleteBufferData.addAll(view);
        break;
      }

      final chunk = Uint8List.sublistView(view, 0, packetLength);
      final header = MySQLPacket.decodePacketHeader(chunk);
      final sequence = header.sequenceId;
      if (_expectedIncomingSequence != null &&
          sequence != _expectedIncomingSequence) {
        throw MySQLProtocolException(
          'Unexpected packet sequence id $sequence; '
          'expected $_expectedIncomingSequence',
        );
      }
      _expectedIncomingSequence = (sequence + 1) & 0xff;

      _logicalPacketSequence ??= sequence;
      if (header.payloadLength > 0) {
        _logicalPacketData.add(Uint8List.sublistView(chunk, 4));
      }

      if (header.payloadLength < mysqlMaxPhysicalPacketPayload) {
        final payload = _logicalPacketData.takeBytes();
        final logicalPacket = Uint8List(4 + payload.lengthInBytes);
        final advertisedLength =
            payload.lengthInBytes > mysqlMaxPhysicalPacketPayload
                ? mysqlMaxPhysicalPacketPayload
                : payload.lengthInBytes;
        logicalPacket[0] = advertisedLength & 0xff;
        logicalPacket[1] = (advertisedLength >> 8) & 0xff;
        logicalPacket[2] = (advertisedLength >> 16) & 0xff;
        logicalPacket[3] = _logicalPacketSequence!;
        logicalPacket.setRange(4, logicalPacket.length, payload);
        _logicalPacketSequence = null;
        yield logicalPacket;
      }

      view = Uint8List.sublistView(view, packetLength);

      if (view.isEmpty) {
        break;
      }
    }
  }

  void _expectIncomingSequence(int sequence) {
    _expectedIncomingSequence = sequence & 0xff;
  }

  Future<void> _processInitialHandshake(Uint8List data) async {
    // First packet can be error packet
    if (MySQLPacket.detectPacketType(data) == MySQLGenericPacketType.error) {
      final packet = MySQLPacket.decodeGenericPacket(data);
      final payload = packet.payload as MySQLPacketError;
      throw MySQLServerException(payload.errorMessage, payload.errorCode);
    }

    final packet = MySQLPacket.decodeInitialHandshake(data);
    final payload = packet.payload;

    if (payload is! MySQLPacketInitialHandshake) {
      throw MySQLClientException("Expected MySQLPacketInitialHandshake packet");
    }

    _serverCapabilities = payload.capabilityFlags;

    if (_secure && (_serverCapabilities & mysqlCapFlagClientSsl == 0)) {
      throw MySQLClientException(
        "Server does not support SSL connection. Pass secure: false to createConnection or enable SSL support",
      );
    }

    if (_secure) {
      // it secure = true, initiate ssl connection
      Future<void> initiateSSL() async {
        final responsePayload = MySQLPacketSSLRequest.createDefault(
          initialHandshakePayload: payload,
          connectWithDB: _databaseName != null,
        );

        final responsePacket = MySQLPacket(
          sequenceID: 1,
          payload: responsePayload,
          payloadLength: 0,
        );

        _socket.add(responsePacket.encode());

        _socketSubscription?.pause();

        final secureSocket = await SecureSocket.secure(
          _socket,
          host: _host,
          context: _securityContext,
          onBadCertificate:
              _allowBadCertificates ? (certificate) => true : null,
        );

        // switch socket
        _socket = secureSocket;

        _listenToSocket();
      }

      await initiateSSL();
    }

    final authPluginName = payload.authPluginName;
    _activeAuthPluginName = authPluginName;

    switch (authPluginName) {
      case 'mysql_native_password':
        final responsePayload =
            MySQLPacketHandshakeResponse41.createWithNativePassword(
              username: _username,
              password: _password,
              initialHandshakePayload: payload,
              secure: _secure,
            );

        responsePayload.database = _databaseName;

        final responsePacket = MySQLPacket(
          payload: responsePayload,
          sequenceID: _secure ? 2 : 1,
          payloadLength: 0,
        );

        _state = _MySQLConnectionState.initialHandshakeResponseSend;
        _socket.add(responsePacket.encode());
        _expectIncomingSequence(responsePacket.sequenceID + 1);
        break;
      case 'caching_sha2_password':
        final responsePayload =
            MySQLPacketHandshakeResponse41.createWithCachingSha2Password(
              username: _username,
              password: _password,
              initialHandshakePayload: payload,
              secure: _secure,
            );

        responsePayload.database = _databaseName;

        final responsePacket = MySQLPacket(
          payload: responsePayload,
          sequenceID: _secure ? 2 : 1,
          payloadLength: 0,
        );

        _state = _MySQLConnectionState.initialHandshakeResponseSend;
        _socket.add(responsePacket.encode());
        _expectIncomingSequence(responsePacket.sequenceID + 1);
        break;
      default:
        throw MySQLClientException(
          "Unsupported auth plugin name: $authPluginName",
        );
    }
  }

  Future<void> _processCommandResponse(Uint8List data) async {
    assert(_responseCallback != null);
    await _responseCallback!(data);
  }

  void _registerPendingOperation<T>(
    Completer<T> completer, {
    StreamSink<ResultSetRow>? Function()? streamSink,
  }) {
    _pendingOperationTimer?.cancel();
    _pendingOperationFailure = (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
        return;
      }

      final sink = streamSink?.call();
      if (sink != null) {
        sink.addError(error, stackTrace);
        unawaited(sink.close());
      }
    };
    _pendingOperationTimer = Timer(Duration(milliseconds: _timeoutMs), () {
      final error = TimeoutException('MySQL command exceeded ${_timeoutMs}ms');
      _forceClose(error: error, stackTrace: StackTrace.current);
    });
  }

  void _clearPendingOperation() {
    _pendingOperationTimer?.cancel();
    _pendingOperationTimer = null;
    _pendingOperationFailure = null;
    _responseCallback = null;
  }

  void _failPendingOperation(Object error, StackTrace stackTrace) {
    final failure = _pendingOperationFailure;
    _clearPendingOperation();
    failure?.call(error, stackTrace);
  }

  Future<T> _awaitCommand<T>(
    Completer<T> completer, {
    bool clearOnCompletion = true,
  }) async {
    try {
      return await completer.future.timeout(Duration(milliseconds: _timeoutMs));
    } on TimeoutException catch (error, stackTrace) {
      _forceClose(error: error, stackTrace: stackTrace);
      rethrow;
    } finally {
      if (clearOnCompletion) {
        _clearPendingOperation();
      }
    }
  }

  /// Executes given [query]
  ///
  /// [execute] can be used to make any query type (SELECT, INSERT, UPDATE)
  /// You can pass named parameters using [params]
  /// Pass [iterable] true if you want to receive rows one by one in Stream fashion
  Future<IResultSet> execute(
    String query, [
    Map<String, dynamic>? params,
    bool iterable = false,
  ]) async {
    if (!_connected) {
      throw MySQLClientException("Can not execute query: connection closed");
    }

    // wait for ready state
    if (_state != _MySQLConnectionState.connectionEstablished) {
      await _waitForState(
        _MySQLConnectionState.connectionEstablished,
      ).timeout(Duration(milliseconds: _timeoutMs));
    }

    _state = _MySQLConnectionState.waitingCommandResponse;

    if (params != null && params.isNotEmpty) {
      _state = _MySQLConnectionState.connectionEstablished;
      throw const MySQLClientException(
        'Named text-protocol parameters are not supported. '
        'Use prepare() and positional parameters instead.',
      );
    }

    final payload = MySQLPacketCommQuery(query: query);

    final packet = MySQLPacket(
      sequenceID: 0,
      payload: payload,
      payloadLength: 0,
    );

    final completer = Completer<IResultSet>();

    /**
     * 0 - initial
     * 1 - columnCount decoded
     * 2 - columnDefs parsed
     * 3 - eofParsed
     * 4 - rowsParsed
     */
    int state = 0;
    int colsCount = 0;
    List<MySQLColumnDefinitionPacket> colDefs = [];
    List<MySQLResultSetRowPacket> resultSetRows = [];

    // support for iterable result set
    IterableResultSet? iterableResultSet;
    StreamSink<ResultSetRow>? sink;

    _registerPendingOperation(
      completer,
      streamSink: () => iterableResultSet?._cancelled == true ? null : sink,
    );

    // used as a pointer to handle multiple result sets
    IResultSet? currentResultSet;
    IResultSet? firstResultSet;

    _responseCallback = (data) async {
      try {
        MySQLPacket? packet;

        switch (state) {
          case 0:
            // if packet is OK packet, there is no data
            if (MySQLPacket.detectPacketType(data) ==
                MySQLGenericPacketType.ok) {
              final okPacket = MySQLPacket.decodeGenericPacket(data);
              _state = _MySQLConnectionState.connectionEstablished;
              if (iterable) {
                _clearPendingOperation();
              }
              completer.complete(
                EmptyResultSet(okPacket: okPacket.payload as MySQLPacketOK),
              );

              return;
            }

            packet = MySQLPacket.decodeColumnCountPacket(data);
            break;
          case 1:
            packet = MySQLPacket.decodeColumnDefPacket(data);
            break;
          case 2:
            packet = MySQLPacket.decodeGenericPacket(data);
            if (packet.isEOFPacket()) {
              state = 3;
            }
            break;
          case 3:
            if (iterable) {
              if (iterableResultSet == null) {
                iterableResultSet = IterableResultSet._(
                  columns: colDefs,
                  onPause: _pauseSocket,
                  onResume: _resumeSocket,
                  onCancel: _resumeSocket,
                );

                sink = iterableResultSet!._sink;
                completer.complete(iterableResultSet);
              }

              // check eof
              if (MySQLPacket.detectPacketType(data) ==
                  MySQLGenericPacketType.eof) {
                state = 4;

                await sink!.close();
                _clearPendingOperation();
                _state = _MySQLConnectionState.connectionEstablished;
                return;
              }

              packet = MySQLPacket.decodeResultSetRowPacket(data, colDefs);
              final values = (packet.payload as MySQLResultSetRowPacket).values;
              if (!iterableResultSet!._cancelled) {
                sink!.add(ResultSetRow._(colDefs: colDefs, values: values));
              }
              packet = null;
              break;
            } else {
              // check eof
              if (MySQLPacket.detectPacketType(data) ==
                  MySQLGenericPacketType.eof) {
                final resultSetPacket = MySQLPacketResultSet(
                  columnCount: BigInt.from(colsCount),
                  columns: colDefs,
                  rows: resultSetRows,
                );

                final resultSet = ResultSet._(resultSetPacket: resultSetPacket);

                if (currentResultSet != null) {
                  currentResultSet!.next = resultSet;
                } else {
                  firstResultSet = resultSet;
                }
                currentResultSet = resultSet;

                final eofPacket = MySQLPacket.decodeGenericPacket(data);
                final eofPayload = eofPacket.payload as MySQLPacketEOF;

                if (eofPayload.statusFlags & mysqlServerFlagMoreResultsExists !=
                    0) {
                  state = 0;
                  colsCount = 0;
                  colDefs = [];
                  resultSetRows = [];
                  return;
                } else {
                  // there is no more results, just return
                  state = 4;
                  _state = _MySQLConnectionState.connectionEstablished;
                  completer.complete(firstResultSet);
                  return;
                }
              }

              packet = MySQLPacket.decodeResultSetRowPacket(data, colDefs);
              break;
            }
        }

        if (packet != null) {
          final payload = packet.payload;

          if (payload is MySQLPacketError) {
            _failPendingOperation(
              MySQLServerException(payload.errorMessage, payload.errorCode),
              StackTrace.current,
            );
            _state = _MySQLConnectionState.connectionEstablished;
            return;
          } else if (payload is MySQLPacketOK || payload is MySQLPacketEOF) {
            // do nothing
          } else if (payload is MySQLPacketColumnCount) {
            state = 1;
            colsCount = payload.columnCount.toInt();
            return;
          } else if (payload is MySQLColumnDefinitionPacket) {
            colDefs.add(payload);
            if (colDefs.length == colsCount) {
              state = 2;
            }
          } else if (payload is MySQLResultSetRowPacket) {
            assert(iterable == false);
            resultSetRows.add(payload);
          } else {
            _forceClose(
              error: const MySQLClientException(
                'Unexpected payload received in response to COMM_QUERY request',
              ),
              stackTrace: StackTrace.current,
            );
            return;
          }
        }
      } catch (e, stackTrace) {
        _forceClose(error: e, stackTrace: stackTrace);
      }
    };

    _sendPacketExpectingResponse(packet);

    return _awaitCommand(completer, clearOnCompletion: !iterable);
  }

  /// Execute [callback] inside database transaction
  ///
  /// If MySQLClientException is thrown inside [callback] function, transaction is rolled back
  Future<T> transactional<T>(
    FutureOr<T> Function(MySQLConnection conn) callback,
  ) async {
    // prevent double transaction
    if (_inTransaction) {
      throw MySQLClientException("Already in transaction");
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
          final transactionError = MySQLTransactionException(
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

  /// Prepares given [query]
  ///
  /// Returns [PreparedStmt] which can be used to execute prepared statement multiple times with different parameters
  /// See [PreparedStmt.execute]
  /// You shoud call [PreparedStmt.deallocate] when you don't need prepared statement anymore to prevent memory leaks
  ///
  /// Pass [iterable] true if you want to iterable result set. See [execute] for details
  Future<PreparedStmt> prepare(String query, [bool iterable = false]) async {
    if (!_connected) {
      throw MySQLClientException("Can not prepare stmt: connection closed");
    }

    // wait for ready state
    if (_state != _MySQLConnectionState.connectionEstablished) {
      await _waitForState(
        _MySQLConnectionState.connectionEstablished,
      ).timeout(Duration(milliseconds: _timeoutMs));
    }

    _state = _MySQLConnectionState.waitingCommandResponse;

    final payload = MySQLPacketCommStmtPrepare(query: query);

    final packet = MySQLPacket(
      sequenceID: 0,
      payload: payload,
      payloadLength: 0,
    );

    final completer = Completer<PreparedStmt>();
    _registerPendingOperation(completer);

    /**
     * 0 - initial
     * 1 - first packet decoded
     * 2 - eof decoded
     */
    int state = 0;
    int numOfEofPacketsParsed = 0;
    MySQLPacketStmtPrepareOK? preparedPacket;

    _responseCallback = (data) async {
      try {
        MySQLPacket? packet;

        switch (state) {
          case 0:
            packet = MySQLPacket.decodeCommPrepareStmtResponsePacket(data);
            state = 1;
            break;
          default:
            packet = null;

            if (MySQLPacket.detectPacketType(data) ==
                MySQLGenericPacketType.eof) {
              numOfEofPacketsParsed++;

              var done = false;

              assert(preparedPacket != null);

              if (preparedPacket!.numOfCols > 0 &&
                  preparedPacket!.numOfParams > 0) {
                // there should be two EOF packets in this case
                if (numOfEofPacketsParsed == 2) {
                  done = true;
                }
              } else {
                // there should be only one EOF packet otherwise
                done = true;
              }

              if (done) {
                state = 2;

                completer.complete(
                  PreparedStmt._(
                    preparedPacket: preparedPacket!,
                    connection: this,
                    iterable: iterable,
                  ),
                );

                _state = _MySQLConnectionState.connectionEstablished;

                return;
              }
            }

            break;
        }

        if (packet != null) {
          final payload = packet.payload;

          if (payload is MySQLPacketStmtPrepareOK) {
            preparedPacket = payload;
            if (payload.numOfCols == 0 && payload.numOfParams == 0) {
              _state = _MySQLConnectionState.connectionEstablished;
              completer.complete(
                PreparedStmt._(
                  preparedPacket: payload,
                  connection: this,
                  iterable: iterable,
                ),
              );
            }
          } else if (payload is MySQLPacketError) {
            _failPendingOperation(
              MySQLServerException(payload.errorMessage, payload.errorCode),
              StackTrace.current,
            );
            _state = _MySQLConnectionState.connectionEstablished;
            return;
          } else {
            _forceClose(
              error: const MySQLClientException(
                'Unexpected payload received in response to '
                'COMM_STMT_PREPARE request',
              ),
              stackTrace: StackTrace.current,
            );
            return;
          }
        }
      } catch (e, stackTrace) {
        _forceClose(error: e, stackTrace: stackTrace);
      }
    };

    _sendPacketExpectingResponse(packet);

    return _awaitCommand(completer);
  }

  Future<IResultSet> _executePreparedStmt(
    PreparedStmt stmt,
    List<dynamic> params,
    bool iterable,
  ) async {
    if (!_connected) {
      throw MySQLClientException(
        "Can not execute prepared stmt: connection closed",
      );
    }

    // wait for ready state
    if (_state != _MySQLConnectionState.connectionEstablished) {
      await _waitForState(
        _MySQLConnectionState.connectionEstablished,
      ).timeout(Duration(milliseconds: _timeoutMs));
    }

    _state = _MySQLConnectionState.waitingCommandResponse;

    final payload = MySQLPacketCommStmtExecute(
      stmtID: stmt._preparedPacket.stmtID,
      params: params,
    );

    final packet = MySQLPacket(
      sequenceID: 0,
      payload: payload,
      payloadLength: 0,
    );

    final completer = Completer<IResultSet>();

    /**
     * 0 - initial
     * 1 - columnCount decoded
     * 2 - columnDefs parsed
     * 3 - eofParsed
     * 4 - rowsParsed
     */
    int state = 0;
    int colsCount = 0;
    List<MySQLColumnDefinitionPacket> colDefs = [];
    List<MySQLBinaryResultSetRowPacket> resultSetRows = [];

    // support for iterable result set
    IterablePreparedStmtResultSet? iterableResultSet;
    StreamSink<ResultSetRow>? sink;

    _registerPendingOperation(
      completer,
      streamSink: () => iterableResultSet?._cancelled == true ? null : sink,
    );

    _responseCallback = (data) async {
      try {
        MySQLPacket? packet;

        switch (state) {
          case 0:
            // if packet is OK packet, there is no data
            if (MySQLPacket.detectPacketType(data) ==
                MySQLGenericPacketType.ok) {
              final okPacket = MySQLPacket.decodeGenericPacket(data);
              _state = _MySQLConnectionState.connectionEstablished;
              if (iterable) {
                _clearPendingOperation();
              }

              completer.complete(
                EmptyResultSet(okPacket: okPacket.payload as MySQLPacketOK),
              );

              return;
            }

            packet = MySQLPacket.decodeColumnCountPacket(data);
            break;
          case 1:
            packet = MySQLPacket.decodeColumnDefPacket(data);
            break;
          case 2:
            packet = MySQLPacket.decodeGenericPacket(data);
            if (packet.isEOFPacket()) {
              state = 3;
            } else if (packet.isErrorPacket()) {
              final errorPayload = packet.payload as MySQLPacketError;
              _failPendingOperation(
                MySQLServerException(
                  errorPayload.errorMessage,
                  errorPayload.errorCode,
                ),
                StackTrace.current,
              );
              _state = _MySQLConnectionState.connectionEstablished;
              return;
            } else {
              _forceClose(
                error: const MySQLClientException('Unexpected packet type'),
                stackTrace: StackTrace.current,
              );
              return;
            }
            break;
          case 3:
            if (iterable) {
              if (iterableResultSet == null) {
                iterableResultSet = IterablePreparedStmtResultSet._(
                  columns: colDefs,
                  onPause: _pauseSocket,
                  onResume: _resumeSocket,
                  onCancel: _resumeSocket,
                );

                sink = iterableResultSet!._sink;
                completer.complete(iterableResultSet);
              }

              // check eof
              if (MySQLPacket.detectPacketType(data) ==
                  MySQLGenericPacketType.eof) {
                state = 4;

                await sink!.close();
                _clearPendingOperation();
                _state = _MySQLConnectionState.connectionEstablished;
                return;
              }

              packet = MySQLPacket.decodeBinaryResultSetRowPacket(
                data,
                colDefs,
              );
              final values =
                  (packet.payload as MySQLBinaryResultSetRowPacket).values;
              if (!iterableResultSet!._cancelled) {
                sink!.add(ResultSetRow._(colDefs: colDefs, values: values));
              }
              packet = null;
              break;
            } else {
              // check eof
              if (MySQLPacket.detectPacketType(data) ==
                  MySQLGenericPacketType.eof) {
                state = 4;

                final resultSetPacket = MySQLPacketBinaryResultSet(
                  columnCount: BigInt.from(colsCount),
                  columns: colDefs,
                  rows: resultSetRows,
                );

                _state = _MySQLConnectionState.connectionEstablished;

                completer.complete(
                  PreparedStmtResultSet._(resultSetPacket: resultSetPacket),
                );

                return;
              }

              packet = MySQLPacket.decodeBinaryResultSetRowPacket(
                data,
                colDefs,
              );

              break;
            }
        }

        if (packet != null) {
          final payload = packet.payload;

          if (payload is MySQLPacketError) {
            _failPendingOperation(
              MySQLServerException(payload.errorMessage, payload.errorCode),
              StackTrace.current,
            );
            _state = _MySQLConnectionState.connectionEstablished;
            return;
          } else if (payload is MySQLPacketOK || payload is MySQLPacketEOF) {
            // do nothing
          } else if (payload is MySQLPacketColumnCount) {
            state = 1;
            colsCount = payload.columnCount.toInt();
            return;
          } else if (payload is MySQLColumnDefinitionPacket) {
            colDefs.add(payload);
            if (colDefs.length == colsCount) {
              state = 2;
            }
          } else if (payload is MySQLBinaryResultSetRowPacket) {
            resultSetRows.add(payload);
          } else {
            _forceClose(
              error: const MySQLClientException(
                'Unexpected payload received in response to COMM_QUERY request',
              ),
              stackTrace: StackTrace.current,
            );
            return;
          }
        }
      } catch (e, stackTrace) {
        _forceClose(error: e, stackTrace: stackTrace);
      }
    };

    _sendPacketExpectingResponse(packet);

    return _awaitCommand(completer, clearOnCompletion: !iterable);
  }

  Future<void> _deallocatePreparedStmt(PreparedStmt stmt) async {
    if (!_connected) {
      throw MySQLClientException("Can not execute query: connection closed");
    }

    // wait for ready state
    if (_state != _MySQLConnectionState.connectionEstablished) {
      await _waitForState(
        _MySQLConnectionState.connectionEstablished,
      ).timeout(Duration(milliseconds: _timeoutMs));
    }

    final payload = MySQLPacketCommStmtClose(
      stmtID: stmt._preparedPacket.stmtID,
    );

    final packet = MySQLPacket(
      sequenceID: 0,
      payload: payload,
      payloadLength: 0,
    );

    _socket.add(packet.encode());
  }

  void _pauseSocket() {
    if (_socketPausedForBackpressure) {
      return;
    }
    _socketPausedForBackpressure = true;
    _socketSubscription?.pause();
  }

  void _resumeSocket() {
    if (!_socketPausedForBackpressure) {
      return;
    }
    _socketPausedForBackpressure = false;
    final subscription = _socketSubscription;
    if (subscription != null && subscription.isPaused) {
      subscription.resume();
    }
  }

  void _sendPacketExpectingResponse(MySQLPacket packet) {
    final encoded = packet.encode();
    var offset = 0;
    var nextSequence = packet.sequenceID & 0xff;
    while (offset < encoded.lengthInBytes) {
      final frame = Uint8List.sublistView(encoded, offset);
      final header = MySQLPacket.decodePacketHeader(frame);
      nextSequence = (header.sequenceId + 1) & 0xff;
      offset += header.payloadLength + 4;
    }
    _expectIncomingSequence(nextSequence);
    _socket.add(encoded);
  }

  /// Close this connection gracefully
  ///
  /// This method is idempotent. If the connection is busy or authentication
  /// has not completed, the socket is force-closed after pending work is failed.
  Future<void> close() async {
    if (_state == _MySQLConnectionState.closed) {
      return;
    }

    if (_state == _MySQLConnectionState.connectionEstablished && _connected) {
      final packet = MySQLPacket(
        sequenceID: 0,
        payload: MySQLPacketCommQuit(),
        payloadLength: 0,
      );

      try {
        _socket.add(packet.encode());
        await _socket.flush();
      } catch (_) {
        // The socket will be destroyed below even if graceful QUIT fails.
      }
    }

    _state = _MySQLConnectionState.quitCommandSend;
    await _closeSocketAndCallHandlers();
  }

  Future<void> _closeSocketAndCallHandlers() async {
    _markClosed(
      error: const MySQLClientException('MySQL connection was closed'),
      stackTrace: StackTrace.current,
    );

    try {
      await _socketSubscription?.cancel();
    } catch (_) {
      // Continue closing the underlying socket.
    }
    try {
      await _socket.close();
    } catch (_) {
      // destroy() below is the final cleanup fallback.
    }
    _socket.destroy();
  }

  void _forceClose({Object? error, StackTrace? stackTrace}) {
    _markClosed(error: error, stackTrace: stackTrace);
    unawaited(_socketSubscription?.cancel() ?? Future.value());
    _socket.destroy();
  }

  void _markClosed({Object? error, StackTrace? stackTrace}) {
    if (_state == _MySQLConnectionState.closed) {
      if (error != null) {
        _failPendingOperation(error, stackTrace ?? StackTrace.current);
      }
      return;
    }

    if (error != null) {
      _failPendingOperation(error, stackTrace ?? StackTrace.current);
    } else {
      _clearPendingOperation();
    }

    _state = _MySQLConnectionState.closed;
    _connected = false;
    _inTransaction = false;
    _incompleteBufferData.clear();
    _logicalPacketData.takeBytes();
    _logicalPacketSequence = null;
    _expectedIncomingSequence = null;
    _socketPausedForBackpressure = false;
    _responseCallback = null;

    final callbacks = List<void Function()>.of(_onCloseCallbacks);
    _onCloseCallbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  Future<void> _waitForState(_MySQLConnectionState state) async {
    if (_state == state) {
      return;
    }

    await Future.doWhile(() async {
      if (_state == state) {
        return false;
      }

      if (_state == _MySQLConnectionState.closed) {
        throw const MySQLClientException(
          'Connection closed while waiting for protocol state',
        );
      }

      await Future.delayed(Duration(microseconds: 100));
      return true;
    });
  }
}

/// Base class to represent result of calling [MySQLConnection.execute] and [PreparedStmt.execute]
abstract class IResultSet
    with IterableMixin<IResultSet>
    implements Iterator<IResultSet>, Iterable<IResultSet> {
  /// Number of colums in this result if any
  int get numOfColumns;

  /// Number of rows in this result if any (unavailable for iterable results)
  int get numOfRows;

  /// Number of affected rows
  BigInt get affectedRows;

  /// Last insert ID
  BigInt get lastInsertID;

  /// Next result set, if any.
  /// Prepared statements and iterable result sets does not supprot this
  IResultSet? next;

  IResultSet? _current;

  @override
  Iterator<IResultSet> get iterator => this;

  @override
  IResultSet get current {
    if (_current != null) {
      return _current!;
    } else {
      throw RangeError("Trying to access past the end value");
    }
  }

  @override
  bool moveNext() {
    if (_current == null) {
      _current = this;
      return true;
    } else {
      if (_current!.next != null) {
        _current = _current!.next;
        return true;
      } else {
        return false;
      }
    }
  }

  /// Provides access to data rows (unavailable for iterable results)
  Iterable<ResultSetRow> get rows;

  /// Use [cols] to get info about returned columns
  Iterable<ResultSetColumn> get cols;

  /// Provides Stream like access to data rows. Use [rowsStream] to get rows from iterable results
  Stream<ResultSetRow> get rowsStream => Stream.fromIterable(rows);
}

/// Represents result of [MySQLConnection.execute] method
class ResultSet extends IResultSet {
  final MySQLPacketResultSet _resultSetPacket;

  ResultSet._({required MySQLPacketResultSet resultSetPacket})
    : _resultSetPacket = resultSetPacket;

  @override
  int get numOfColumns => _resultSetPacket.columns.length;

  @override
  int get numOfRows => _resultSetPacket.rows.length;

  @override
  BigInt get affectedRows => BigInt.zero;

  @override
  BigInt get lastInsertID => BigInt.zero;

  @override
  Iterable<ResultSetRow> get rows sync* {
    for (final row in _resultSetPacket.rows) {
      yield ResultSetRow._(
        colDefs: _resultSetPacket.columns,
        values: row.values,
      );
    }
  }

  @override
  Iterable<ResultSetColumn> get cols {
    return _resultSetPacket.columns.map(
      (e) =>
          ResultSetColumn(name: e.name, type: e.type, length: e.columnLength),
    );
  }
}

/// Represents result of [MySQLConnection.execute] method when passing iterable = true
class IterableResultSet with IterableMixin<IResultSet> implements IResultSet {
  final List<MySQLColumnDefinitionPacket> _columns;
  late StreamController<ResultSetRow> _controller;
  bool _cancelled = false;

  IterableResultSet._({
    required List<MySQLColumnDefinitionPacket> columns,
    required void Function() onPause,
    required void Function() onResume,
    required void Function() onCancel,
  }) : _columns = columns {
    _controller = StreamController(
      onPause: onPause,
      onResume: onResume,
      onCancel: () {
        _cancelled = true;
        onCancel();
      },
    );
  }

  @override
  IResultSet? get next => throw UnimplementedError();

  @override
  set next(val) => throw UnimplementedError();

  @override
  Iterator<IResultSet> get iterator => throw UnimplementedError();

  @override
  IResultSet? _current;

  @override
  IResultSet get current => throw UnimplementedError();

  @override
  bool moveNext() => throw UnimplementedError();

  StreamSink<ResultSetRow> get _sink => _controller.sink;

  @override
  Stream<ResultSetRow> get rowsStream => _controller.stream;

  @override
  int get numOfColumns => _columns.length;

  @override
  int get numOfRows =>
      throw MySQLClientException(
        "numOfRows is not implemented for IterableResultSet",
      );

  @override
  BigInt get affectedRows => BigInt.zero;

  @override
  BigInt get lastInsertID => BigInt.zero;

  @override
  Iterable<ResultSetColumn> get cols {
    return _columns.map(
      (e) =>
          ResultSetColumn(name: e.name, type: e.type, length: e.columnLength),
    );
  }

  @override
  Iterable<ResultSetRow> get rows =>
      throw MySQLClientException(
        "Use rowsStream to get rows from IterableResultSet",
      );
}

/// Represents result of [PreparedStmt.execute] method
class PreparedStmtResultSet extends IResultSet {
  final MySQLPacketBinaryResultSet _resultSetPacket;

  PreparedStmtResultSet._({required MySQLPacketBinaryResultSet resultSetPacket})
    : _resultSetPacket = resultSetPacket;

  @override
  int get numOfColumns => _resultSetPacket.columns.length;

  @override
  int get numOfRows => _resultSetPacket.rows.length;

  @override
  BigInt get affectedRows => BigInt.zero;

  @override
  BigInt get lastInsertID => BigInt.zero;

  @override
  Iterable<ResultSetRow> get rows sync* {
    for (final row in _resultSetPacket.rows) {
      yield ResultSetRow._(
        colDefs: _resultSetPacket.columns,
        values: row.values,
      );
    }
  }

  @override
  Iterable<ResultSetColumn> get cols {
    return _resultSetPacket.columns.map(
      (e) =>
          ResultSetColumn(name: e.name, type: e.type, length: e.columnLength),
    );
  }
}

/// Represents result of [PreparedStmt.execute] method when using iterable = true
class IterablePreparedStmtResultSet extends IResultSet {
  final List<MySQLColumnDefinitionPacket> _columns;
  late StreamController<ResultSetRow> _controller;
  bool _cancelled = false;

  IterablePreparedStmtResultSet._({
    required List<MySQLColumnDefinitionPacket> columns,
    required void Function() onPause,
    required void Function() onResume,
    required void Function() onCancel,
  }) : _columns = columns {
    _controller = StreamController(
      onPause: onPause,
      onResume: onResume,
      onCancel: () {
        _cancelled = true;
        onCancel();
      },
    );
  }

  StreamSink<ResultSetRow> get _sink => _controller.sink;

  @override
  int get numOfColumns => _columns.length;

  @override
  int get numOfRows =>
      throw MySQLClientException(
        "numOfRows is not implemented for IterableResultSet",
      );

  @override
  BigInt get affectedRows => BigInt.zero;

  @override
  BigInt get lastInsertID => BigInt.zero;

  @override
  Iterable<ResultSetRow> get rows =>
      throw MySQLClientException(
        "Use rowsStream to get rows from IterablePreparedStmtResultSet",
      );

  @override
  Stream<ResultSetRow> get rowsStream => _controller.stream;

  @override
  Iterable<ResultSetColumn> get cols {
    return _columns.map(
      (e) =>
          ResultSetColumn(name: e.name, type: e.type, length: e.columnLength),
    );
  }
}

/// Represents empty result set
class EmptyResultSet extends IResultSet {
  final MySQLPacketOK _okPacket;

  EmptyResultSet({required MySQLPacketOK okPacket}) : _okPacket = okPacket;

  @override
  int get numOfColumns => 0;

  @override
  int get numOfRows => 0;

  @override
  BigInt get affectedRows => _okPacket.affectedRows;

  @override
  BigInt get lastInsertID => _okPacket.lastInsertID;

  @override
  Iterable<ResultSetRow> get rows => List<ResultSetRow>.empty();

  @override
  Iterable<ResultSetColumn> get cols => List<ResultSetColumn>.empty();
}

/// Represents result set row data
class ResultSetRow {
  final List<MySQLColumnDefinitionPacket> _colDefs;
  final List<Object?> _values;

  ResultSetRow._({
    required List<MySQLColumnDefinitionPacket> colDefs,
    required List<Object?> values,
  }) : _colDefs = colDefs,
       _values = values;

  /// Get number of columns for this row
  int get numOfColumns => _colDefs.length;

  /// Get column data by column index (starting form 0)
  Object? colAt(int colIndex) {
    if (colIndex >= _values.length) {
      throw MySQLClientException("Column index is out of range");
    }

    final value = _values[colIndex];

    return value;
  }

  /// Same as [colAt] but performs conversion of string data, into provided type [T], if possible
  ///
  /// Conversion is "typesafe", meaning that actual MySQL column type will be checked,
  /// to decide is it possible to make such a conversion
  ///
  /// Throws [MySQLClientException] if conversion is not possible
  T? typedColAt<T>(int colIndex) {
    final value = colAt(colIndex);
    final colDef = _colDefs[colIndex];

    if (value == null) {
      return null;
    }
    if (T == bool &&
        value is int &&
        colDef.type.intVal == mysqlColumnTypeTiny &&
        colDef.columnLength == 1) {
      return (value > 0) as T;
    }
    if (T == dynamic || value is T) {
      return value as T;
    }
    if (value is! String) {
      throw MySQLProtocolException(
        'Can not convert ${value.runtimeType} to requested type $T',
      );
    }

    return colDef.type.convertStringValueToProvidedType<T>(
      value,
      colDef.columnLength,
    );
  }

  /// Get column data by column name
  Object? colByName(String columnName) {
    final colIndex = _colDefs.indexWhere(
      (element) => element.name.toLowerCase() == columnName.toLowerCase(),
    );

    if (colIndex == -1) {
      throw MySQLClientException("There is no column with name: $columnName");
    }

    if (colIndex >= _values.length) {
      throw MySQLClientException("Column index is out of range");
    }

    final value = _values[colIndex];

    return value;
  }

  /// Same as [colByName] but performs conversion of string data, into provided type [T], if possible
  ///
  /// Conversion is "typesafe", meaning that actual MySQL column type will be checked,
  /// to decide is it possible to make such a conversion
  ///
  /// Throws [MySQLClientException] if conversion is not possible
  T? typedColByName<T>(String columnName) {
    final value = colByName(columnName);

    final colIndex = _colDefs.indexWhere(
      (element) => element.name.toLowerCase() == columnName.toLowerCase(),
    );

    final colDef = _colDefs[colIndex];

    if (value == null) {
      return null;
    }
    if (T == bool &&
        value is int &&
        colDef.type.intVal == mysqlColumnTypeTiny &&
        colDef.columnLength == 1) {
      return (value > 0) as T;
    }
    if (T == dynamic || value is T) {
      return value as T;
    }
    if (value is! String) {
      throw MySQLProtocolException(
        'Can not convert ${value.runtimeType} to requested type $T',
      );
    }

    return colDef.type.convertStringValueToProvidedType<T>(
      value,
      colDef.columnLength,
    );
  }

  /// Get data for all columns
  Map<String, Object?> assoc() {
    final result = <String, Object?>{};

    int colIndex = 0;

    for (final colDef in _colDefs) {
      result[colDef.name] = _values[colIndex];
      colIndex++;
    }

    return result;
  }

  /// Same as [assoc] but detects best dart type for columns, and converts string data into appropriate types
  Map<String, dynamic> typedAssoc() {
    final result = <String, dynamic>{};

    int colIndex = 0;

    for (final colDef in _colDefs) {
      final value = _values[colIndex];

      if (value == null) {
        result[colDef.name] = null;
        colIndex++;
        continue;
      }

      if (value is int &&
          colDef.type.intVal == mysqlColumnTypeTiny &&
          colDef.columnLength == 1) {
        result[colDef.name] = value > 0;
        colIndex++;
        continue;
      }

      if (value is! String) {
        result[colDef.name] = value;
        colIndex++;
        continue;
      }

      final dartType = colDef.type.getBestMatchDartType(colDef.columnLength);

      dynamic decodedValue;

      if (dartType == int) {
        decodedValue = int.parse(value);
      } else if (dartType == double) {
        decodedValue = double.parse(value);
      } else if (dartType == num) {
        decodedValue = num.parse(value);
      } else if (dartType == bool) {
        decodedValue = int.parse(value) > 0;
      } else {
        decodedValue = value;
      }

      result[colDef.name] = decodedValue;

      colIndex++;
    }

    return result;
  }
}

/// Represents column definition
class ResultSetColumn {
  String name;
  MySQLColumnType type;
  int length;

  ResultSetColumn({
    required this.name,
    required this.type,
    required this.length,
  });
}

/// Prepared statement class
class PreparedStmt {
  final MySQLPacketStmtPrepareOK _preparedPacket;
  final MySQLConnection _connection;
  final bool _iterable;

  PreparedStmt._({
    required MySQLPacketStmtPrepareOK preparedPacket,
    required MySQLConnection connection,
    required bool iterable,
  }) : _preparedPacket = preparedPacket,
       _connection = connection,
       _iterable = iterable;

  int get numOfParams => _preparedPacket.numOfParams;

  /// Executes this prepared statement with given [params]
  Future<IResultSet> execute(List<dynamic> params) async {
    if (numOfParams != params.length) {
      throw MySQLClientException(
        "Can not execute prepared stmt: number of passed params != number of prepared params",
      );
    }

    return _connection._executePreparedStmt(this, params, _iterable);
  }

  /// Deallocates this prepared statement
  ///
  /// Use this method to prevent memory leaks for long running connections
  /// All prepared statements are automatically deallocated by database when connection is closed
  Future<void> deallocate() {
    return _connection._deallocatePreparedStmt(this);
  }
}
