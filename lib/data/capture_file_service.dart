import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'csv_capture_codec.dart';

final class CaptureFile {
  const CaptureFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

abstract interface class CaptureFileService {
  Future<CaptureFile?> pickCsv({String title = '导入 PD 报文'});
  Future<String?> saveCsv(
    String name,
    Uint8List bytes, {
    String title = '导出 PD 报文',
  });
}

final class NativeCaptureFileService implements CaptureFileService {
  @override
  Future<CaptureFile?> pickCsv({String title = '导入 PD 报文'}) async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      dialogTitle: title,
    );
    if (result == null) return null;
    final file = result;
    if ((await file.length() ?? 0) > CsvCaptureCodec.maxFileBytes) {
      throw const FormatException('CSV 文件不能超过 64 MiB');
    }
    return CaptureFile(file.name, await file.readAsBytes());
  }

  @override
  Future<String?> saveCsv(
    String name,
    Uint8List bytes, {
    String title = '导出 PD 报文',
  }) async => (await FilePicker.saveFile(
    dialogTitle: title,
    fileName: name,
    type: FileType.custom,
    allowedExtensions: ['csv'],
    mimeType: 'text/csv',
    bytes: bytes,
  ))?.toString();
}
