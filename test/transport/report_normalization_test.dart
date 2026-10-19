import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/transport/hid_transport.dart';

void main() {
  test(
    'native boundaries retain FE/FF; only proven report IDs are removed',
    () {
      final raw = Uint8List(64)..[0] = 0xfe;
      expect(normalizeReport(raw, ReportLayout.automatic, {0xfe}), raw);
      final prefixed = Uint8List.fromList([1, ...raw]);
      expect(
        () => normalizeReport(prefixed, ReportLayout.automatic, {}),
        throwsFormatException,
      );
      expect(normalizeReport(prefixed, ReportLayout.automatic, {1}), raw);
      expect(normalizeReport(prefixed, ReportLayout.reportId65, {}), raw);
      expect(
        () => normalizeReport(prefixed, ReportLayout.raw64, {1}),
        throwsFormatException,
      );
      expect(
        () => normalizeReport(Uint8List(63), ReportLayout.automatic, {}),
        throwsFormatException,
      );
    },
  );
}
