import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/core/extended_reassembler.dart';

void main() {
  late ExtendedReassembler assembler;
  setUp(() => assembler = ExtendedReassembler());
  ExtendedResult add(
    int chunk, {
    int sop = 0xe0,
    int type = 8,
    int size = 30,
    int time = 0,
    bool request = false,
    List<int>? body,
  }) => assembler.add(
    sop: sop,
    header: PdHeader(0xf180 | type),
    extendedHeader: 0x8000 | (chunk << 11) | size | (request ? 0x400 : 0),
    bytes: Uint8List.fromList(body ?? List.filled(chunk == 0 ? 26 : 6, chunk)),
    elapsedUs: time,
  );
  test('two chunks trim padding, duplicate tolerated, request excluded', () {
    expect(add(0).payload, isNull);
    expect(add(1, request: true).diagnostics.single.code, 'chunkRequest');
    final complete = add(1).payload!;
    expect(complete.length, 30);
    expect(complete.take(26).every((b) => b == 0), isTrue);
    expect(complete.last, 1);
  });
  test('missing, wrong channel, wrong type, out of order, size mismatch and timeout', () {
    expect(add(1).diagnostics.single.code, 'missingChunk');
    add(0);
    expect(add(1, sop: 0xc0).diagnostics.single.code, 'missingChunk');
    expect(add(1, type: 9).diagnostics.single.code, 'missingChunk');
    expect(add(2).diagnostics.single.code, 'outOfOrderChunk');
    add(0);
    expect(add(1, size: 31).diagnostics.single.code, 'chunkSizeMismatch');
    add(0);
    expect(add(1, time: 3000000).diagnostics.single.code, 'chunkTimeout');
  });
  test('reset discards old transactions and invalid size is rejected', () {
    add(0);
    assembler.reset();
    expect(add(1).diagnostics.single.code, 'missingChunk');
    expect(add(0, size: 511).diagnostics.single.code, 'invalidExtendedSize');
    expect(add(0, body: [0]).diagnostics.single.code, 'truncatedChunk');
  });
  test('unchunked message trims padding and incomplete data is reported', () {
    final result = assembler.add(
      sop: 0xe0,
      header: const PdHeader(0x908c),
      extendedHeader: 4,
      bytes: Uint8List.fromList([1, 2, 3, 4, 0, 0]),
      elapsedUs: 0,
    );
    expect(result.payload, [1, 2, 3, 4]);
  });
}
