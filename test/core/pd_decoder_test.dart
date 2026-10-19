import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/core/pd_decoder.dart';
import 'package:witrn_analyzer/core/power_decoder.dart';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/porting_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  List<DecodedReport> decode(
    String id, {
    DecodeProfile profile = DecodeProfile.witrnCompat,
    bool crc = false,
  }) {
    final data = (fixture['cases'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((v) => v['id'] == id);
    final decoder = PdDecoder(profile: profile, verifyCrc: crc);
    return (data['reports_hex'] as List<dynamic>)
        .cast<String>()
        .map((hex) => decoder.decode(parseHex(hex)))
        .toList();
  }

  PdMessage message(
    String id, {
    DecodeProfile profile = DecodeProfile.witrnCompat,
    bool crc = false,
  }) => (decode(id, profile: profile, crc: crc).last as PdReport).message;
  test('reference GoodCRC and immutable original bytes', () {
    final m = message('goodcrc');
    expect(m.type, 'GoodCRC');
    expect(m.header!.revision, '3.x');
    expect(m.powerRole, 'Sink');
    expect(m.dataRole, 'UFP');
    expect(m.header!.messageId, 0);
    expect(m.header!.objectCount, 0);
    expect(hexBytes(m.raw), '8100');
    expect(() => m.raw[0] = 0, throwsUnsupportedError);
  });
  test('fixed PDO and context-dependent RDO', () {
    final result = decode('fixed_pdo_then_request').cast<PdReport>();
    final pdo = result.first.message.capabilities.single;
    expect(pdo.maxVoltage, 5);
    expect(pdo.maxCurrent, 3);
    final rdo = result.last.message.request!;
    expect(rdo.position, 1);
    expect(rdo.current, 2);
    expect(rdo.limit, 3);
  });
  test('PPS request and both private bit profiles', () {
    final result = decode('pps_pdo_then_request').cast<PdReport>();
    final pdo = result.first.message.capabilities.last;
    expect(pdo.minVoltage, closeTo(3.3, 1e-6));
    expect(pdo.maxVoltage, 11);
    expect(pdo.maxCurrent, 3);
    expect(result.last.message.request!.voltage, 9);
    expect(result.last.message.request!.current, 2);
    expect(
      message('pps_private_bit25').capabilities.single.maxVoltage,
      closeTo(36.6, 1e-6),
    );
    expect(
      message(
        'pps_private_bit25',
        profile: DecodeProfile.standard,
      ).capabilities.single.maxVoltage,
      11,
    );
  });
  test('unknown SOP and missing or invalid RDO context stay visible', () {
    for (final item in [
      ('unknown_sop', 'unknownSop'),
      ('request_without_context', 'missingContext'),
      ('invalid_rdo_position_zero', 'invalidObjectPosition'),
    ]) {
      expect(
        message(item.$1).diagnostics.map((d) => d.code),
        contains(item.$2),
      );
    }
    expect(message('unknown_sop').sop, contains('Unknown'));
    expect(message('request_without_context').type, 'Request');
    expect(message('invalid_rdo_position_zero').request!.capability, isNull);
  });
  test('telemetry offsets and absolute current match all fixture values', () {
    final t =
        (decode('general_negative_current').single as GeneralReport).sample;
    expect(t.voltage, 5);
    expect(t.current, 2);
    expect(t.power, 10);
    expect(t.cc1, 1.2);
    expect(t.cc2, 2.3);
    expect(t.dp, closeTo(.6, 1e-6));
    expect(t.dn, closeTo(.7, 1e-6));
    expect(t.temperature, 25);
    expect(t.ampHours, 1.5);
    expect(t.wattHours, 7.5);
    expect(t.recordSeconds, 3661);
    expect(t.runtimeSeconds, 123);
    expect(t.group, 1);
  });
  test(
    'temperatures below -20 °C are omitted while the boundary remains valid',
    () {
      final raw = parseHex(
        'FF550592C53B0E491A34000050000161C33F361523413F1E000005000000'
        'EF2FB23E25A0D13E0000C8410000C8C2000000000000000000200008800600205698',
      );
      final decoder = PdDecoder();
      final sample = (decoder.decode(raw) as GeneralReport).sample;
      expect(sample.temperature, isNull);
      expect(sample.raw.length, 64);
      expect(sample.raw.sublist(42, 46), [0, 0, 0xc8, 0xc2]);

      final data = ByteData.sublistView(raw);
      for (final (value, expected) in [
        (-20.1, null),
        (-20.0, -20.0),
        (-10.0, -10.0),
      ]) {
        data.setFloat32(42, value, Endian.little);
        final sample = (decoder.decode(raw) as GeneralReport).sample;
        expect(sample.temperature, expected);
      }
    },
  );
  test(
    'CRC is optional, exact raw bytes retained, bad CRC cannot seed context',
    () {
      expect(message('pd_with_crc').crcStatus, CrcStatus.unchecked);
      expect(message('pd_with_crc', crc: true).crcStatus, CrcStatus.valid);
      expect(message('pd_bad_crc', crc: true).crcStatus, CrcStatus.invalid);
      expect(hexBytes(message('pd_with_crc').raw), 'A1112C910100DA2E2C31');
      final decoder = PdDecoder(verifyCrc: true);
      decoder.decode(parseHex('FE0BE0A1112C910100DA2E2C30'));
      final request =
          (decoder.decode(parseHex('FE07E082122C210310')) as PdReport).message;
      expect(
        request.diagnostics.map((d) => d.code),
        contains('missingContext'),
      );
    },
  );
  test(
    'malformed envelope, unknown report and truncated PD payload are diagnosed',
    () {
      expect(
        (decode('unknown_frame_type').single as InvalidReport).diagnostic.code,
        'unknownReportType',
      );
      final decoder = PdDecoder();
      for (final bytes in [
        <int>[],
        [0xfe],
        [0xfe, 2, 0xe0, 0],
        [0xfe, 63, 0xe0],
        List<int>.filled(65, 0),
      ]) {
        expect(decoder.decode(bytes), isA<InvalidReport>());
      }
      final truncated =
          (decoder.decode(parseHex('FE03E0A111')) as PdReport).message;
      expect(truncated.isValid, isFalse);
      expect(truncated.diagnostics.first.code, 'truncatedPayload');
      final nonfinite = Uint8List(64)..[0] = 0xff;
      ByteData.sublistView(nonfinite).setFloat32(46, double.nan, Endian.little);
      expect(
        (decoder.decode(nonfinite) as GeneralReport).sample.voltage,
        isNull,
      );
    },
  );
  test(
    'message dispatch distinguishes control, data, extended and all SOP roles',
    () {
      expect(const PdHeader(0x81).messageType, 'GoodCRC');
      expect(const PdHeader(0x1081).messageType, 'Source_Capabilities');
      expect(
        const PdHeader(0x9081).messageType,
        'Source_Capabilities_Extended',
      );
      for (final code in PdMessage.sopNames.keys) {
        final m =
            (PdDecoder().decode([0xfe, 3, code, 0xa1, 1]) as PdReport).message;
        expect(m.sop, PdMessage.sopNames[code]);
        if (code != 0xe0) {
          expect(m.powerRole, 'Cable Plug');
          expect(m.dataRole, '—');
        }
      }
    },
  );
  test('battery, variable and AVS unit conversions', () {
    final battery = decodeCapability(
      0x40000000 | (400 << 20) | (100 << 10) | 240,
      1,
      DecodeProfile.standard,
    );
    expect(battery.kind, PdoKind.battery);
    expect(battery.minVoltage, 5);
    expect(battery.maxVoltage, 20);
    expect(battery.maxPower, 60);
    expect(
      decodeRequest(
        0x10000000 | (120 << 10) | 240,
        battery,
        DecodeProfile.standard,
      ).power,
      30,
    );
    final variable = decodeCapability(
      0x80000000 | (400 << 20) | (100 << 10) | 300,
      1,
      DecodeProfile.standard,
    );
    expect(variable.maxCurrent, 3);
    final avs = decodeCapability(
      0xd0000000 | (280 << 17) | (150 << 8) | 140,
      1,
      DecodeProfile.standard,
    );
    expect(avs.maxVoltage, 28);
    expect(avs.minVoltage, 15);
    expect(avs.maxPower, 140);
    expect(
      decodeRequest(
        0x10000000 | (800 << 9) | 60,
        avs,
        DecodeProfile.standard,
      ).voltage,
      20,
    );
  });
  test('soft reset and role swap invalidate channel context', () {
    for (final control in [10, 13]) {
      final decoder = PdDecoder();
      decoder.decode(parseHex('FE07E0A1112C910100'));
      decoder.decode([0xfe, 3, 0xe0, 0x80 | control, 0]);
      final m =
          (decoder.decode(parseHex('FE07E082122C210310')) as PdReport).message;
      expect(m.request!.capability, isNull);
    }
  });
}
