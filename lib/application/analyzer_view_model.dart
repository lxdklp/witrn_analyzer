import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../data/capture_repository.dart';
import '../data/capture_file_service.dart';
import '../data/csv_capture_codec.dart';
import '../data/csv_chart_codec.dart';
import '../data/decoder_worker.dart';
import '../transport/hid_transport.dart';

enum ConnectionPhase { disconnected, connecting, connected, closing, failed }

enum ContentSource { live, imported }

final class AnalyzerViewModel extends ChangeNotifier {
  AnalyzerViewModel({
    required this.transport,
    required this.repository,
    required this.files,
    this.connectionTimeout = const Duration(seconds: 8),
  }) {
    _reportSubscription = transport.reports.listen(
      _receive,
      onError: (Object error) => unawaited(_fail(error)),
    );
    _decodedSubscription = _decoder.results.listen(_consume);
    _refresh = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_dirty) {
        _dirty = false;
        _notify();
      }
    });
  }
  final HidTransport transport;
  final CaptureRepository repository;
  final CaptureFileService files;
  final Duration connectionTimeout;
  final DecoderWorker _decoder = DecoderWorker();
  final Stopwatch _clock = Stopwatch();
  StreamSubscription<Uint8List>? _reportSubscription;
  StreamSubscription<List<DecodedFrame>>? _decodedSubscription;
  Timer? _refresh, _timeout;
  Future<void>? _closing;
  bool _disposed = false, _dirty = false;
  int _generation = 0, _nextId = 1, _operation = 0;
  ConnectionPhase connection = ConnectionPhase.disconnected;
  ContentSource source = ContentSource.live;
  bool recording = false, busy = false, scanning = false;
  bool hideGoodCrc = true, relativeTime = true, followLatest = true;
  String search = '',
      sopFilter = '全部',
      fileName = '',
      status = '就绪，连接设备或导入 CSV';
  String? error;
  String chartFileName = '';
  bool get chartLinkedToMessages =>
      source == ContentSource.live && chartFileName.isEmpty;
  bool get canExportChart => !busy && samples.isNotEmpty;
  List<DeviceInfo> devices = const [];
  DeviceInfo? selectedDevice;
  CaptureRecord? selected;
  TelemetrySample? latestTelemetry;
  List<PowerCapability> sourceCapabilities = const [];
  PowerRequest? latestRequest;
  DecodeProfile profile = DecodeProfile.witrnCompat;
  ReportLayout reportLayout = ReportLayout.automatic;
  bool verifyCrc = false;
  int _usbVendorId = defaultUsbVendorId;
  int _usbProductId = defaultUsbProductId;
  bool get canConfigureUsb =>
      !connected && !transitioning && !scanning && !busy;

  void setUsbDeviceIds({required int vendorId, required int productId}) {
    RangeError.checkValueInInterval(vendorId, 0, 0xffff, 'vendorId');
    RangeError.checkValueInInterval(productId, 0, 0xffff, 'productId');
    if (_usbVendorId == vendorId && _usbProductId == productId) return;
    _usbVendorId = vendorId;
    _usbProductId = productId;
    // Invalidate scan results so the next connection cannot reuse another filter.
    devices = const [];
    selectedDevice = null;
    _notify();
  }

  int _hidReadRateHz = 10;

  Future<void> setHidReadRate(int hz) async {
    if (_hidReadRateHz == hz) return;
    _hidReadRateHz = hz;
    try {
      await transport.setReadRate(hz);
    } catch (error) {
      _error(error);
    }
  }

  int receivedReports = 0,
      droppedReports = 0,
      pausedReports = 0,
      invalidReports = 0;
  final List<CaptureRecord> _visible = [];
  int _indexed = 0;
  bool _filterDirty = true;

  bool get connected => connection == ConnectionPhase.connected;
  bool get transitioning =>
      connection == ConnectionPhase.connecting ||
      connection == ConnectionPhase.closing;
  bool get canConfigure =>
      !connected && !transitioning && !busy && records.isEmpty;
  bool get canImport => !recording && !transitioning && !busy;
  List<CaptureRecord> get records => repository.records;
  List<TelemetrySample> get samples => repository.samples;
  List<Diagnostic> get diagnostics => repository.diagnostics;
  List<CaptureRecord> get visibleRecords {
    final all = records;
    if (_filterDirty || _indexed > all.length) {
      _visible.clear();
      _indexed = 0;
      _filterDirty = false;
    }
    final query = search.toLowerCase();
    for (; _indexed < all.length; _indexed++) {
      final record = all[_indexed];
      if (hideGoodCrc && record.message.isGoodCrc) continue;
      if (sopFilter != '全部' && record.message.sop != sopFilter) continue;
      if (query.isNotEmpty &&
          !'${record.id} ${record.message.type} ${record.message.summary} ${record.rawHex}'
              .toLowerCase()
              .contains(query)) {
        continue;
      }
      _visible.add(record);
    }
    return _visible;
  }

  String timeLabel(CaptureRecord record) => relativeTime
      ? formatElapsed(record.elapsedUs - (records.firstOrNull?.elapsedUs ?? 0))
      : record.clockTime;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setFilters({bool? goodCrc, String? query, String? sop}) {
    if (goodCrc != null) hideGoodCrc = goodCrc;
    if (query != null) search = query;
    if (sop != null) sopFilter = sop;
    _filterDirty = true;
    _notify();
  }

  void toggleRelative() {
    relativeTime = !relativeTime;
    _notify();
  }

  void setFollow(bool follow) {
    followLatest = follow;
    _notify();
  }

  void select(CaptureRecord record) {
    selected = record;
    followLatest = false;
    _notify();
  }

  void selectDevice(DeviceInfo device) {
    selectedDevice = device;
    _notify();
  }

  void clearError() {
    error = null;
    _notify();
  }

  void _error(Object value) {
    error = value.toString().replaceFirst(
      RegExp(r'^(Bad state: |FormatException: )'),
      '',
    );
    _notify();
  }

  Future<void> refreshDevices() async {
    if (scanning || transitioning) return;
    scanning = true;
    error = null;
    _notify();
    try {
      final vendorId = _usbVendorId, productId = _usbProductId;
      final found = await transport.enumerate(
        vendorId: vendorId,
        productId: productId,
      );
      if (vendorId != _usbVendorId || productId != _usbProductId) return;
      devices = found;
      selectedDevice =
          devices.where((d) => d.path == selectedDevice?.path).firstOrNull ??
          devices.firstOrNull;
      status = devices.isEmpty
          ? '未找到 USB HID 设备（${vendorId.toRadixString(16).padLeft(4, '0').toUpperCase()}:${productId.toRadixString(16).padLeft(4, '0').toUpperCase()}），请检查 USB 连接与权限'
          : '找到 ${devices.length} 个设备接口';
    } catch (e) {
      _error(e);
    } finally {
      scanning = false;
      _notify();
    }
  }

  Future<void> connect() async {
    if (connected) {
      start();
      return;
    }
    if (transitioning || busy) return;
    error = null;
    if (selectedDevice == null) await refreshDevices();
    if (selectedDevice == null || _disposed) return;
    final operation = ++_operation;
    connection = ConnectionPhase.connecting;
    _notify();
    try {
      await _decoder.start(profile, verifyCrc);
      _newSession();
      status = '正在打开设备并等待有效报告…';
      _notify();
      await transport.open(
        selectedDevice!,
        layout: reportLayout,
        vendorId: _usbVendorId,
        productId: _usbProductId,
      );
      if (operation != _operation || _disposed) {
        await transport.close();
        return;
      }
      if (connection == ConnectionPhase.connecting) {
        _timeout = Timer(
          connectionTimeout,
          () =>
              unawaited(_fail(TimeoutException('设备已打开，但未收到有效报告。请检查接口与报告布局。'))),
        );
      }
    } catch (e) {
      if (operation == _operation) await _fail(e);
    }
  }

  void start() {
    if (!connected || busy || source != ContentSource.live) return;
    recording = true;
    followLatest = true;
    status = '正在采集 PD 报文和电参曲线';
    _notify();
  }

  void pause() {
    if (!connected || !recording) return;
    recording = false;
    status = '采集已暂停，PD 报文和电参曲线均停止更新';
    _notify();
  }

  Future<void> disconnect() =>
      _closing ??= _disconnect().whenComplete(() => _closing = null);
  Future<void> _disconnect() async {
    ++_operation;
    _timeout?.cancel();
    _timeout = null;
    recording = false;
    connection = ConnectionPhase.closing;
    _notify();
    try {
      await transport.close();
      await _decoder.flush();
    } catch (e) {
      _error(e);
    } finally {
      connection = ConnectionPhase.disconnected;
      _clock.stop();
      status = '已断开，历史记录已保留';
      _notify();
    }
  }

  Future<void> _fail(Object reason) async {
    if (_disposed ||
        connection == ConnectionPhase.closing ||
        connection == ConnectionPhase.failed ||
        connection == ConnectionPhase.disconnected) {
      return;
    }
    await disconnect();
    connection = ConnectionPhase.failed;
    _error(reason);
  }

  void _newSession() {
    _generation++;
    _nextId = 1;
    recording = connected;
    repository.clear();
    selected = null;
    sourceCapabilities = const [];
    latestRequest = null;
    latestTelemetry = null;
    source = ContentSource.live;
    fileName = '';
    chartFileName = '';
    receivedReports = droppedReports = pausedReports = invalidReports = 0;
    _filterDirty = true;
    followLatest = true;
    _clock
      ..reset()
      ..start();
    _decoder.reset(profile, verifyCrc);
  }

  Future<void> clearSession() async {
    if (transitioning || busy) return;
    await _decoder.flush();
    _newSession();
    if (!connected) _clock.stop();
    status = connected ? '新会话已建立，正在采集 PD 报文和电参曲线' : '会话已清空';
    _notify();
  }

  void configure({
    required DecodeProfile decodeProfile,
    required bool crc,
    required ReportLayout layout,
  }) {
    if (!canConfigure) return;
    profile = decodeProfile;
    verifyCrc = crc;
    reportLayout = layout;
    _notify();
  }

  void _receive(Uint8List bytes) {
    if (_disposed || (connection != ConnectionPhase.connecting && !connected)) {
      return;
    }
    receivedReports++;
    if (!_decoder.add(
      InputFrame(
        generation: _generation,
        elapsedUs: _clock.elapsedMicroseconds,
        time: DateTime.now().toUtc(),
        recording: recording || connection == ConnectionPhase.connecting,
        bytes: bytes,
      ),
    )) {
      droppedReports++;
      repository.addDiagnostic(
        const Diagnostic('queueOverflow', '解析队列已满，丢弃一份新报告；上下文可能不完整'),
      );
      _decoder.reset(profile, verifyCrc);
    }
  }

  void _consume(List<DecodedFrame> frames) {
    for (final frame in frames) {
      if (frame.input.generation != _generation) continue;
      final report = frame.report;
      if (connection == ConnectionPhase.connecting &&
          (report is GeneralReport ||
              report is PdReport && report.message.isValid)) {
        connection = ConnectionPhase.connected;
        _timeout?.cancel();
        recording = true;
        status = '正在采集 PD 报文和电参曲线';
      }
      switch (report) {
        case GeneralReport(:final sample):
          if (!frame.input.recording) {
            pausedReports++;
            break;
          }
          latestTelemetry = sample;
          repository.addSample(sample);
        case PdReport(:final message):
          if (!frame.input.recording) {
            pausedReports++;
            break;
          }
          final record = CaptureRecord(
            id: _nextId++,
            elapsedUs: frame.input.elapsedUs,
            time: frame.input.time,
            message: message,
            report: frame.input.bytes,
          );
          if (!repository.addRecord(record)) {
            droppedReports++;
            recording = false;
            status = '达到 100,000 条容量上限，已暂停；请导出后新建会话';
            break;
          }
          if (message.isSourceCapabilities && message.isValid) {
            sourceCapabilities = message.capabilities;
          }
          if (message.request != null) latestRequest = message.request;
          if (followLatest && (!hideGoodCrc || !message.isGoodCrc)) {
            selected = record;
          }
        case InvalidReport(:final diagnostic):
          invalidReports++;
          repository.addDiagnostic(diagnostic);
      }
    }
    _dirty = true;
  }

  Future<void> importCsv() async {
    if (!canImport) return;
    busy = true;
    error = null;
    _notify();
    try {
      final file = await files.pickCsv();
      if (file == null || _disposed) return;
      await _importBytes(file.bytes, file.name);
    } catch (e) {
      _error(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> importBytes(Uint8List bytes, String name) async {
    if (!canImport) return;
    busy = true;
    error = null;
    _notify();
    try {
      await _importBytes(bytes, name);
    } catch (e) {
      _error(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _importBytes(Uint8List bytes, String name) async {
    final decodeProfile = profile;
    final crc = verifyCrc;
    status = '正在解析 CSV…';
    _notify();
    // The isolate owns a fresh decoder; unsuccessful imports leave the old session intact.
    final result = await Isolate.run(
      () => const CsvCaptureCodec().decode(
        bytes,
        profile: decodeProfile,
        verifyCrc: crc,
      ),
    );
    if (_disposed) return;
    if (connected) await disconnect();
    _generation++;
    repository.replace(result.records, result.diagnostics);
    source = ContentSource.imported;
    fileName = name;
    recording = false;
    followLatest = false;
    selected = records.firstOrNull;
    latestTelemetry = samples.lastOrNull;
    receivedReports = droppedReports = pausedReports = invalidReports = 0;
    _filterDirty = true;
    _restoreSummary();
    status =
        '已导入 ${records.length} 条 PD 报文${result.skippedRows == 0 ? '' : '，跳过 ${result.skippedRows} 行'}';
  }

  Future<void> exportCsv() async {
    if (busy || records.isEmpty) return;
    busy = true;
    error = null;
    _notify();
    try {
      final snapshot = List<CaptureRecord>.of(records);
      final bytes = await Isolate.run(
        () => const CsvCaptureCodec().encode(snapshot),
      );
      final now = DateTime.now();
      final name =
          'WITRN_PD_${now.toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.csv';
      final path = await files.saveCsv(name, bytes);
      if (path != null) status = '已导出全部 ${snapshot.length} 条报文（含隐藏的 GoodCRC）';
    } catch (e) {
      _error(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> importChart() async {
    if (!canImport) return;
    busy = true;
    error = null;
    _notify();
    try {
      final file = await files.pickCsv(title: '导入图表');
      if (file == null || _disposed) return;
      await _importChartBytes(file.bytes, file.name);
    } catch (e) {
      _error(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> importChartBytes(Uint8List bytes, String name) async {
    if (!canImport) return;
    busy = true;
    error = null;
    _notify();
    try {
      await _importChartBytes(bytes, name);
    } catch (e) {
      _error(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _importChartBytes(Uint8List bytes, String name) async {
    final imported = await Isolate.run(
      () => const CsvChartCodec().decode(bytes),
    );
    if (_disposed) return;
    if (connected) await disconnect();
    repository.replaceSamples(imported);
    _generation++;
    chartFileName = name;
    latestTelemetry = imported.last;
    source = ContentSource.imported;
    recording = false;
    followLatest = true;
    status = '已导入图表 $name，共 ${imported.length} 条电参采样';
  }

  Future<void> exportChart() async {
    if (!canExportChart) return;
    busy = true;
    error = null;
    _notify();
    try {
      // Export the full retained history, not the downsampled/visible chart.
      final snapshot = List<TelemetrySample>.of(samples);
      final bytes = await Isolate.run(
        () => const CsvChartCodec().encode(snapshot),
      );
      final stamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final path = await files.saveCsv(
        'WITRN_Chart_$stamp.csv',
        bytes,
        title: '导出图表',
      );
      if (path != null) status = '已导出图表，共 ${snapshot.length} 条电参采样';
    } catch (e) {
      _error(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  void _restoreSummary() {
    sourceCapabilities = const [];
    latestRequest = null;
    for (final record in records) {
      if (record.message.isSourceCapabilities && record.message.isValid) {
        sourceCapabilities = record.message.capabilities;
      }
      if (record.message.request != null) {
        latestRequest = record.message.request;
      }
    }
  }

  Future<void>? _shutdownFuture;
  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    _refresh?.cancel();
    _timeout?.cancel();
    await disconnect();
    await _reportSubscription?.cancel();
    await _decodedSubscription?.cancel();
    await _decoder.dispose();
    await transport.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(shutdown());
    super.dispose();
  }
}
