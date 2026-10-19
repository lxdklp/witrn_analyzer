import 'models.dart';

PowerCapability decodeCapability(
  int raw,
  int position,
  DecodeProfile profile, {
  bool sink = false,
}) {
  final fields = <FieldNode>[];
  void number(String name, int hi, int lo, double scale, String unit) {
    fields.add(
      FieldNode(
        name,
        value: bits(raw, hi, lo) * scale,
        raw: bits(raw, hi, lo),
        unit: unit,
        bitRange: '$hi:$lo',
      ),
    );
  }

  void flag(String name, int bit) => fields.add(
    FieldNode(
      name,
      value: bits(raw, bit, bit) == 1,
      raw: bits(raw, bit, bit),
      bitRange: '$bit',
    ),
  );
  double? minV, maxV, current, power, at15, at20;
  final type = bits(raw, 31, 30);
  final compat = profile == DecodeProfile.witrnCompat;
  var kind = PdoKind.reserved;
  fields.add(FieldNode('PDO 类型', value: type, bitRange: '31:30'));
  switch (type) {
    case 0:
      kind = PdoKind.fixed;
      minV = maxV = bits(raw, 19, 10) * .05;
      current = bits(raw, 9, 0) * .01;
      flag('Dual Role Power', 29);
      flag(sink ? 'Higher Capability' : 'USB Suspend Supported', 28);
      flag('Unconstrained Power', 27);
      flag('USB Communications Capable', 26);
      flag('Dual Role Data', 25);
      if (sink) {
        fields.add(
          FieldNode(
            'Fast Role Swap Current',
            value: bits(raw, 24, 23),
            bitRange: '24:23',
          ),
        );
      } else {
        flag('Unchunked Extended Messages', 24);
        flag('EPR Mode Capable', 23);
        fields.add(
          FieldNode(
            'Peak Current',
            value: bits(raw, 21, 20),
            bitRange: '21:20',
          ),
        );
      }
      number('Voltage', 19, 10, .05, 'V');
      number(sink ? 'Operational Current' : 'Maximum Current', 9, 0, .01, 'A');
    case 1 || 2:
      kind = type == 1 ? PdoKind.battery : PdoKind.variable;
      maxV = bits(raw, 29, 20) * .05;
      minV = bits(raw, 19, 10) * .05;
      number('Maximum Voltage', 29, 20, .05, 'V');
      number('Minimum Voltage', 19, 10, .05, 'V');
      if (type == 1) {
        power = bits(raw, 9, 0) * .25;
        number(sink ? 'Operational Power' : 'Maximum Power', 9, 0, .25, 'W');
      } else {
        current = bits(raw, 9, 0) * .01;
        number(
          sink ? 'Operational Current' : 'Maximum Current',
          9,
          0,
          .01,
          'A',
        );
      }
    case 3:
      final subtype = bits(raw, 29, 28);
      fields.add(FieldNode('APDO 类型', value: subtype, bitRange: '29:28'));
      switch (subtype) {
        case 0:
          kind = PdoKind.pps;
          maxV = bits(raw, compat ? 26 : 24, 17) * .1;
          minV = bits(raw, compat ? 16 : 15, 8) * .1;
          current = bits(raw, compat ? 7 : 6, 0) * .05;
          if (!sink) flag('PPS Power Limited', 27);
          number('Maximum Voltage', compat ? 26 : 24, 17, .1, 'V');
          number('Minimum Voltage', compat ? 16 : 15, 8, .1, 'V');
          number('Maximum Current', compat ? 7 : 6, 0, .05, 'A');
        case 1:
          kind = PdoKind.eprAvs;
          maxV = bits(raw, 25, 17) * .1;
          minV = bits(raw, 15, 8) * .1;
          power = bits(raw, 7, 0).toDouble();
          number('Maximum Voltage', 25, 17, .1, 'V');
          number('Minimum Voltage', 15, 8, .1, 'V');
          number('PDP', 7, 0, 1, 'W');
        case 2:
          kind = PdoKind.sprAvs;
          at15 = bits(raw, 19, 10) * .01;
          at20 = bits(raw, 9, 0) * .01;
          number('15 V Maximum Current', 19, 10, .01, 'A');
          number('20 V Maximum Current', 9, 0, .01, 'A');
      }
  }
  return PowerCapability(
    raw: raw,
    position: position,
    kind: kind,
    fields: List.unmodifiable(fields),
    minVoltage: minV,
    maxVoltage: maxV,
    maxCurrent: current,
    maxPower: power,
    currentAt15V: at15,
    currentAt20V: at20,
  );
}

PowerRequest decodeRequest(
  int raw,
  PowerCapability? pdo,
  DecodeProfile profile,
) {
  double? voltage, current, power, limit;
  final giveback = bits(raw, 27, 27) == 1;
  switch (pdo?.kind) {
    case PdoKind.fixed || PdoKind.variable:
      voltage = pdo?.kind == PdoKind.fixed ? pdo?.maxVoltage : null;
      current = bits(raw, 19, 10) * .01;
      limit = bits(raw, 9, 0) * .01;
    case PdoKind.battery:
      power = bits(raw, 19, 10) * .25;
      limit = bits(raw, 9, 0) * .25;
    case PdoKind.pps:
      final compat = profile == DecodeProfile.witrnCompat;
      voltage = bits(raw, compat ? 21 : 20, 9) * .02;
      current = bits(raw, compat ? 8 : 6, 0) * .05;
    case PdoKind.eprAvs || PdoKind.sprAvs:
      voltage = bits(raw, 20, 9) * .025;
      current = bits(raw, 6, 0) * .05;
    case PdoKind.reserved || null:
      break;
  }
  return PowerRequest(
    raw: raw,
    position: bits(raw, 31, 28),
    capability: pdo,
    voltage: voltage,
    current: current,
    power: power,
    limit: limit,
    giveback: giveback,
  );
}

List<FieldNode> requestFields(PowerRequest r) => [
  FieldNode('Object Position', value: r.position, bitRange: '31:28'),
  for (final flag in [
    (26, 'Capability Mismatch'),
    (25, 'USB Communications Capable'),
    (24, 'No USB Suspend'),
    (23, 'Unchunked Extended Messages'),
    (22, 'EPR Mode Capable'),
  ])
    FieldNode(
      flag.$2,
      value: bits(r.raw, flag.$1, flag.$1) == 1,
      bitRange: '${flag.$1}',
    ),
  if (r.voltage != null)
    FieldNode('Output Voltage', value: r.voltage, unit: 'V'),
  if (r.current != null)
    FieldNode('Operating Current', value: r.current, unit: 'A'),
  if (r.power != null) FieldNode('Operating Power', value: r.power, unit: 'W'),
  if (r.limit != null) ...[
    FieldNode('Giveback', value: r.giveback, bitRange: '27'),
    FieldNode(
      r.giveback ? 'Minimum Operating' : 'Maximum Operating',
      value: r.limit,
      unit: r.power == null ? 'A' : 'W',
      bitRange: '9:0',
    ),
  ],
];
