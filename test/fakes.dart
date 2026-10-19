import 'dart:async';
import 'dart:typed_data';

import 'package:witrn_analyzer/transport/hid_transport.dart';
import 'package:witrn_analyzer/data/capture_file_service.dart';

final class FakeTransport implements HidTransport {
  final controller = StreamController<Uint8List>.broadcast();
  bool isOpen = false;
  int openCount = 0, closeCount = 0;
  int readRateHz = 10;
  (int, int)? enumeratedIds, openedIds;
  @override
  Future<void> setReadRate(int hz) async => readRateHz = hz;
  Object? openError;
  static const device = DeviceInfo(
    path: 'fake-k2',
    name: 'Test K2',
    serial: 'test',
    interfaceNumber: 0,
  );
  @override
  Uint8List? get descriptor => null;
  @override
  Stream<Uint8List> get reports => controller.stream;
  @override
  Future<List<DeviceInfo>> enumerate({
    int vendorId = defaultUsbVendorId,
    int productId = defaultUsbProductId,
  }) async {
    enumeratedIds = (vendorId, productId);
    return [device];
  }

  @override
  Future<void> open(
    DeviceInfo device, {
    ReportLayout layout = ReportLayout.automatic,
    int vendorId = defaultUsbVendorId,
    int productId = defaultUsbProductId,
  }) async {
    openedIds = (vendorId, productId);
    if (openError != null) throw openError!;
    isOpen = true;
    openCount++;
  }

  @override
  Future<void> close() async {
    if (isOpen) closeCount++;
    isOpen = false;
  }

  @override
  Future<void> dispose() async {
    await close();
    await controller.close();
  }

  void emit(List<int> bytes) => controller.add(Uint8List.fromList(bytes));
}

final class FakeFiles implements CaptureFileService {
  CaptureFile? picked;
  Uint8List? saved;
  String? savedName, pickTitle, saveTitle;
  @override
  Future<CaptureFile?> pickCsv({String title = '导入 PD 报文'}) async {
    pickTitle = title;
    return picked;
  }

  @override
  Future<String?> saveCsv(
    String name,
    Uint8List bytes, {
    String title = '导出 PD 报文',
  }) async {
    savedName = name;
    saveTitle = title;
    saved = bytes;
    return name;
  }
}
