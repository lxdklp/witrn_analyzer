import 'dart:typed_data';

import 'extended_reassembler.dart';
import 'models.dart';
import 'payload_decoder.dart';
import 'power_decoder.dart';

/// Pure Dart stateful decoder; create a fresh instance for each session or import.
final class PdDecoder {
  PdDecoder({this.profile = DecodeProfile.witrnCompat, this.verifyCrc = false});
  final DecodeProfile profile;
  final bool verifyCrc;
  final Map<(int, int), List<PowerCapability>> _sources = {};
  final ExtendedReassembler _extended = ExtendedReassembler();
  void reset() {
    _sources.clear();
    _extended.reset();
  }

  DecodedReport decode(List<int> input, {int elapsedUs = 0}) {
    final report = Uint8List.fromList(input);
    InvalidReport invalid(String code, String text) =>
        InvalidReport(Diagnostic(code, text, severity: Severity.error), report);
    if (report.isEmpty) return invalid('emptyReport', '空报告');
    if (report.length > 64) {
      return invalid('oversizeReport', 'WITRN 报告超过 64 字节');
    }
    if (report[0] == 0xff) {
      if (report.length != 64) {
        return invalid('truncatedTelemetry', '电参报告必须为 64 字节');
      }
      final data = ByteData.sublistView(report);
      double? float(int offset) {
        final value = data.getFloat32(offset, Endian.little);
        return value.isFinite ? value : null;
      }

      final temperature = float(42);

      return GeneralReport(
        TelemetrySample(
          elapsedUs: elapsedUs,
          raw: report,
          voltage: float(46),
          current: float(50)?.abs(),
          cc1: report[55] / 10,
          cc2: report[56] / 10,
          dp: float(30),
          dn: float(34),
          // Values below the K2 NTC's -20 °C lower limit are not readings.
          temperature: temperature != null && temperature >= -20
              ? temperature
              : null,
          ampHours: float(14),
          wattHours: float(18),
          recordSeconds: data.getUint32(22, Endian.little),
          runtimeSeconds: data.getUint32(26, Endian.little),
          group: report[54] + 1,
        ),
      );
    }
    if (report[0] != 0xfe) {
      return invalid('unknownReportType', '未知报告首字节 ${hexValue(report[0], 2)}');
    }
    if (report.length < 3 ||
        report[1] < 3 ||
        report[1] > 62 ||
        report[1] + 2 > report.length) {
      return invalid('invalidReportLength', 'FE 报告长度字段不合法或报告被截断');
    }
    return PdReport(
      _decodePd(report[2], report.sublist(3, report[1] + 2), elapsedUs),
    );
  }

  PdMessage _decodePd(int sop, Uint8List raw, int elapsedUs) {
    final diagnostics = <Diagnostic>[];
    final fields = <FieldNode>[];
    final header = PdHeader(
      ByteData.sublistView(raw).getUint16(0, Endian.little),
    );
    var crc = CrcStatus.absent;
    var capabilities = <PowerCapability>[];
    PowerRequest? request;
    Uint8List? extendedPayload;
    PdMessage result() => PdMessage(
      sopCode: sop,
      raw: raw,
      header: header,
      fields: fields,
      diagnostics: diagnostics,
      crcStatus: crc,
      capabilities: capabilities,
      request: request,
      extendedPayload: extendedPayload,
    );
    if (!PdMessage.sopNames.containsKey(sop)) {
      diagnostics.add(const Diagnostic('unknownSop', '未知 SOP，保留原始通道码'));
    }
    fields.add(
      FieldNode(
        'Message Header',
        value: hexValue(header.raw, 4),
        raw: header.raw,
        children: [
          FieldNode('Extended', value: header.extended, bitRange: '15'),
          FieldNode(
            'Number of Data Objects',
            value: header.objectCount,
            bitRange: '14:12',
          ),
          FieldNode('Message ID', value: header.messageId, bitRange: '11:9'),
          FieldNode(
            sop == 0xe0 ? 'Port Power Role' : 'Cable Plug',
            value: header.powerRole,
            bitRange: '8',
          ),
          FieldNode(
            'Specification Revision',
            value: header.revision,
            bitRange: '7:6',
          ),
          FieldNode(
            sop == 0xe0 ? 'Port Data Role' : 'Reserved',
            value: header.dataRole,
            bitRange: '5',
          ),
          FieldNode(
            'Message Type',
            value: header.messageType,
            raw: header.typeCode,
            bitRange: '4:0',
          ),
        ],
      ),
    );
    final end = 2 + header.objectCount * 4;
    if (raw.length < end) {
      diagnostics.add(
        Diagnostic(
          'truncatedPayload',
          '头部要求 $end 字节，实际 ${raw.length} 字节',
          severity: Severity.error,
        ),
      );
      return result();
    }
    if (raw.length == end + 4) {
      crc = verifyCrc
          ? (crc32(raw.sublist(0, end)) ==
                    ByteData.sublistView(raw).getUint32(end, Endian.little)
                ? CrcStatus.valid
                : CrcStatus.invalid)
          : CrcStatus.unchecked;
      if (crc == CrcStatus.invalid) {
        diagnostics.add(
          const Diagnostic('invalidCrc', 'CRC 校验失败', severity: Severity.error),
        );
      }
      fields.add(FieldNode('CRC', value: hexBytes(raw.sublist(end))));
    } else if (raw.length != end) {
      crc = CrcStatus.unknown;
      diagnostics.add(
        const Diagnostic('trailingBytes', '尾部长度不符合 4 字节 CRC，保留原文'),
      );
    }
    final canUpdate =
        crc != CrcStatus.invalid && PdMessage.sopNames.containsKey(sop);
    if (!header.extended && header.objectCount == 0) {
      if ([10, 13, 14, 19].contains(header.typeCode) && canUpdate) {
        _sources.removeWhere((key, _) => key.$1 == sop);
        _extended.reset(sop);
      }
      return result();
    }
    final data = ByteData.sublistView(raw);
    if (header.extended) {
      if (end < 4) {
        diagnostics.add(
          const Diagnostic(
            'missingExtendedHeader',
            '缺少扩展消息头',
            severity: Severity.error,
          ),
        );
        return result();
      }
      final ext = data.getUint16(2, Endian.little);
      fields.add(
        FieldNode(
          'Extended Message Header',
          value: hexValue(ext, 4),
          children: [
            FieldNode('Chunked', value: bits(ext, 15, 15) == 1, bitRange: '15'),
            FieldNode(
              'Chunk Number',
              value: bits(ext, 14, 11),
              bitRange: '14:11',
            ),
            FieldNode(
              'Request Chunk',
              value: bits(ext, 10, 10) == 1,
              bitRange: '10',
            ),
            FieldNode(
              'Data Size',
              value: bits(ext, 8, 0),
              unit: 'bytes',
              bitRange: '8:0',
            ),
          ],
        ),
      );
      if (canUpdate) {
        final assembly = _extended.add(
          sop: sop,
          header: header,
          extendedHeader: ext,
          bytes: raw.sublist(4, end),
          elapsedUs: elapsedUs,
        );
        diagnostics.addAll(assembly.diagnostics);
        extendedPayload = assembly.payload;
      }
      if (extendedPayload case final payload?) {
        if ([17, 18].contains(header.typeCode)) {
          if (payload.length % 4 != 0) {
            diagnostics.add(
              const Diagnostic(
                'invalidPdoLength',
                '扩展 PDO 不是 4 字节的整数倍',
                severity: Severity.error,
              ),
            );
          }
          final view = ByteData.sublistView(payload);
          capabilities = [
            for (var i = 0; i + 4 <= payload.length; i += 4)
              decodeCapability(
                view.getUint32(i, Endian.little),
                i ~/ 4 + 1,
                profile,
                sink: header.typeCode == 18,
              ),
          ];
          if (header.typeCode == 17 && payload.length % 4 == 0) {
            _sources[(sop, header.powerRole)] = capabilities;
          }
        } else {
          fields.addAll(
            decodeExtendedPayload(header.typeCode, payload, diagnostics),
          );
        }
        fields.add(FieldNode('重组正文', value: hexBytes(payload)));
      } else {
        fields.add(FieldNode('分片正文', value: hexBytes(raw.sublist(4, end))));
      }
    } else {
      final objects = [
        for (var i = 2; i < end; i += 4) data.getUint32(i, Endian.little),
      ];
      switch (header.typeCode) {
        case 1 || 4:
          capabilities = [
            for (var i = 0; i < objects.length; i++)
              decodeCapability(
                objects[i],
                i + 1,
                profile,
                sink: header.typeCode == 4,
              ),
          ];
          if (header.typeCode == 1 && canUpdate) {
            _sources[(sop, header.powerRole)] = capabilities;
          }
        case 2 || 9:
          final position = bits(objects.first, 31, 28);
          final source = _sources[(sop, 1 - header.powerRole)];
          PowerCapability? pdo;
          if (position == 0) {
            diagnostics.add(
              const Diagnostic('invalidObjectPosition', 'RDO 对象位置必须从 1 开始'),
            );
          } else if (header.typeCode == 9) {
            if (objects.length < 2) {
              diagnostics.add(
                const Diagnostic(
                  'missingCopyOfPdo',
                  'EPR Request 缺少 Copy of PDO',
                  severity: Severity.error,
                ),
              );
            } else {
              pdo = decodeCapability(objects[1], position, profile);
              fields.add(
                FieldNode(
                  'Copy of PDO',
                  value: pdo.summary,
                  raw: pdo.raw,
                  children: pdo.fields,
                ),
              );
            }
          } else if (source == null) {
            diagnostics.add(
              const Diagnostic(
                'missingContext',
                '此会话尚未收到对应通道的 Source Capabilities',
              ),
            );
          } else if (position > source.length) {
            diagnostics.add(
              const Diagnostic('invalidObjectPosition', 'RDO 超出最近源能力的 PDO 数量'),
            );
          } else {
            pdo = source[position - 1];
          }
          request = decodeRequest(objects.first, pdo, profile);
          fields.add(
            FieldNode(
              'RDO',
              value: request.summary,
              raw: request.raw,
              children: requestFields(request),
            ),
          );
        default:
          fields.addAll(
            decodeDataPayload(header.typeCode, sop, objects, diagnostics),
          );
      }
    }
    for (final pdo in capabilities) {
      fields.add(
        FieldNode(
          'PDO ${pdo.position}',
          value: pdo.summary,
          raw: pdo.raw,
          children: pdo.fields,
        ),
      );
    }
    return result();
  }
}

int crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc >>> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
