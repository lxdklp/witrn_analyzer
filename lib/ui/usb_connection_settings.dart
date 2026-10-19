import 'package:flutter/material.dart';

import '../application/app_settings.dart';
import '../transport/hid_transport.dart';

class UsbConnectionSettings extends StatefulWidget {
  const UsbConnectionSettings({
    super.key,
    required this.settings,
    required this.enabled,
  });

  final AppSettings settings;
  final bool enabled;

  @override
  State<UsbConnectionSettings> createState() => _UsbConnectionSettingsState();
}

class _UsbConnectionSettingsState extends State<UsbConnectionSettings> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _vid, _pid;
  late int _savedVid, _savedPid;

  @override
  void initState() {
    super.initState();
    _savedVid = widget.settings.usbVendorId;
    _savedPid = widget.settings.usbProductId;
    _vid = TextEditingController(text: _hex(_savedVid));
    _pid = TextEditingController(text: _hex(_savedPid));
  }

  static String _hex(int value) =>
      value.toRadixString(16).padLeft(4, '0').toUpperCase();

  @override
  void didUpdateWidget(covariant UsbConnectionSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_savedVid != widget.settings.usbVendorId ||
        _savedPid != widget.settings.usbProductId) {
      _savedVid = widget.settings.usbVendorId;
      _savedPid = widget.settings.usbProductId;
      _vid.text = _hex(_savedVid);
      _pid.text = _hex(_savedPid);
    }
  }

  @override
  void dispose() {
    _vid.dispose();
    _pid.dispose();
    super.dispose();
  }

  int? _parse(String? input) {
    final text = (input ?? '').trim();
    if (!RegExp(r'^(?:0[xX])?[0-9a-fA-F]{1,4}$').hasMatch(text)) return null;
    return int.parse(text.replaceFirst(RegExp(r'^0[xX]'), ''), radix: 16);
  }

  Future<void> _save() async {
    if (!widget.enabled || !_form.currentState!.validate()) return;
    final vendorId = _parse(_vid.text)!;
    final productId = _parse(_pid.text)!;
    _vid.text = _hex(vendorId);
    _pid.text = _hex(productId);
    await widget.settings.setUsbDeviceIds(
      vendorId: vendorId,
      productId: productId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.settings.persistenceError ?? '已保存，下次扫描和连接时生效。'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card.filled(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.enabled
                  ? '使用十六进制 VID / PID 查找 USB HID 设备，保存后用于下次扫描和连接。'
                  : '请先断开设备并等待当前操作完成，再修改连接标识。',
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (label, controller, key) in [
                  ('VID', _vid, 'usb-vid'),
                  ('PID', _pid, 'usb-pid'),
                ]) ...[
                  if (label == 'PID') const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey(key),
                      controller: controller,
                      enabled: widget.enabled,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: label,
                        helperText: '十六进制',
                        errorMaxLines: 3,
                      ),
                      validator: (value) => _parse(value) == null
                          ? '请输入 1–4 位十六进制数，可带 0x 前缀'
                          : null,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: widget.enabled ? _save : null,
                  child: const Text('保存 VID / PID'),
                ),
                TextButton(
                  onPressed: widget.enabled
                      ? () async {
                          _vid.text = _hex(defaultUsbVendorId);
                          _pid.text = _hex(defaultUsbProductId);
                          await _save();
                        }
                      : null,
                  child: const Text('恢复默认'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
