import 'dart:async';
import 'dart:typed_data';

import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/capabilities.dart';
import 'package:laconic_mysql/src/client/protocol/command/query_commands.dart';
import 'package:laconic_mysql/src/client/protocol/command/statement_commands.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';
import 'package:laconic_mysql/src/client/protocol/packet_decoder.dart';
import 'package:laconic_mysql/src/client/protocol/response/column_packets.dart';
import 'package:laconic_mysql/src/client/protocol/response/row_packets.dart';
import 'package:laconic_mysql/src/client/protocol/response/statement_packets.dart';
import 'package:laconic_mysql/src/client/protocol/response/status_packets.dart';
import 'package:laconic_mysql/src/client/result/prepared_statement.dart';
import 'package:laconic_mysql/src/client/result/result_row.dart';
import 'package:laconic_mysql/src/client/result/result_set.dart';
import 'package:laconic_mysql/src/client/transport/packet_transport.dart';

class MysqlCommandExecutor {
  final MysqlPacketTransport _transport;
  final Duration _timeout;
  final bool Function() _isConnected;
  final Future<void> Function() _waitUntilReady;
  final void Function() _onStarted;
  final void Function() _onCompleted;
  final void Function(Object error, StackTrace stackTrace) _onFatalError;

  Future<void> Function(Uint8List data)? _responseCallback;
  void Function(Object error, StackTrace stackTrace)? _pendingFailure;
  Timer? _pendingTimer;

  MysqlCommandExecutor({
    required MysqlPacketTransport transport,
    required Duration timeout,
    required bool Function() isConnected,
    required Future<void> Function() waitUntilReady,
    required void Function() onStarted,
    required void Function() onCompleted,
    required void Function(Object error, StackTrace stackTrace) onFatalError,
  }) : _transport = transport,
       _timeout = timeout,
       _isConnected = isConnected,
       _waitUntilReady = waitUntilReady,
       _onStarted = onStarted,
       _onCompleted = onCompleted,
       _onFatalError = onFatalError;

  Future<void> processResponse(Uint8List data) async {
    final callback = _responseCallback;
    if (callback == null) {
      throw const MysqlClientException(
        'Received a command response without a pending command',
      );
    }
    await callback(data);
  }

  Future<MysqlResultSet> execute(
    String query, {
    Map<String, Object?>? namedParameters,
    bool streaming = false,
  }) async {
    await _beginCommand('Can not execute query: connection closed');
    if (namedParameters != null && namedParameters.isNotEmpty) {
      _onCompleted();
      throw const MysqlClientException(
        'Named text-protocol parameters are not supported. '
        'Use prepare() and positional parameters instead.',
      );
    }

    return _runResultCommand(
      MysqlPacket(
        sequenceId: 0,
        payload: MysqlQueryCommand(query: query),
        payloadLength: 0,
      ),
      streaming: streaming,
      binary: false,
      allowMultipleResults: true,
    );
  }

  Future<MysqlPreparedStatement> prepare(
    String query, {
    bool streaming = false,
  }) async {
    await _beginCommand('Can not prepare statement: connection closed');

    final completer = Completer<MysqlPreparedStatement>();
    _registerPending(completer);
    var state = 0;
    var eofCount = 0;
    MysqlStatementPrepareOkPacket? preparedPacket;

    _responseCallback = (data) async {
      try {
        MysqlPacket? packet;
        if (state == 0) {
          packet = MysqlPacketDecoder.decodeStatementPrepareResponse(data);
          state = 1;
        } else {
          packet = null;
          if (MysqlPacketDecoder.detectPacketType(data) ==
              MysqlGenericPacketType.eof) {
            eofCount++;
            final prepared = preparedPacket!;
            final expectedEofCount =
                prepared.columnCount > 0 && prepared.parameterCount > 0 ? 2 : 1;
            if (eofCount == expectedEofCount) {
              state = 2;
              completer.complete(_createPreparedStatement(prepared, streaming));
              _onCompleted();
              return;
            }
          }
        }

        final payload = packet?.payload;
        if (payload is MysqlStatementPrepareOkPacket) {
          preparedPacket = payload;
          if (payload.columnCount == 0 && payload.parameterCount == 0) {
            completer.complete(_createPreparedStatement(payload, streaming));
            _onCompleted();
          }
        } else if (payload is MysqlErrorPacket) {
          _completeServerError(payload);
        } else if (payload != null) {
          _fatal(
            const MysqlClientException(
              'Unexpected COM_STMT_PREPARE response payload',
            ),
          );
        }
      } catch (error, stackTrace) {
        _onFatalError(error, stackTrace);
      }
    };

    _transport.sendPacket(
      MysqlPacket(
        sequenceId: 0,
        payload: MysqlStatementPrepareCommand(query: query),
        payloadLength: 0,
      ),
      expectResponse: true,
    );
    return _awaitCommand(completer);
  }

  void failPending(Object error, StackTrace stackTrace) {
    final failure = _pendingFailure;
    clearPending();
    failure?.call(error, stackTrace);
  }

  void clearPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingFailure = null;
    _responseCallback = null;
  }

  Future<void> _beginCommand(String disconnectedMessage) async {
    if (!_isConnected()) {
      throw MysqlClientException(disconnectedMessage);
    }
    await _waitUntilReady().timeout(_timeout);
    _onStarted();
  }

  MysqlPreparedStatement _createPreparedStatement(
    MysqlStatementPrepareOkPacket packet,
    bool streaming,
  ) {
    return MysqlPreparedStatement.internal(
      statementId: packet.statementId,
      parameterCount: packet.parameterCount,
      execute:
          (parameters) => _executePreparedStatement(
            packet.statementId,
            parameters,
            streaming,
          ),
      deallocate: () => _deallocatePreparedStatement(packet.statementId),
    );
  }

  Future<MysqlResultSet> _executePreparedStatement(
    int statementId,
    List<Object?> parameters,
    bool streaming,
  ) async {
    await _beginCommand(
      'Can not execute prepared statement: connection closed',
    );
    return _runResultCommand(
      MysqlPacket(
        sequenceId: 0,
        payload: MysqlStatementExecuteCommand(
          statementId: statementId,
          params: parameters,
        ),
        payloadLength: 0,
      ),
      streaming: streaming,
      binary: true,
      allowMultipleResults: false,
    );
  }

  Future<void> _deallocatePreparedStatement(int statementId) async {
    await _beginCommand('Can not deallocate statement: connection closed');
    _transport.sendPacket(
      MysqlPacket(
        sequenceId: 0,
        payload: MysqlStatementCloseCommand(statementId: statementId),
        payloadLength: 0,
      ),
    );
    _onCompleted();
  }

  Future<MysqlResultSet> _runResultCommand(
    MysqlPacket command, {
    required bool streaming,
    required bool binary,
    required bool allowMultipleResults,
  }) {
    final completer = Completer<MysqlResultSet>();
    var state = 0;
    var columnCount = 0;
    var columns = <MysqlColumnDefinitionPacket>[];
    var rowValues = <List<Object?>>[];
    MysqlStreamingResultSet? streamingResult;
    StreamSink<MysqlResultRow>? sink;
    MysqlResultSet? firstResult;
    MysqlResultSet? currentResult;

    _registerPending(
      completer,
      streamSink: () => streamingResult?.isCancelled == true ? null : sink,
    );

    _responseCallback = (data) async {
      try {
        MysqlPacket? packet;
        switch (state) {
          case 0:
            if (MysqlPacketDecoder.detectPacketType(data) ==
                MysqlGenericPacketType.ok) {
              final ok = MysqlPacketDecoder.decodeGeneric(data);
              if (streaming) {
                clearPending();
              }
              _onCompleted();
              completer.complete(
                MysqlCommandResult(ok.payload as MysqlOkPacket),
              );
              return;
            }
            packet = MysqlPacketDecoder.decodeColumnCount(data);
          case 1:
            packet = MysqlPacketDecoder.decodeColumnDefinition(data);
          case 2:
            packet = MysqlPacketDecoder.decodeGeneric(data);
            if (packet.isEof) {
              state = 3;
            } else if (packet.isError) {
              _completeServerError(packet.payload as MysqlErrorPacket);
              return;
            } else {
              _fatal(const MysqlClientException('Unexpected packet type'));
              return;
            }
          case 3:
            if (streaming) {
              final activeResult =
                  streamingResult ??= MysqlStreamingResultSet(
                    columns: columns,
                    onPause: _transport.pause,
                    onResume: _transport.resume,
                    onCancel: _transport.resume,
                  );
              final activeSink = sink ??= activeResult.sink;
              if (!completer.isCompleted) {
                completer.complete(activeResult);
              }

              if (MysqlPacketDecoder.detectPacketType(data) ==
                  MysqlGenericPacketType.eof) {
                state = 4;
                await activeSink.close();
                clearPending();
                _onCompleted();
                return;
              }

              packet = _decodeRow(data, columns, binary);
              final values = _rowValues(packet.payload);
              if (!activeResult.isCancelled) {
                activeSink.add(
                  MysqlResultRow(columns: columns, values: values),
                );
              }
              packet = null;
            } else {
              if (MysqlPacketDecoder.detectPacketType(data) ==
                  MysqlGenericPacketType.eof) {
                final result = MysqlBufferedResultSet(
                  columns: columns,
                  rows: rowValues,
                );
                if (currentResult == null) {
                  firstResult = result;
                } else {
                  currentResult!.next = result;
                }
                currentResult = result;

                final eof = MysqlPacketDecoder.decodeGeneric(data);
                final hasMore =
                    allowMultipleResults &&
                    (eof.payload as MysqlEofPacket).statusFlags &
                            mysqlServerFlagMoreResultsExists !=
                        0;
                if (hasMore) {
                  state = 0;
                  columnCount = 0;
                  columns = [];
                  rowValues = [];
                  return;
                }

                state = 4;
                _onCompleted();
                completer.complete(firstResult);
                return;
              }
              packet = _decodeRow(data, columns, binary);
            }
        }

        final payload = packet?.payload;
        if (payload is MysqlErrorPacket) {
          _completeServerError(payload);
        } else if (payload is MysqlOkPacket || payload is MysqlEofPacket) {
          return;
        } else if (payload is MysqlColumnCountPacket) {
          state = 1;
          columnCount = payload.columnCount.toInt();
        } else if (payload is MysqlColumnDefinitionPacket) {
          columns.add(payload);
          if (columns.length == columnCount) {
            state = 2;
          }
        } else if (payload is MysqlTextRowPacket) {
          rowValues.add(payload.values);
        } else if (payload is MysqlBinaryRowPacket) {
          rowValues.add(_rowValues(payload));
        } else if (payload != null) {
          _fatal(
            const MysqlClientException(
              'Unexpected result-set response payload',
            ),
          );
        }
      } catch (error, stackTrace) {
        _onFatalError(error, stackTrace);
      }
    };

    _transport.sendPacket(command, expectResponse: true);
    return _awaitCommand(completer, clearOnCompletion: !streaming);
  }

  MysqlPacket _decodeRow(
    Uint8List data,
    List<MysqlColumnDefinitionPacket> columns,
    bool binary,
  ) {
    return binary
        ? MysqlPacketDecoder.decodeBinaryRow(data, columns)
        : MysqlPacketDecoder.decodeTextRow(data, columns);
  }

  List<Object?> _rowValues(MysqlPacketPayload payload) {
    return switch (payload) {
      MysqlTextRowPacket(:final values) => values,
      MysqlBinaryRowPacket(:final values) => values,
      _ => throw const MysqlProtocolException('Expected a row packet'),
    };
  }

  void _completeServerError(MysqlErrorPacket error) {
    failPending(
      MysqlServerException(error.errorMessage, error.errorCode),
      StackTrace.current,
    );
    _onCompleted();
  }

  void _fatal(Object error) {
    _onFatalError(error, StackTrace.current);
  }

  void _registerPending<T>(
    Completer<T> completer, {
    StreamSink<MysqlResultRow>? Function()? streamSink,
  }) {
    _pendingTimer?.cancel();
    _pendingFailure = (error, stackTrace) {
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
    _pendingTimer = Timer(_timeout, () {
      _onFatalError(
        TimeoutException('MySQL command exceeded ${_timeout.inMilliseconds}ms'),
        StackTrace.current,
      );
    });
  }

  Future<T> _awaitCommand<T>(
    Completer<T> completer, {
    bool clearOnCompletion = true,
  }) async {
    try {
      return await completer.future.timeout(_timeout);
    } on TimeoutException catch (error, stackTrace) {
      _onFatalError(error, stackTrace);
      rethrow;
    } finally {
      if (clearOnCompletion) {
        clearPending();
      }
    }
  }
}
