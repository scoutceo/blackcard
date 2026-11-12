import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:blackcard/crop.dart';
import 'package:blackcard/style.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'Use exports a card-shaped PNG',
    timeout: const Timeout(Duration(seconds: 60)),
    (tester) async {
      tester.view.physicalSize = const Size(1440, 3120);
      tester.view.devicePixelRatio = 3.5;
      addTearDown(tester.view.reset);

      // A 400x300 test image on disk, standing in for a picked photo.
      final dir = Directory.systemTemp.createTempSync('blackcard_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final src = File('${dir.path}/source.png');
    await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(
        const Rect.fromLTWH(0, 0, 400, 300),
        Paint()..color = const Color(0xFF3366CC),
      );
      final img = await rec.endRecording().toImage(400, 300);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      src.writeAsBytesSync(data!.buffer.asUint8List());
    });

    Uint8List? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<Uint8List>(
                  MaterialPageRoute(
                    builder: (_) => CropScreen(sourcePath: src.path),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // File I/O and image decoding are real async work: let them run.
      Future<void> settleReal(bool Function() done) async {
        for (var i = 0; i < 60 && !done(); i++) {
          await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
      }

      // The clipped card preview only exists once the image has decoded.
      await settleReal(() => find.byType(ClipRRect).evaluate().isNotEmpty);
      expect(find.byType(ClipRRect), findsOneWidget);

      await tester.tap(find.text('Use'));
      await settleReal(() => result != null);
      await tester.pump(const Duration(seconds: 1));

      expect(result, isNotNull);
      final size = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(result!);
        final frame = await codec.getNextFrame();
        return Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
      });
      expect(size!.width, 1600);
      expect(size.height, (1600 / kCardAspect).roundToDouble());
    },
  );
}
