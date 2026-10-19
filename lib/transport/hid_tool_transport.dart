import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:hid_tool/hid_tool.dart';

import 'hid_transport.dart';

/// Desktop: one persistent isolate owns all HID handles and FFI calls.
/// Android: platform calls stay on the root isolate; native I/O uses a serial queue.
final class HidToolTransport implements HidTransport {
  final _reports = StreamController<Uint8List>.broadcast();
  final Map<int, Completer<Object?>> _pending = {};
  _DeviceDriver? _driver;
  Isolate? _worker;
  ReceivePort? _port;
  SendPort? _commands;
  StreamSubscription<HidDeviceEvent>? _detach;
  Future<void>? _initializing;
  String? _path;
  int _id = 0;
  int _readRateHz = 10;
  bool _disposed = false;
  @override
  Uint8List? descriptor;
  @override
  Stream<Uint8List> get reports => _reports.stream;

  Future<void> _initialize() => _initializing ??= _start();
  Future<void> _start() async {
    if (Platform.isAndroid) {
      _driver = _DeviceDriver(
        (data) => _reports.add(data),
        (error) => _reports.addError(error),
      );
    } else {
      final ready = Completer<void>();
      final port = _port = ReceivePort();
      port.listen((Object? event) {
        if (event is SendPort) {
          _commands = event;
          ready.complete();
        }
        if (event is Uint8List && !_disposed) _reports.add(event);
        if (event is _Reply) {
          final pending = _pending.remove(event.id);
          if (event.error != null) {
            pending?.completeError(StateError(event.error!));
          } else {
            pending?.complete(event.value);
          }
        }
        if (event is _ReadError && !_disposed) {
          _reports.addError(StateError(event.message));
        }
      });
      _worker = await Isolate.spawn(_hidWorker, port.sendPort);
      await ready.future.timeout(const Duration(seconds: 10));
    }
    await Hid.startListening();
    _detach = HidDeviceEvents.onDisconnected.listen((event) {
      if (event.path == _path && !_disposed) {
        _reports.addError(StateError('USB 设备已拔出'));
      }
    });
  }

  Future<Object?> _call(String method, [Object? argument]) async {
    await _initialize();
    if (_disposed) throw StateError('Transport disposed');
    if (_driver case final driver?) return driver.call(method, argument);
    final id = ++_id;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands!.send(_Command(id, method, argument));
    return completer.future;
  }

  @override
  Future<List<DeviceInfo>> enumerate({
    int vendorId = defaultUsbVendorId,
    int productId = defaultUsbProductId,
  }) async {
    RangeError.checkValueInInterval(vendorId, 0, 0xffff, 'vendorId');
    RangeError.checkValueInInterval(productId, 0, 0xffff, 'productId');
    return (await _call('enumerate', (vendorId, productId)))!
        as List<DeviceInfo>;
  }

  @override
  Future<void> setReadRate(int hz) async {
    RangeError.checkValueInInterval(hz, 1, 10, 'hz');
    if (_disposed) throw StateError('Transport disposed');
    _readRateHz = hz;
    // Saving preferences while offline must not start the USB backend.
    if (_initializing != null) await _call('setReadRate', hz);
  }

  @override
  Future<void> open(
    DeviceInfo device, {
    ReportLayout layout = ReportLayout.automatic,
    int vendorId = defaultUsbVendorId,
    int productId = defaultUsbProductId,
  }) async {
    RangeError.checkValueInInterval(vendorId, 0, 0xffff, 'vendorId');
    RangeError.checkValueInInterval(productId, 0, 0xffff, 'productId');
    _path = device.path;
    descriptor = await _call('open', (
      device.path,
      layout,
      _readRateHz,
      vendorId,
      productId,
    )) as Uint8List?;
  }

  @override
  Future<void> close() async {
    _path = null;
    if (_initializing == null || _disposed) return;
    await _call('close');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    try {
      await close();
    } finally {
      _disposed = true;
      await _detach?.cancel();
      if (_initializing != null) await Hid.stopListening();
      _worker?.kill(priority: Isolate.immediate);
      _port?.close();
      for (final pending in _pending.values) {
        pending.completeError(StateError('Transport disposed'));
      }
      _pending.clear();
      await _reports.close();
    }
  }
}

final class _Command {
  const _Command(this.id, this.method, this.argument);
  final int id;
  final String method;
  final Object? argument;
}

final class _Reply {
  const _Reply(this.id, this.value, [this.error]);
  final int id;
  final Object? value;
  final String? error;
}

final class _ReadError {
  const _ReadError(this.message);
  final String message;
}

Future<void> _hidWorker(SendPort output) async {
  DartPluginRegistrant.ensureInitialized();
  final port = ReceivePort();
  final driver = _DeviceDriver(
    output.send,
    (error) => output.send(_ReadError(error.toString())),
  );
  output.send(port.sendPort);
  await for (final event in port) {
    final command = event as _Command;
    try {
      output.send(
        _Reply(command.id, await driver.call(command.method, command.argument)),
      );
    } catch (error) {
      output.send(_Reply(command.id, null, error.toString()));
    }
  }
}

final class _DeviceDriver {
  _DeviceDriver(this.onReport, this.onError);
  final void Function(Uint8List) onReport;
  final void Function(Object) onError;
  HidDevice? _device;
  StreamSubscription<Uint8List>? _input;
  bool _closing = false;
  Duration _readInterval = const Duration(milliseconds: 100);
  Future<Object?> call(String method, Object? argument) async {
    switch (method) {
      case 'setReadRate':
        final hz = argument! as int;
        RangeError.checkValueInInterval(hz, 1, 10, 'hz');
        _readInterval = Duration(microseconds: (1000000 / hz).ceil());
        return null;
      case 'enumerate':
        final (vendorId, productId) = argument! as (int, int);
        final devices = await Hid.getDevices(
          vendorId: vendorId,
          productId: productId,
        );
        return [
          for (final d in devices)
            // HIDAPI treats zero as a wildcard; configured IDs match exactly.
            if (d.vendorId == vendorId && d.productId == productId)
              DeviceInfo(
                path: d.path,
                name: d.productName.isEmpty ? 'USB HID' : d.productName,
                serial: d.serialNumber,
                interfaceNumber: d.interfaceNumber,
              ),
        ];
      case 'open':
        await close();
        final (path, layout, hz, vendorId, productId) =
            argument! as (String, ReportLayout, int, int, int);
        _readInterval = Duration(microseconds: (1000000 / hz).ceil());
        final devices = await Hid.getDevices(
          vendorId: vendorId,
          productId: productId,
        );
        final device = devices
            .where(
              (d) =>
                  d.path == path &&
                  d.vendorId == vendorId &&
                  d.productId == productId,
            )
            .firstOrNull;
        if (device == null) throw StateError('所选设备已断开，请重新扫描');
        _device = device;
        try {
          await device.open();
          Uint8List? descriptor;
          final ids = <int>{};
          try {
            final reportDescriptor = await device.getReportDescriptor();
            descriptor = reportDescriptor.rawBytes;
            // Prove an extra Report ID only for a declared 512-bit input body.
            final lengths = <int, int>{};
            for (final input in reportDescriptor.inputs) {
              lengths.update(
                input.reportId,
                (n) => n + input.reportSize * input.reportCount,
                ifAbsent: () => input.reportSize * input.reportCount,
              );
            }
            ids.addAll(
              lengths.entries
                  .where((e) => e.key != 0 && e.value == 512)
                  .map((e) => e.key),
            );
          } catch (_) {
            // Descriptor retrieval is unsupported on some firmware. Raw 64 remains
            // usable, but automatic mode will never strip an unproven report ID.
          }
          _closing = false;
          _input = device
              .inputReports(readInterval: () => _readInterval)
              .listen(
                (report) {
                  if (_closing) return;
                  try {
                    onReport(normalizeReport(report, layout, ids));
                  } catch (error) {
                    onError(error);
                  }
                },
                onError: (Object error) {
                  if (!_closing) onError(error);
                },
                onDone: () {
                  if (!_closing) onError(StateError('HID 输入流已结束'));
                },
              );
          return descriptor;
        } catch (_) {
          await close();
          rethrow;
        }
      case 'close':
        await close();
        return null;
      default:
        throw StateError('Unknown HID operation: $method');
    }
  }

  Future<void> close() async {
    _closing = true;
    final device = _device;
    _device = null;
    final cancellation = _input?.cancel();
    _input = null;
    try {
      if (device != null && (device.isOpen || Platform.isAndroid)) {
        await device.close();
      }
    } finally {
      await cancellation;
    }
  }
}
