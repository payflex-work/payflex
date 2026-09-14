// Shared helpers for the SCF demo capture harnesses.
//
// These render frames of the demo at 393x852 logical pixels (2x) using the
// app's real theme tokens and widgets. Nothing here fakes protocol behavior —
// harnesses pass in already-computed real values (verified requests, real
// signatures, real transaction hashes) and this file only draws them.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:payflex/theme/payflex_tokens.dart';

const frameW = 393.0;
const frameH = 852.0;

/// Renders one demo frame and captures it as PNG bytes.
///
/// Fixed pumps, never pumpAndSettle: the AnimatedOpticalQr's sweep controller
/// repeats forever and would never settle. Capture is wrapped in runAsync so
/// the real async image encoding is not starved by the test FakeAsync zone.
Future<Uint8List> renderFrame(
  WidgetTester tester,
  Widget child, {
  double pixelRatio = 2.0,
}) async {
  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(frameW, frameH)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(
            color: PfColors.navy,
            child: SizedBox(width: frameW, height: frameH, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 90));
  await tester.pump(const Duration(milliseconds: 90));
  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = (await tester
      .runAsync(() => boundary.toImage(pixelRatio: pixelRatio)))!;
  final ByteData? data = await tester
      .runAsync<ByteData?>(() => image.toByteData(format: ImageByteFormat.png));
  return data!.buffer.asUint8List();
}

/// Demo screen chrome: device label + screen title over the brand background.
class DemoChrome extends StatelessWidget {
  final String deviceLabel;
  final String title;
  final Widget body;
  const DemoChrome({
    super.key,
    required this.deviceLabel,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 46, 18, 14),
          color: PfColors.navyRaised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(deviceLabel,
                  style: const TextStyle(
                      color: PfColors.onNavyFaint,
                      fontSize: 11,
                      letterSpacing: 1.4)),
              const SizedBox(height: 2),
              Text(title,
                  style: const TextStyle(
                      color: PfColors.onNavy,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

class StatusRow extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final String text;
  const StatusRow(
      {super.key, required this.icon, required this.tone, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: tone),
      const SizedBox(width: 10),
      Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: PfColors.onNavy,
                  fontSize: 14,
                  fontWeight: FontWeight.w600))),
    ]);
  }
}

class Panel extends StatelessWidget {
  final Widget child;
  const Panel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: PfColors.navyRaised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

String naira(int minor) =>
    '₦${(minor ~/ 100).toString()}.${(minor % 100).toString().padLeft(2, '0')}';

/// Writes collected PNGs to disk; called from a plain (non-FakeAsync) test
/// so file IO is not constrained by the widget-test zone.
void flushPngs(String dir, Map<String, Uint8List> frames) {
  Directory(dir).createSync(recursive: true);
  frames.forEach((name, png) {
    File('$dir/$name.png').writeAsBytesSync(png, flush: true);
    stderr.writeln('FRAME $name ${png.length}B');
  });
}
