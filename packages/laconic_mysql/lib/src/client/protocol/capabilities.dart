abstract final class MysqlCapabilities {
  static const clientLongPassword = 0x00000001;
  static const clientFoundRows = 0x00000002;
  static const clientLongFlag = 0x00000004;
  static const clientConnectWithDB = 0x00000008;
  static const clientNoSchema = 0x00000010;
  static const clientCompress = 0x00000020;
  static const clientODBC = 0x00000040;
  static const clientLocalFiles = 0x00000080;
  static const clientIgnoreSpace = 0x00000100;
  static const clientProtocol41 = 0x00000200;
  static const clientInteractive = 0x00000400;
  static const clientSsl = 0x00000800;
  static const clientIgnoreSigPipe = 0x00001000;
  static const clientTransactions = 0x00002000;
  static const clientReserved = 0x00004000;
  static const clientSecureConnection = 0x00008000;
  static const clientMultiStatements = 0x00010000;
  static const clientMultiResults = 0x00020000;
  static const clientPsMultiResults = 0x00040000;
  static const clientPluginAuth = 0x00080000;
  static const clientPluginAuthLenEncClientData = 0x00200000;
  static const clientDeprecateEOF = 0x01000000;
}

abstract final class MysqlServerStatus {
  static const moreResultsExists = 0x0008;
}
