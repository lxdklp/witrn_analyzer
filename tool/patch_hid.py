"""Apply project-local fixes to the vendored, unmodified hid_tool 0.1.3 release."""
from pathlib import Path
root = Path('third_party/hid_tool')
p = root / 'lib/src/hid_device.dart'
s = p.read_text().replace('  Stream<int> inputStream();', '  Stream<int> inputStream();\n\n  /// One owned byte buffer per native read; preserves HID report boundaries.\n  Stream<Uint8List> inputReports();')
p.write_text(s)
for backend in ['desktop', 'android']:
 p = root / f'lib/src/{backend}/hid_device_{backend}.dart'
 s = p.read_text().replace('  Stream<int> inputStream() async* {', '''  Stream<int> inputStream() => inputReports().expand((report) => report);

  @override
  Stream<Uint8List> inputReports() async* {''')
 if backend == 'desktop':
  s = s.replace('''          for (var i = 0; i < result; i++) {
            yield buffer[i];
          }''', '          yield Uint8List.fromList(buffer.asTypedList(result));')
  s = s.replace("        throw HidException('Failed to set non blocking mode. '", "        _hidapi.hid_close(_device);\n        _device = nullptr;\n        throw HidException('Failed to set non blocking mode. '")
 else:
  s = s.replace('''      for (final byte in report) {
        yield byte;
      }''', '      if (report.isNotEmpty) yield report;')
 p.write_text(s)
# Allow the application to change native read cadence without replacing streams.
p = root / 'lib/src/hid_device.dart'
s = p.read_text().replace('Stream<Uint8List> inputReports();',
    'Stream<Uint8List> inputReports({Duration Function()? readInterval});')
p.write_text(s)
for backend in ['desktop', 'android']:
 p = root / f'lib/src/{backend}/hid_device_{backend}.dart'
 s = p.read_text().replace('Stream<Uint8List> inputReports() async* {',
     'Stream<Uint8List> inputReports({Duration Function()? readInterval}) async* {')
 if backend == 'desktop':
  s = s.replace('''      while (isOpen) {
        final result''', '''      final readClock = Stopwatch();
      while (isOpen) {
        readClock.reset();
        readClock.start();
        final result''')
  s = s.replace('''        // Polling with 1ms interval for better power efficiency
        await Future.delayed(const Duration(milliseconds: 1));''', '''        final interval = readInterval?.call() ?? const Duration(milliseconds: 1);
        final remaining = interval - readClock.elapsed;
        await Future<void>.delayed(
          remaining.isNegative ? Duration.zero : remaining,
        );''')
 else:
  s = s.replace('''    while (isOpen) {
      Uint8List report;''', '''    final readClock = Stopwatch();
    while (isOpen) {
      readClock.reset();
      readClock.start();''')
  s = s.replace('''        report = await receiveReport(''', '''        final report = await receiveReport(''')
  s = s.replace('''      } on TimeoutException {
        continue;
      }

      if (report.isNotEmpty) yield report;''', '''        if (report.isNotEmpty) yield report;
      } on TimeoutException {
        // Empty reads count toward the polling limit as well.
      }
      final interval = readInterval?.call() ?? Duration.zero;
      final remaining = interval - readClock.elapsed;
      await Future<void>.delayed(
        remaining.isNegative ? Duration.zero : remaining,
      );''')
 p.write_text(s)
p = root / 'lib/src/desktop/hid_desktop.dart'
s = p.read_text().replace('// Skip device\n        continue;', '// Skip device, advancing the enumeration linked list.\n        current = info.next;\n        continue;')
p.write_text(s)
p = root / 'android/src/main/kotlin/com/github/ardwang/hid_tool/HidToolPlugin.kt'
s = p.read_text().replace('import android.os.Build', 'import android.os.Build\nimport android.os.Handler\nimport android.os.Looper\nimport java.util.concurrent.Executors')
s = s.replace('  private lateinit var channel : MethodChannel', '''  // All USB operations, permission completions and detach cleanup share one queue.
  private val ioExecutor = Executors.newSingleThreadExecutor()
  private val mainHandler = Handler(Looper.getMainLooper())
  private lateinit var channel : MethodChannel''')
# Serialize broadcast handling with I/O and closing, including permission completions.
s = s.replace('    override fun onReceive(context: Context?, intent: Intent?) {', '''    override fun onReceive(context: Context?, intent: Intent?) {
      if (!ioExecutor.isShutdown) ioExecutor.execute { handleBroadcast(context, intent) }
    }
    private fun handleBroadcast(context: Context?, intent: Intent?) {''')
s = s.replace('  override fun onMethodCall(call: MethodCall, result: Result) {', '''  override fun onMethodCall(call: MethodCall, result: Result) {
    if (ioExecutor.isShutdown) {
      result.error("DETACHED", "Plugin is detached.", null)
      return
    }
    ioExecutor.execute { handleMethodCall(call, result) }
  }

  private fun handleMethodCall(call: MethodCall, result: Result) {''')
s = s.replace('''    stopListeningInternal()
    unregisterPermissionReceiver()
    closeAllSessions()
    channel.setMethodCallHandler(null)''', '''    channel.setMethodCallHandler(null)
    ioExecutor.execute {
      stopListeningInternal()
      unregisterPermissionReceiver()
      closeAllSessions()
      for (requests in pendingPermissionRequests.values) {
        for (request in requests) request.result.error("DETACHED", "Plugin detached.", null)
      }
      pendingPermissionRequests.clear()
    }
    ioExecutor.shutdown()''')
# All channel invocations (not replies) need Android's main thread.
s = s.replace('channel.invokeMethod(method, payload)', 'mainHandler.post { channel.invokeMethod(method, payload) }')
p.write_text(s)
p=Path('pubspec.yaml');p.write_text(p.read_text().replace('  hid_tool: 0.1.3','  hid_tool:\n    path: third_party/hid_tool'))
