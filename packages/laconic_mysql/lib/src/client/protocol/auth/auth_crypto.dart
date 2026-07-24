import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

List<int> sha1(List<int> data) => crypto.sha1.convert(data).bytes;

List<int> sha256(List<int> data) => crypto.sha256.convert(data).bytes;

Uint8List xor(List<int> aList, List<int> bList) {
  final a = Uint8List.fromList(aList);
  final b = Uint8List.fromList(bList);

  if (a.isEmpty || b.isEmpty) {
    throw ArgumentError.value(
      'Uint8List arguments',
      'aList/bList',
      'must not be empty',
    );
  }

  final length = a.length > b.length ? a.length : b.length;
  final result = Uint8List(length);
  for (var index = 0; index < length; index++) {
    final aValue = index < a.length ? a[index] : 0;
    final bValue = index < b.length ? b[index] : 0;
    result[index] = aValue ^ bValue;
  }
  return result;
}
