import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hid_tool/src/android/hid_device_android.dart';
import 'package:witrn_analyzer/transport/hid_tool_transport.dart';

void main() {
  test('rate can be configured offline without starting native HID', () async {
    final transport = HidToolTransport();
    await transport.setReadRate(1);
    await transport.setReadRate(10);
    await expectLater(transport.setReadRate(0), throwsRangeError);
    await expectLater(transport.setReadRate(11), throwsRangeError);
    await transport.dispose();
  });

  for (final timeoutFirst in [false, true]) {
    testWidgets(
      'native reads are paced and adapt live, timeout=$timeoutFirst',
      (tester) async {
        var reads = 0;
        const channel = MethodChannel('hid_tool');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'receiveReport') {
              reads++;
              if (timeoutFirst && reads == 1) {
                throw PlatformException(code: 'TIMEOUT');
              }
              return Uint8List.fromList([reads]);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final device = HidDeviceAndroid.fromMap({
          'path': 'fake',
          'inputReportSize': 64,
        });
        await device.open();
        var interval = const Duration(milliseconds: 200);
        final reports = <Uint8List>[];
        final subscription = device
            .inputReports(readInterval: () => interval)
            .listen(reports.add);
        await tester.pump();
        expect(reads, 1);
        await tester.pump(const Duration(milliseconds: 50));
        expect(reads, 1);
        await tester.pump(const Duration(milliseconds: 151));
        expect(reads, 2);
        interval = const Duration(milliseconds: 100);
        await tester.pump(const Duration(milliseconds: 201));
        expect(reads, 3);
        await tester.pump(const Duration(milliseconds: 101));
        expect(reads, 4);
        expect(
          reports.map((report) => report.single),
          timeoutFirst ? [2, 3, 4] : [1, 2, 3, 4],
        );
        final cancellation = subscription.cancel();
        await device.close();
        await tester.pump(const Duration(seconds: 1));
        await cancellation;
        expect(reads, 4);
      },
    );
  }
}
