import 'dart:io';

// Use the image package already supplied by flutter_launcher_icons.
// ignore: depend_on_referenced_packages
import 'package:image/image.dart' as img;

/// Prepare Android layers without changing the desktop icons.
void main() {
  const directory = 'assets/branding';
  final source = img.decodePng(
    File('$directory/witrn_analyzer.png').readAsBytesSync(),
  )!;
  final foreground = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );
  final monochrome = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );

  // The artwork uses a teal mark on a neutral background. Chroma separates
  // the mark from the background while retaining partially covered edge pixels.
  for (final pixel in source) {
    final chroma = pixel.b - pixel.r;
    final alpha = chroma < 12
        ? 0
        : ((chroma - 5) / 110 * 255).round().clamp(0, 255);
    foreground.setPixelRgba(pixel.x, pixel.y, 22, 139, 154, alpha);
    monochrome.setPixelRgba(pixel.x, pixel.y, 255, 255, 255, alpha);
  }

  File('$directory/witrn_analyzer_adaptive_foreground.png')
      .writeAsBytesSync(img.encodePng(foreground));
  File('$directory/witrn_analyzer_monochrome.png')
      .writeAsBytesSync(img.encodePng(monochrome));
  stdout.writeln('Prepared Android layers.');
}
