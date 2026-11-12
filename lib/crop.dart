import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'style.dart';

/// Width in pixels of the saved, cropped card (height follows the card ratio).
const _outputWidth = 1600;

/// Longest side a picked photo is decoded at. The S26's 200 MP shots would
/// otherwise need ~800 MB of RAM.
const _maxDecodeSide = 2800;

/// Full-screen editor: pinch, drag and twist the picked image inside a
/// card-shaped frame. Pops with the cropped card as PNG bytes, or null.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.sourcePath});

  final String sourcePath;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  ui.Image? _image;
  String? _error;
  bool _saving = false;

  Rect _frame = Rect.zero;
  Offset _offset = Offset.zero;
  double _scale = 1;
  double _rotation = 0;

  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  double _startScale = 1;
  double _startRotation = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final bytes = await File(widget.sourcePath).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (w, h) {
          final longest = math.max(w, h);
          if (longest <= _maxDecodeSide)
            return ui.TargetImageSize(width: w, height: h);
          final k = _maxDecodeSide / longest;
          return ui.TargetImageSize(
            width: (w * k).round(),
            height: (h * k).round(),
          );
        },
      );
      final frame = await codec.getNextFrame();
      if (!mounted) return frame.image.dispose();
      setState(() => _image = frame.image);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't open that image");
    }
  }

  void _reset() => setState(() {
    _offset = Offset.zero;
    _scale = 1;
    _rotation = 0;
  });

  void _rotate90() => setState(() {
    _rotation =
        (_rotation / (math.pi / 2)).round() * (math.pi / 2) + math.pi / 2;
  });

  /// Snap to the nearest quarter turn when within 3°, so straight cards stay straight.
  void _snapRotation() {
    const quarter = math.pi / 2;
    final nearest = (_rotation / quarter).round() * quarter;
    if ((_rotation - nearest).abs() < 3 * math.pi / 180) {
      setState(() => _rotation = nearest);
    }
  }

  Future<void> _save() async {
    final image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);

    final outH = (_outputWidth / kCardAspect).round();
    final k = _outputWidth / _frame.width;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(k)
      ..translate(-_frame.left, -_frame.top);
    _painter(image).paintImage(canvas);
    final out = await recorder.endRecording().toImage(_outputWidth, outH);
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    if (!mounted) return;
    Navigator.of(context).pop(png?.buffer.asUint8List());
  }

  _CropPainter _painter(ui.Image image) => _CropPainter(
    image: image,
    frame: _frame,
    offset: _offset,
    scale: _scale,
    rotation: _rotation,
  );

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      backgroundColor: kBlack,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              'Move and Scale',
              style: TextStyle(
                color: kWhite,
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth - 40;
                  final h = w / kCardAspect;
                  _frame = Rect.fromLTWH(20, (box.maxHeight - h) * 0.42, w, h);
                  final rrect = RRect.fromRectAndRadius(
                    _frame,
                    Radius.circular(w * kCardRadius),
                  );

                  if (image == null) {
                    return Center(
                      child: Text(
                        _error ?? '',
                        style: const TextStyle(color: kGrey),
                      ),
                    );
                  }
                  final painter = _painter(image);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: _reset,
                    onScaleStart: (d) {
                      _startOffset = _offset;
                      _startFocal = d.focalPoint;
                      _startScale = _scale;
                      _startRotation = _rotation;
                    },
                    onScaleUpdate: (d) => setState(() {
                      _offset = _startOffset + (d.focalPoint - _startFocal);
                      _scale = (_startScale * d.scale).clamp(0.2, 12.0);
                      _rotation = _startRotation + d.rotation;
                    }),
                    onScaleEnd: (_) => _snapRotation(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // The whole image, dimmed, so you can see what's outside the card.
                        Opacity(
                          opacity: 0.28,
                          child: CustomPaint(painter: painter),
                        ),
                        ClipRRect(
                          clipper: _RRectClipper(rrect),
                          child: CustomPaint(painter: painter),
                        ),
                        CustomPaint(painter: _FrameOutline(rrect)),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: _frame.bottom + 24,
                          child: const Text(
                            'Pinch, drag or twist to fit your card',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: kGrey,
                              fontSize: 14,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: kGrey, fontSize: 17),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: image == null ? null : _rotate90,
                    tooltip: 'Rotate',
                    icon: const Icon(
                      Icons.rotate_90_degrees_ccw_outlined,
                      color: kGrey,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: image == null || _saving ? null : _save,
                    child: Text(
                      _saving ? 'Saving…' : 'Use',
                      style: const TextStyle(
                        color: kWhite,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the image centred on the frame, then offset, rotated and scaled.
/// Used both on screen and for the exported card, so what you see is what
/// gets saved.
class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.frame,
    required this.offset,
    required this.scale,
    required this.rotation,
  });

  final ui.Image image;
  final Rect frame;
  final Offset offset;
  final double scale;
  final double rotation;

  void paintImage(Canvas canvas) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    // At scale 1 the image exactly covers the card frame.
    final cover = math.max(frame.width / iw, frame.height / ih);
    final c = frame.center + offset;
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(rotation)
      ..scale(cover * scale)
      ..drawImage(
        image,
        Offset(-iw / 2, -ih / 2),
        Paint()..filterQuality = FilterQuality.high,
      )
      ..restore();
  }

  @override
  void paint(Canvas canvas, Size size) => paintImage(canvas);

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image ||
      old.frame != frame ||
      old.offset != offset ||
      old.scale != scale ||
      old.rotation != rotation;
}

class _RRectClipper extends CustomClipper<RRect> {
  _RRectClipper(this.rrect);
  final RRect rrect;

  @override
  RRect getClip(Size size) => rrect;

  @override
  bool shouldReclip(_RRectClipper old) => old.rrect != rrect;
}

class _FrameOutline extends CustomPainter {
  _FrameOutline(this.rrect);
  final RRect rrect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_FrameOutline old) => old.rrect != rrect;
}
