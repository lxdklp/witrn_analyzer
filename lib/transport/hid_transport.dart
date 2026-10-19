import 'dart:typed_data';

const defaultUsbVendorId = 0x0716;
const defaultUsbProductId = 0x5060;

final class DeviceInfo {
  const DeviceInfo({
    required this.path,
    required this.name,
    required this.serial,
    required this.interfaceNumber,
  });
  final String path, name, serial;
  final int interfaceNumber;
  String get label =>
      '$name · 接口 $interfaceNumber${serial.isEmpty ? '' : ' · $serial'}';
}

enum ReportLayout { automatic, raw64, reportId65 }

abstract interface class HidTransport {
  Stream<Uint8List> get reports;
  Uint8List? get descriptor;
  Future<List<DeviceInfo>> enumerate({
    int vendorId = defaultUsbVendorId,
    int productId = defaultUsbProductId,
  });

  /// Sets the maximum rate of native HID reads without reopening the device.
  Future<void> setReadRate(int hz);
  Future<void> open(
    DeviceInfo device, {
    ReportLayout layout = ReportLayout.automatic,
    int vendorId = defaultUsbVendorId,
    int productId = defaultUsbProductId,
  });
  Future<void> close();
  Future<void> dispose();
}

/// Native report boundaries are preserved by the vendored hid_tool patch.
/// A 65-byte report is stripped only when its ID is proven by the descriptor,
/// or the user has explicitly selected the extra-ID layout.
Uint8List normalizeReport(Uint8List report, ReportLayout layout, Set<int> ids) {
  if (report.length == 64 && layout != ReportLayout.reportId65) {
    return Uint8List.fromList(report);
  }
  if (report.length == 65 &&
      layout != ReportLayout.raw64 &&
      (layout == ReportLayout.reportId65 || ids.contains(report[0]))) {
    return Uint8List.fromList(report.sublist(1));
  }
  throw FormatException(
    '收到 ${report.length} 字节 HID 报告，无法按所选布局解析。请核对报告描述符及 Report ID。',
  );
}
