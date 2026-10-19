import 'dart:typed_data';

Uint8List frozenBytes(List<int> bytes) =>
    Uint8List.fromList(bytes).asUnmodifiableView();
String hexBytes(Iterable<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
String hexValue(int value, [int width = 8]) =>
    '0x${value.toRadixString(16).padLeft(width, '0').toUpperCase()}';
int bits(int value, int high, int low) =>
    (value >> low) & ((1 << (high - low + 1)) - 1);

Uint8List parseHex(String text) {
  final clean = text
      .trim()
      .replaceFirst(RegExp(r'^0[xX]'), '')
      .replaceAll(RegExp(r'\s+'), '');
  if (clean.isEmpty ||
      clean.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) {
    throw const FormatException('Raw 必须是偶数位十六进制字节');
  }
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

enum DecodeProfile { witrnCompat, standard }

enum CrcStatus { absent, unchecked, valid, invalid, unknown }

enum Severity { info, warning, error }

final class Diagnostic {
  const Diagnostic(this.code, this.message, {this.severity = Severity.warning});
  final String code;
  final String message;
  final Severity severity;
  @override
  String toString() => '$code: $message';
}

final class FieldNode {
  FieldNode(
    this.label, {
    this.value,
    this.unit,
    this.bitRange,
    this.raw,
    List<FieldNode> children = const [],
  }) : children = List.unmodifiable(children);
  final String label;
  final Object? value;
  final String? unit;
  final String? bitRange;
  final int? raw;
  final List<FieldNode> children;
  String get displayValue => '${value ?? ''}${unit == null ? '' : ' $unit'}';
}

final class PdHeader {
  const PdHeader(this.raw);
  final int raw;
  bool get extended => raw & 0x8000 != 0;
  int get objectCount => bits(raw, 14, 12);
  int get messageId => bits(raw, 11, 9);
  int get powerRole => bits(raw, 8, 8);
  int get revisionCode => bits(raw, 7, 6);
  int get dataRole => bits(raw, 5, 5);
  int get typeCode => bits(raw, 4, 0);
  String get revision => const ['1.0', '2.0', '3.x', 'Reserved'][revisionCode];
  String get messageType {
    final table = extended
        ? extendedTypes
        : objectCount == 0
        ? controlTypes
        : dataTypes;
    return table[typeCode] ?? 'Reserved ($typeCode)';
  }

  static const controlTypes = {
    1: 'GoodCRC',
    2: 'GotoMin',
    3: 'Accept',
    4: 'Reject',
    5: 'Ping',
    6: 'PS_RDY',
    7: 'Get_Source_Cap',
    8: 'Get_Sink_Cap',
    9: 'DR_Swap',
    10: 'PR_Swap',
    11: 'VCONN_Swap',
    12: 'Wait',
    13: 'Soft_Reset',
    14: 'Data_Reset',
    15: 'Data_Reset_Complete',
    16: 'Not_Supported',
    17: 'Get_Source_Cap_Extended',
    18: 'Get_Status',
    19: 'FR_Swap',
    20: 'Get_PPS_Status',
    21: 'Get_Country_Codes',
    22: 'Get_Sink_Cap_Extended',
    23: 'Get_Source_Info',
    24: 'Get_Revision',
  };
  static const dataTypes = {
    1: 'Source_Capabilities',
    2: 'Request',
    3: 'BIST',
    4: 'Sink_Capabilities',
    5: 'Battery_Status',
    6: 'Alert',
    7: 'Get_Country_Info',
    8: 'Enter_USB',
    9: 'EPR_Request',
    10: 'EPR_Mode',
    11: 'Source_Info',
    12: 'Revision',
    15: 'Vendor_Defined',
  };
  static const extendedTypes = {
    1: 'Source_Capabilities_Extended',
    2: 'Status',
    3: 'Get_Battery_Cap',
    4: 'Get_Battery_Status',
    5: 'Battery_Capabilities',
    6: 'Get_Manufacturer_Info',
    7: 'Manufacturer_Info',
    8: 'Security_Request',
    9: 'Security_Response',
    10: 'Firmware_Update_Request',
    11: 'Firmware_Update_Response',
    12: 'PPS_Status',
    13: 'Country_Info',
    14: 'Country_Codes',
    15: 'Sink_Capabilities_Extended',
    16: 'Extended_Control',
    17: 'EPR_Source_Capabilities',
    18: 'EPR_Sink_Capabilities',
    30: 'Vendor_Defined_Extended',
  };
}

enum PdoKind { fixed, battery, variable, pps, eprAvs, sprAvs, reserved }

final class PowerCapability {
  PowerCapability({
    required this.raw,
    required this.position,
    required this.kind,
    required this.fields,
    this.minVoltage,
    this.maxVoltage,
    this.maxCurrent,
    this.maxPower,
    this.currentAt15V,
    this.currentAt20V,
  });
  final int raw;
  final int position;
  final PdoKind kind;
  final List<FieldNode> fields;
  final double? minVoltage, maxVoltage, maxCurrent, maxPower;
  final double? currentAt15V, currentAt20V;
  String get summary {
    if (kind == PdoKind.reserved) return 'Reserved ${hexValue(raw)}';
    if (kind == PdoKind.sprAvs) {
      return 'SPR AVS · 15 V / $currentAt15V A · 20 V / $currentAt20V A';
    }
    final voltage = minVoltage == maxVoltage
        ? '${maxVoltage?.toStringAsFixed(2)} V'
        : '${minVoltage?.toStringAsFixed(2)}–${maxVoltage?.toStringAsFixed(2)} V';
    final limit = maxCurrent != null
        ? '${maxCurrent!.toStringAsFixed(2)} A'
        : '${maxPower?.toStringAsFixed(2)} W';
    return '${kind.name.toUpperCase()} · $voltage / $limit';
  }
}

final class PowerRequest {
  const PowerRequest({
    required this.raw,
    required this.position,
    this.capability,
    this.voltage,
    this.current,
    this.power,
    this.limit,
    this.giveback = false,
  });
  final int raw, position;
  final PowerCapability? capability;
  final double? voltage, current, power, limit;
  final bool giveback;
  String get summary => capability == null
      ? 'PDO #$position · 缺少源能力上下文'
      : 'PDO #$position · ${voltage == null ? '' : '${voltage!.toStringAsFixed(2)} V / '}'
            '${current != null ? '${current!.toStringAsFixed(2)} A' : '${power?.toStringAsFixed(2)} W'}';
}

final class PdMessage {
  PdMessage({
    required this.sopCode,
    required List<int> raw,
    required this.header,
    required List<FieldNode> fields,
    required List<Diagnostic> diagnostics,
    this.crcStatus = CrcStatus.absent,
    List<PowerCapability> capabilities = const [],
    this.request,
    List<int>? extendedPayload,
  }) : raw = frozenBytes(raw),
       fields = List.unmodifiable(fields),
       diagnostics = List.unmodifiable(diagnostics),
       capabilities = List.unmodifiable(capabilities),
       extendedPayload = extendedPayload == null
           ? null
           : frozenBytes(extendedPayload);
  final int sopCode;
  final Uint8List raw;
  final PdHeader? header;
  final List<FieldNode> fields;
  final List<Diagnostic> diagnostics;
  final List<PowerCapability> capabilities;
  final PowerRequest? request;
  final CrcStatus crcStatus;
  final Uint8List? extendedPayload;
  static const sopNames = {
    0xe0: 'SOP',
    0xc0: "SOP'",
    0xa0: "SOP''",
    0x80: "SOP'_DEBUG",
    0x60: "SOP''_DEBUG",
  };
  String get sop => sopNames[sopCode] ?? 'Unknown ${hexValue(sopCode, 2)}';
  String get type => header?.messageType ?? 'Malformed';
  bool get isGoodCrc => type == 'GoodCRC';
  bool get isSourceCapabilities =>
      type == 'Source_Capabilities' || type == 'EPR_Source_Capabilities';
  bool get isValid =>
      header != null && !diagnostics.any((d) => d.severity == Severity.error);
  String get powerRole => header == null
      ? '—'
      : sopCode == 0xe0
      ? (header!.powerRole == 1 ? 'Source' : 'Sink')
      : (header!.powerRole == 1 ? 'Cable Plug' : 'Port');
  String get dataRole => header == null || sopCode != 0xe0
      ? '—'
      : header!.dataRole == 1
      ? 'DFP'
      : 'UFP';
  String get summary =>
      request?.summary ??
      (capabilities.isNotEmpty
          ? capabilities.map((p) => p.summary).join('; ')
          : type);
}

final class TelemetrySample {
  TelemetrySample({
    required this.elapsedUs,
    required List<int> raw,
    this.voltage,
    this.current,
    this.measuredPower,
    this.cc1,
    this.cc2,
    this.dp,
    this.dn,
    this.temperature,
    this.ampHours,
    this.wattHours,
    this.recordSeconds = 0,
    this.runtimeSeconds = 0,
    this.group = 1,
  }) : raw = frozenBytes(raw);
  final int elapsedUs;
  final Uint8List raw;
  final double? voltage,
      current,
      cc1,
      cc2,
      dp,
      dn,
      temperature,
      ampHours,
      wattHours;
  final int recordSeconds, runtimeSeconds, group;
  final double? measuredPower;
  double? get power =>
      measuredPower ??
      (voltage == null || current == null ? null : (voltage! * current!).abs());
}

sealed class DecodedReport {
  const DecodedReport();
}

final class PdReport extends DecodedReport {
  const PdReport(this.message);
  final PdMessage message;
}

final class GeneralReport extends DecodedReport {
  const GeneralReport(this.sample);
  final TelemetrySample sample;
}

final class InvalidReport extends DecodedReport {
  InvalidReport(this.diagnostic, List<int> raw) : raw = frozenBytes(raw);
  final Diagnostic diagnostic;
  final Uint8List raw;
}

final class CaptureRecord {
  CaptureRecord({
    required this.id,
    required this.elapsedUs,
    required this.time,
    required this.message,
    required List<int> report,
    this.sourceTime,
  }) : report = frozenBytes(report);
  final int id, elapsedUs;
  final DateTime? time;
  final String? sourceTime;
  final PdMessage message;
  final Uint8List report;
  String get clockTime =>
      sourceTime ?? (time == null ? '—' : formatClock(time!.toLocal()));
  String get rawHex => hexBytes(
    report.take(
      report.length >= 2 && report[0] == 0xfe
          ? (report[1] + 2).clamp(0, report.length)
          : report.length,
    ),
  );
}

String formatClock(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}.'
    '${date.millisecond.toString().padLeft(3, '0')}';
String formatElapsed(int us) {
  final ms = us ~/ 1000;
  return '${(ms ~/ 60000).toString().padLeft(2, '0')}:'
      '${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}.'
      '${(ms % 1000).toString().padLeft(3, '0')}';
}
