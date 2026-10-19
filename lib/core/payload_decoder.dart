import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';
import 'vendor_ids.dart';

FieldNode _field(
  int raw,
  String label,
  int high,
  int low, {
  Map<int, String>? names,
  double? scale,
  String? unit,
}) {
  final value = bits(raw, high, low);
  return FieldNode(
    label,
    raw: value,
    bitRange: '$high:$low',
    unit: unit,
    value: names == null
        ? (scale == null ? value : value * scale)
        : names[value] ?? 'Reserved ($value)',
  );
}

String vendorName(int id) =>
    '${hexValue(id, 4)} · ${vendorIds[id] ?? 'Unknown vendor'}';

List<FieldNode> decodeDataPayload(
  int type,
  int sop,
  List<int> objects,
  List<Diagnostic> diagnostics,
) {
  final raw = objects.first;
  final fields = <FieldNode>[];
  switch (type) {
    case 3:
      fields.add(
        _field(
          raw,
          'BIST Mode',
          31,
          28,
          names: {
            5: 'Carrier Mode',
            8: 'Test Data',
            9: 'Shared Test Entry',
            10: 'Shared Test Exit',
          },
        ),
      );
    case 5:
      fields.addAll([
        _field(raw, 'Battery Present Capacity', 31, 16, scale: .1, unit: 'Wh'),
        _field(raw, 'Invalid Battery Reference', 8, 8),
        _field(raw, 'Battery Present', 9, 9),
        _field(
          raw,
          'Charging Status',
          11,
          10,
          names: {0: 'Charging', 1: 'Discharging', 2: 'Idle'},
        ),
      ]);
    case 6:
      fields.addAll([
        for (final item in [
          (25, 'Battery Status Changed'),
          (26, 'OCP'),
          (27, 'OTP'),
          (28, 'Operating Condition Change'),
          (29, 'Source Input Change'),
          (30, 'OVP'),
          (31, 'Extended Alert'),
        ])
          _field(raw, item.$2, item.$1, item.$1),
        _field(raw, 'Fixed Batteries', 23, 20),
        _field(raw, 'Hot Swappable Batteries', 19, 16),
        _field(raw, 'Extended Alert Event', 3, 0),
      ]);
    case 7:
      fields.add(
        FieldNode(
          'Country Code',
          value: String.fromCharCodes([bits(raw, 31, 24), bits(raw, 23, 16)]),
        ),
      );
    case 8:
      fields.addAll([
        _field(
          raw,
          'USB Mode',
          30,
          28,
          names: {0: 'USB 2.0', 1: 'USB 3.2', 2: 'USB4'},
        ),
        _field(raw, 'USB4 DRD', 26, 26),
        _field(raw, 'USB3 DRD', 25, 25),
        _field(raw, 'Cable Speed', 23, 21),
        _field(
          raw,
          'Cable Type',
          20,
          19,
          names: {0: 'Passive', 1: 'Retimer', 2: 'Redriver', 3: 'Optical'},
        ),
        _field(
          raw,
          'Cable Current',
          18,
          17,
          names: {0: 'No VBUS', 2: '3 A', 3: '5 A'},
        ),
        for (final item in [
          (16, 'PCIe'),
          (15, 'DisplayPort'),
          (14, 'Thunderbolt'),
          (13, 'Host Present'),
        ])
          _field(raw, item.$2, item.$1, item.$1),
      ]);
    case 10:
      fields.addAll([
        _field(
          raw,
          'EPR Action',
          31,
          24,
          names: {
            1: 'Enter',
            2: 'Enter Acknowledged',
            3: 'Enter Succeeded',
            4: 'Enter Failed',
            5: 'Exit',
          },
        ),
        _field(raw, 'EPR Data', 23, 16),
      ]);
    case 11:
      fields.addAll([
        _field(raw, 'Port Type', 31, 31),
        _field(raw, 'Maximum PDP', 23, 16, unit: 'W'),
        _field(raw, 'Present PDP', 15, 8, unit: 'W'),
        _field(raw, 'Reported PDP', 7, 0, unit: 'W'),
      ]);
    case 12:
      fields.addAll([
        _field(raw, 'Revision.major', 31, 28),
        _field(raw, 'Revision.minor', 27, 24),
        _field(raw, 'Version.major', 23, 20),
        _field(raw, 'Version.minor', 19, 16),
      ]);
    case 15:
      return _vdm(sop, objects, diagnostics);
    default:
      diagnostics.add(
        const Diagnostic('rawPayload', '未定义载荷按原始对象显示', severity: Severity.info),
      );
  }
  return [
    for (var i = 0; i < objects.length; i++)
      FieldNode(
        'Data Object ${i + 1}',
        value: hexValue(objects[i]),
        raw: objects[i],
        children: i == 0 ? fields : const [],
      ),
  ];
}

List<FieldNode> _vdm(int sop, List<int> objects, List<Diagnostic> diagnostics) {
  final raw = objects.first;
  final structured = bits(raw, 15, 15) == 1;
  final command = bits(raw, 4, 0);
  final ack = bits(raw, 7, 6) == 1;
  final fields = <FieldNode>[
    FieldNode(
      'VDM Header',
      value: structured ? 'Structured' : 'Unstructured',
      raw: raw,
      children: [
        FieldNode(
          'SVID / VID',
          value: vendorName(bits(raw, 31, 16)),
          bitRange: '31:16',
        ),
        _field(raw, 'VDM Type', 15, 15),
        if (structured) ...[
          _field(raw, 'Version.major', 14, 13),
          _field(raw, 'Version.minor', 12, 11),
          _field(raw, 'Object Position', 10, 8),
          _field(
            raw,
            'Command Type',
            7,
            6,
            names: {0: 'Initiator', 1: 'ACK', 2: 'NAK', 3: 'BUSY'},
          ),
          _field(
            raw,
            'Command',
            4,
            0,
            names: {
              1: 'Discover Identity',
              2: 'Discover SVIDs',
              3: 'Discover Modes',
              4: 'Enter Mode',
              5: 'Exit Mode',
              6: 'Attention',
            },
          ),
        ],
      ],
    ),
  ];
  if (structured && command == 1 && ack && objects.length < 4) {
    diagnostics.add(
      const Diagnostic(
        'truncatedIdentity',
        'Discover Identity ACK 缺少 Identity / Cert / Product VDO',
      ),
    );
  }
  for (var i = 1; i < objects.length; i++) {
    final value = objects[i];
    var label = 'VDO $i';
    final children = <FieldNode>[];
    if (structured && command == 2 && ack) {
      children.addAll([
        FieldNode('SVID ${i * 2 - 1}', value: vendorName(bits(value, 31, 16))),
        FieldNode('SVID ${i * 2}', value: vendorName(bits(value, 15, 0))),
      ]);
    } else if (structured && command == 1 && ack) {
      if (i == 1) {
        label = 'ID Header VDO';
        children.addAll([
          _field(value, 'USB Host Capable', 31, 31),
          _field(value, 'USB Device Capable', 30, 30),
          _field(
            value,
            sop == 0xe0 ? 'Product Type (UFP)' : 'Product Type (Cable)',
            29,
            27,
          ),
          _field(value, 'Modal Operation', 26, 26),
          _field(value, 'Product Type (DFP)', 25, 23),
          _field(value, 'Connector Type', 22, 21),
          FieldNode(
            'USB Vendor ID',
            value: vendorName(bits(value, 15, 0)),
            bitRange: '15:0',
          ),
        ]);
      } else if (i == 2) {
        label = 'Cert Stat VDO';
        children.add(FieldNode('XID', value: value));
      } else if (i == 3) {
        label = 'Product VDO';
        children.addAll([
          _field(value, 'USB Product ID', 31, 16),
          _field(value, 'bcdDevice', 15, 0),
        ]);
      } else if (sop != 0xe0 && i == 4) {
        label = 'Cable / VPD VDO';
        children.addAll([
          _field(value, 'HW Version', 31, 28),
          _field(value, 'FW Version', 27, 24),
          _field(value, 'VDO Version', 23, 21),
          _field(value, 'Connector Type', 19, 18),
          _field(value, 'Cable Latency', 16, 13),
          _field(value, 'Cable Termination', 12, 11),
          _field(
            value,
            'Maximum VBUS Voltage',
            10,
            9,
            names: {0: '20 V', 1: '30 V', 2: '40 V', 3: '50 V'},
          ),
          _field(
            value,
            'Current Handling',
            6,
            5,
            names: {0: 'Default USB', 1: '3 A', 2: '5 A'},
          ),
          _field(value, 'USB Highest Speed', 2, 0),
        ]);
      }
    }
    fields.add(
      FieldNode(label, value: hexValue(value), raw: value, children: children),
    );
  }
  return fields;
}

List<FieldNode> decodeExtendedPayload(
  int type,
  Uint8List data,
  List<Diagnostic> diagnostics,
) {
  final fields = <FieldNode>[];
  final view = ByteData.sublistView(data);
  bool need(int length) {
    if (data.length >= length) return true;
    diagnostics.add(
      Diagnostic(
        'shortExtendedPayload',
        '该消息至少需要 $length 字节，实际 ${data.length}',
        severity: Severity.error,
      ),
    );
    return false;
  }

  void byte(String label, int offset, {String? unit}) => fields.add(
    FieldNode(
      label,
      value: data[offset],
      unit: unit,
      bitRange: '${offset * 8 + 7}:${offset * 8}',
    ),
  );
  void word(String label, int offset, {double? scale, String? unit}) {
    final raw = view.getUint16(offset, Endian.little);
    fields.add(
      FieldNode(
        label,
        value: scale == null ? hexValue(raw, 4) : raw * scale,
        raw: raw,
        unit: unit,
      ),
    );
  }

  switch (type) {
    case 1 || 15:
      if (!need(type == 1 ? 24 : 21)) break;
      word('VID', 0);
      word('PID', 2);
      fields.add(
        FieldNode('XID', value: hexValue(view.getUint32(4, Endian.little))),
      );
      byte('FW Version', 8);
      byte('HW Version', 9);
      if (type == 1) {
        byte('Voltage Regulation', 10);
        byte('Holdup Time', 11, unit: 'ms');
        byte('Compliance', 12);
        byte('Touch Current', 13);
        for (var i = 0; i < 3; i++) {
          word('Peak Current ${i + 1}', 14 + i * 2);
        }
        byte('Touch Temperature', 20);
        byte('Source Inputs', 21);
        byte('Battery Slots', 22);
        byte('SPR Source PDP', 23, unit: 'W');
        if (data.length >= 25) byte('EPR Source PDP', 24, unit: 'W');
      } else {
        byte('SKEDB Version', 10);
        byte('Load Step', 11);
        word('Load Characteristics', 12);
        byte('Compliance', 14);
        byte('Touch Temperature', 15);
        byte('Battery Info', 16);
        byte('Sink Modes', 17);
        for (var i = 18; i < data.length && i < 24; i++) {
          fields.add(
            FieldNode(
              '${i < 21 ? 'SPR' : 'EPR'} Sink ${['Minimum', 'Operational', 'Maximum'][(i - 18) % 3]} PDP',
              value: i < 21 ? data[i] & 127 : data[i],
              unit: 'W',
            ),
          );
        }
      }
    case 2:
      if (!need(6)) break;
      fields.add(
        FieldNode(
          'Internal Temperature',
          value: data[0] == 0
              ? 'Not supported'
              : data[0] == 1
              ? '< 2 °C'
              : '${data[0]} °C',
        ),
      );
      byte('Present Input', 1);
      byte('Present Battery Input', 2);
      byte('Event Flags', 3);
      byte('Temperature Status', 4);
      byte('Power Status', 5);
      if (data.length > 6) byte('Power State Change', 6);
    case 3 || 4:
      if (need(1)) byte('Battery Reference', 0);
    case 5:
      if (!need(9)) break;
      word('VID', 0);
      word('PID', 2);
      word('Battery Design Capacity', 4, scale: .1, unit: 'Wh');
      word('Battery Last Full Charge Capacity', 6, scale: .1, unit: 'Wh');
      byte('Battery Type', 8);
    case 6:
      if (!need(2)) break;
      byte('Manufacturer Info Target', 0);
      byte('Manufacturer Info Reference', 1);
    case 7:
      if (!need(4)) break;
      word('VID', 0);
      word('PID', 2);
      fields.add(
        FieldNode(
          'Manufacturer String',
          value: utf8.decode(
            data.sublist(4).takeWhile((b) => b != 0).toList(),
            allowMalformed: true,
          ),
        ),
      );
    case 12:
      if (!need(4)) break;
      final voltage = view.getUint16(0, Endian.little);
      fields.add(
        FieldNode(
          'Output Voltage',
          value: voltage == 0xffff ? 'Not supported' : voltage * .02,
          unit: voltage == 0xffff ? null : 'V',
        ),
      );
      fields.add(
        FieldNode(
          'Output Current',
          value: data[2] == 0xff ? 'Not supported' : data[2] * .05,
          unit: data[2] == 0xff ? null : 'A',
        ),
      );
      byte('Real Time Flags', 3);
    case 13:
      if (!need(4)) break;
      fields.add(
        FieldNode(
          'Country Code',
          value: ascii.decode(data.sublist(0, 2), allowInvalid: true),
        ),
      );
      fields.add(
        FieldNode('Country Specific Data', value: hexBytes(data.sublist(4))),
      );
    case 14:
      if (!need(2)) break;
      byte('Length', 0);
      for (var i = 2; i + 2 <= data.length; i += 2) {
        fields.add(
          FieldNode(
            'Country Code ${i ~/ 2}',
            value: ascii.decode(data.sublist(i, i + 2), allowInvalid: true),
          ),
        );
      }
    case 16:
      if (!need(2)) break;
      fields.add(
        FieldNode(
          'Type',
          value:
              {
                1: 'EPR_Get_Source_Cap',
                2: 'EPR_Get_Sink_Cap',
                3: 'EPR_KeepAlive',
                4: 'EPR_KeepAlive_Ack',
              }[data[0]] ??
              'Reserved',
        ),
      );
      byte('Data', 1);
    default:
      diagnostics.add(
        const Diagnostic(
          'rawExtendedPayload',
          '此扩展类型保留完整重组正文，未解释内部子协议',
          severity: Severity.info,
        ),
      );
  }
  return fields;
}
