import 'dart:typed_data';

import 'models.dart';

final class ExtendedResult {
  const ExtendedResult(this.payload, this.diagnostics);
  final Uint8List? payload;
  final List<Diagnostic> diagnostics;
}

final class _Transaction {
  _Transaction(this.size, this.updatedUs);
  final int size;
  int updatedUs;
  final List<Uint8List> chunks = [];
}

/// One instance belongs to one capture session. Message IDs are not transaction keys.
final class ExtendedReassembler {
  final Map<(int, int, int), _Transaction> _pending = {};
  void reset([int? sop]) {
    if (sop == null) {
      _pending.clear();
    } else {
      _pending.removeWhere((key, _) => key.$1 == sop);
    }
  }

  ExtendedResult add({
    required int sop,
    required PdHeader header,
    required int extendedHeader,
    required Uint8List bytes,
    required int elapsedUs,
  }) {
    final size = bits(extendedHeader, 8, 0);
    final chunk = bits(extendedHeader, 14, 11);
    final chunked = extendedHeader & 0x8000 != 0;
    final request = extendedHeader & 0x400 != 0;
    final key = (sop, header.typeCode, header.powerRole);
    ExtendedResult fail(String code, String text) {
      _pending.remove(key);
      return ExtendedResult(null, [Diagnostic(code, text)]);
    }

    if (request) {
      return const ExtendedResult(null, [
        Diagnostic('chunkRequest', '请求分片，不包含数据正文', severity: Severity.info),
      ]);
    }
    if (size > 260) return fail('invalidExtendedSize', '扩展正文超过 260 字节');
    if (!chunked) {
      if (bytes.length < size) {
        return fail('truncatedExtended', '扩展正文不足 $size 字节');
      }
      return ExtendedResult(frozenBytes(bytes.take(size).toList()), const []);
    }
    final previous = _pending[key];
    if (previous != null && elapsedUs - previous.updatedUs > 2000000) {
      _pending.remove(key);
      if (chunk != 0) return fail('chunkTimeout', '分片事务已超时');
    }
    if (chunk == 0) {
      _pending[key] = _Transaction(size, elapsedUs);
    }
    final transaction = _pending[key];
    if (transaction == null) return fail('missingChunk', '缺少起始分片');
    if (size != transaction.size) {
      return fail('chunkSizeMismatch', '分片 Data Size 不一致');
    }
    if (chunk < transaction.chunks.length) {
      final old = transaction.chunks[chunk];
      if (hexBytes(old) == hexBytes(bytes)) {
        return const ExtendedResult(null, [
          Diagnostic('duplicateChunk', '重复分片已忽略', severity: Severity.info),
        ]);
      }
      return fail('conflictingChunk', '相同序号分片内容冲突');
    }
    if (chunk != transaction.chunks.length) {
      return fail('outOfOrderChunk', '分片缺失或乱序');
    }
    final remaining = size - chunk * 26;
    if (remaining < 0 || bytes.length < (remaining < 26 ? remaining : 26)) {
      return fail('truncatedChunk', '分片正文长度不足');
    }
    transaction.chunks.add(frozenBytes(bytes));
    transaction.updatedUs = elapsedUs;
    if ((chunk + 1) * 26 >= size) {
      _pending.remove(key);
      return ExtendedResult(
        frozenBytes(transaction.chunks.expand((x) => x).take(size).toList()),
        const [],
      );
    }
    return ExtendedResult(null, [
      Diagnostic(
        'awaitingChunks',
        '等待后续分片，已收到 ${chunk + 1} 片',
        severity: Severity.info,
      ),
    ]);
  }
}
