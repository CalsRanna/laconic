import 'dart:typed_data';

import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';
import 'package:laconic_mysql/src/client/protocol/auth/auth_packets.dart';
import 'package:laconic_mysql/src/client/protocol/auth/handshake_packets.dart';
import 'package:laconic_mysql/src/client/protocol/response/column_packets.dart';
import 'package:laconic_mysql/src/client/protocol/response/row_packets.dart';
import 'package:laconic_mysql/src/client/protocol/response/statement_packets.dart';
import 'package:laconic_mysql/src/client/protocol/response/status_packets.dart';

enum MysqlGenericPacketType { ok, error, eof, other }

abstract final class MysqlPacketDecoder {
  static MysqlGenericPacketType detectPacketType(Uint8List buffer) {
    final header = MysqlPacket.decodePacketHeader(buffer);
    final type = buffer[4];

    if (type == 0x00 && header.payloadLength >= 7) {
      return MysqlGenericPacketType.ok;
    }
    if (type == 0xfe && header.payloadLength < 9) {
      return MysqlGenericPacketType.eof;
    }
    if (type == 0xff) {
      return MysqlGenericPacketType.error;
    }
    return MysqlGenericPacketType.other;
  }

  static MysqlPacket decodeInitialHandshake(Uint8List buffer) {
    final header = MysqlPacket.decodePacketHeader(buffer);
    return MysqlPacket(
      sequenceId: header.sequenceId,
      payloadLength: header.payloadLength,
      payload: MysqlInitialHandshakePacket.decode(
        Uint8List.sublistView(buffer, 4),
      ),
    );
  }

  static MysqlPacket decodeAuthSwitchRequest(Uint8List buffer) {
    final header = MysqlPacket.decodePacketHeader(buffer);
    if (buffer[4] != 0xfe) {
      throw MysqlProtocolException(
        'Can not decode AuthSwitchResponse packet: type is not 0xfe',
      );
    }

    return MysqlPacket(
      sequenceId: header.sequenceId,
      payloadLength: header.payloadLength,
      payload: MysqlAuthSwitchRequestPacket.decode(
        Uint8List.sublistView(buffer, 4),
      ),
    );
  }

  static MysqlPacket decodeGeneric(Uint8List buffer) {
    final header = MysqlPacket.decodePacketHeader(buffer);
    final payloadBuffer = Uint8List.sublistView(buffer, 4);
    final type = buffer[4];

    final MysqlPacketPayload payload;
    if (type == 0x00 && header.payloadLength >= 7) {
      payload = MysqlOkPacket.decode(payloadBuffer);
    } else if (type == 0xfe && header.payloadLength < 9) {
      payload = MysqlEofPacket.decode(payloadBuffer);
    } else if (type == 0xff) {
      payload = MysqlErrorPacket.decode(payloadBuffer);
    } else if (type == 0x01) {
      payload = MysqlExtraAuthDataPacket.decode(payloadBuffer);
    } else {
      throw MysqlProtocolException('Unsupported generic packet: $buffer');
    }

    return MysqlPacket(
      sequenceId: header.sequenceId,
      payloadLength: header.payloadLength,
      payload: payload,
    );
  }

  static MysqlPacket decodeColumnCount(Uint8List buffer) {
    final header = MysqlPacket.decodePacketHeader(buffer);
    final payloadBuffer = Uint8List.sublistView(buffer, 4);
    final type = buffer[4];

    final MysqlPacketPayload payload;
    if (type == 0x00) {
      payload = MysqlOkPacket.decode(payloadBuffer);
    } else if (type == 0xff) {
      payload = MysqlErrorPacket.decode(payloadBuffer);
    } else if (type == 0xfb) {
      throw MysqlProtocolException(
        'COM_QUERY_RESPONSE of type 0xfb is not implemented',
      );
    } else {
      payload = MysqlColumnCountPacket.decode(payloadBuffer);
    }

    return MysqlPacket(
      sequenceId: header.sequenceId,
      payloadLength: header.payloadLength,
      payload: payload,
    );
  }

  static MysqlPacket decodeColumnDefinition(Uint8List buffer) {
    final header = MysqlPacket.decodePacketHeader(buffer);
    return MysqlPacket(
      sequenceId: header.sequenceId,
      payloadLength: header.payloadLength,
      payload: MysqlColumnDefinitionPacket.decode(
        Uint8List.sublistView(buffer, 4),
      ),
    );
  }

  static MysqlPacket decodeTextRow(
    Uint8List buffer,
    List<MysqlColumnDefinitionPacket> columnDefinitions,
  ) {
    final header = MysqlPacket.decodePacketHeader(buffer);
    return MysqlPacket(
      sequenceId: header.sequenceId,
      payloadLength: header.payloadLength,
      payload: MysqlTextRowPacket.decode(
        Uint8List.sublistView(buffer, 4),
        columnDefinitions,
      ),
    );
  }

  static MysqlPacket decodeBinaryRow(
    Uint8List buffer,
    List<MysqlColumnDefinitionPacket> columnDefinitions,
  ) {
    final header = MysqlPacket.decodePacketHeader(buffer);
    return MysqlPacket(
      sequenceId: header.sequenceId,
      payloadLength: header.payloadLength,
      payload: MysqlBinaryRowPacket.decode(
        Uint8List.sublistView(buffer, 4),
        columnDefinitions,
      ),
    );
  }

  static MysqlPacket decodeStatementPrepareResponse(Uint8List buffer) {
    final header = MysqlPacket.decodePacketHeader(buffer);
    final payloadBuffer = Uint8List.sublistView(buffer, 4);
    final type = buffer[4];

    final MysqlPacketPayload payload;
    if (type == 0x00) {
      payload = MysqlStatementPrepareOkPacket.decode(payloadBuffer);
    } else if (type == 0xff) {
      payload = MysqlErrorPacket.decode(payloadBuffer);
    } else {
      throw MysqlProtocolException(
        'Unexpected header type while decoding COM_STMT_PREPARE response: '
        '$header',
      );
    }

    return MysqlPacket(
      sequenceId: header.sequenceId,
      payloadLength: header.payloadLength,
      payload: payload,
    );
  }
}

extension MysqlDecodedPacket on MysqlPacket {
  bool get isOk => payload is MysqlOkPacket;

  bool get isError => payload is MysqlErrorPacket;

  bool get isEof {
    final packetPayload = payload;
    if (packetPayload is MysqlEofPacket) {
      return true;
    }
    return packetPayload is MysqlOkPacket &&
        packetPayload.header == 0xfe &&
        payloadLength < 9;
  }
}
