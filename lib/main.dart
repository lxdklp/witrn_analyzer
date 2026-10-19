import 'package:flutter/widgets.dart';

import 'app.dart';
import 'application/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(WitrnAnalyzerApp(settings: settings));
}
