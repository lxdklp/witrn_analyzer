import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/models.dart';
import '../core/pd_decoder.dart';

final class InputFrame {
  const InputFrame({
    required this.generation,
    required this.elapsedUs,
    required this.time,
    required this.recording,
    required this.bytes,
  });
  final int generation, elapsedUs;
  final DateTime time;
  final bool recording;
  final Uint8List bytes;
}

final class DecodedFrame {
  const DecodedFrame(this.input, this.report);
  final InputFrame input;
  final DecodedReport report;
}

final class DecoderWorker {
  final _results = StreamController<List<DecodedFrame>>.broadcast();
  Stream<List<DecodedFrame>> get results => _results.stream;
  Isolate? _isolate;
  ReceivePort? _port;
  SendPort? _input;
  final Map<int, Completer<void>> _barriers = {};
  var _barrierId = 0;
  int pending = 0;
  Future<void> start(DecodeProfile profile, bool verifyCrc) async {
    if (_isolate != null) return;
    final ready = Completer<void>();
    final port = _port = ReceivePort();
    port.listen((Object? message) {
      if (message is SendPort) {
        _input = message;
        ready.complete();
      }
      if (message is List<DecodedFrame>) {
        pending -= message.length;
        _results.add(message);
      }
      if (message is int) _barriers.remove(message)?.complete();
    });
    _isolate = await Isolate.spawn(_decodeLoop, (
      port.sendPort,
      profile,
      verifyCrc,
    ));
    await ready.future;
  }

  bool add(InputFrame frame) {
    if (_input == null || pending >= 2048) return false;
    pending++;
    _input!.send(frame);
    return true;
  }

  Future<void> flush() async {
    if (_input == null) return;
    final id = ++_barrierId;
    final done = Completer<void>();
    _barriers[id] = done;
    _input!.send(id);
    await done.future;
  }

  void reset(DecodeProfile profile, bool verifyCrc) =>
      _input?.send((profile, verifyCrc));
  Future<void> dispose() async {
    await flush();
    _isolate?.kill(priority: Isolate.immediate);
    _port?.close();
    await _results.close();
  }
}

void _decodeLoop((SendPort, DecodeProfile, bool) config) {
  final (output, profile, verifyCrc) = config;
  final port = ReceivePort();
  var decoder = PdDecoder(profile: profile, verifyCrc: verifyCrc);
  var batch = <DecodedFrame>[];
  void flush() {
    if (batch.isEmpty) return;
    output.send(batch);
    batch = [];
  }

  Timer.periodic(const Duration(milliseconds: 25), (_) => flush());
  port.listen((Object? event) {
    switch (event) {
      case InputFrame():
        batch.add(
          DecodedFrame(
            event,
            decoder.decode(event.bytes, elapsedUs: event.elapsedUs),
          ),
        );
        if (batch.length >= 128) flush();
      case (DecodeProfile newProfile, bool crc):
        flush();
        decoder = PdDecoder(profile: newProfile, verifyCrc: crc);
      case int():
        flush();
        output.send(event);
    }
  });
  output.send(port.sendPort);
}
