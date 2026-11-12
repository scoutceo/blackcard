import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'crop.dart';
import 'settings.dart';
import 'style.dart';

/// Card flick: slightly under-damped (ζ ≈ 0.72) so it overshoots a touch and
/// settles in roughly 600 ms.
const _flickSpring = SpringDescription(mass: 1, stiffness: 140, damping: 17);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _applySystemUi();
  runApp(const BlackcardApp());
}

/// Hide the status and navigation bars: nothing on screen but the card.
void _applySystemUi() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: kBlack,
      systemNavigationBarColor: kBlack,
      systemNavigationBarDividerColor: kBlack,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
}

class BlackcardApp extends StatelessWidget {
  const BlackcardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBlack,
        canvasColor: kBlack,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      home: const PayScreen(),
    );
  }
}

class PayScreen extends StatefulWidget {
  const PayScreen({super.key});

  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> with TickerProviderStateMixin {
  Uint8List? _card;
  bool _loaded = false;
  bool _nfcOn = true;
  Settings _settings = Settings.defaults;
  Timer? _timeout;

  /// Bumped on every show/hide so stale async work and delays are ignored.
  int _session = 0;
  bool _landed = false;

  /// 0 = card below the screen, 1 = in place. Unbounded: the spring overshoots.
  late final AnimationController _flick = AnimationController.unbounded(
    vsync: this,
  )..addListener(_onFlickTick);

  late final AnimationController _readerIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// Slow "breathing" of the Hold Near Reader prompt.
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void initState() {
    super.initState();
    // The engine is pre-warmed at process start, before any screen exists, so
    // the session is driven purely by the Activity's shown/hidden events.
    native.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'shown':
          await _onShown();
        case 'hidden':
          _onHidden();
      }
    });
    _loadCard();
    Settings.load().then((s) => _settings = s);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _flick.dispose();
    _readerIn.dispose();
    _breathe.dispose();
    super.dispose();
  }

  Future<void> _onShown() async {
    final session = ++_session;
    _applySystemUi();
    _restartTimeout();
    unawaited(_refreshNfc());
    if (!_loaded) await _loadCard();
    if (!mounted || session != _session) return;

    _breathe.repeat(reverse: true);
    if (MediaQuery.disableAnimationsOf(context)) {
      _flick.value = 1;
      _readerIn.value = 1;
      return;
    }
    _landed = false;
    _flick
      ..value = 0
      ..animateWith(SpringSimulation(_flickSpring, 0, 1, 0));
    _readerIn.value = 0;
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted && session == _session) _readerIn.forward();
    });
  }

  /// Back to the pre-animation state while the Activity is not visible, so
  /// the next launch never shows a stale frame.
  void _onHidden() {
    _session++;
    _timeout?.cancel();
    // The engine outlives the Activity: don't reopen into a half-finished
    // crop or an open settings sheet.
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    _flick
      ..stop()
      ..value = 0;
    _readerIn.value = 0;
    _breathe.stop();
  }

  void _onFlickTick() {
    // A light tick the moment the card first reaches its resting place.
    if (!_landed && _flick.value >= 1) {
      _landed = true;
      HapticFeedback.lightImpact();
    }
  }

  void _restartTimeout() {
    _timeout?.cancel();
    _timeout = Timer(Duration(seconds: _settings.timeoutSeconds), () {
      native.invokeMethod('close').catchError((_) => null);
    });
  }

  Future<void> _refreshNfc() async {
    try {
      final on = await native.invokeMethod<bool>('nfcEnabled');
      if (mounted && on != null && on != _nfcOn) setState(() => _nfcOn = on);
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  Future<void> _loadCard() async {
    Uint8List? bytes;
    try {
      final path = await native.invokeMethod<String>('cardPath');
      if (path != null) bytes = await File(path).readAsBytes();
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
    if (!mounted) return;
    setState(() {
      _card = bytes;
      _loaded = true;
    });
  }

  /// Anything that changes the card or settings needs the phone unlocked,
  /// since this screen can appear over the lock screen.
  Future<bool> _ensureUnlocked() async {
    try {
      return await native.invokeMethod<bool>('unlock') ?? false;
    } on MissingPluginException catch (_) {
      return true;
    }
  }

  /// Pauses the auto-close while [task] runs (picker, crop, settings).
  Future<void> _paused(Future<void> Function() task) async {
    _timeout?.cancel();
    try {
      await task();
    } finally {
      if (mounted) _restartTimeout();
    }
  }

  Future<void> _openSettings() => _paused(() async {
    if (!await _ensureUnlocked() || !mounted) return;
    HapticFeedback.selectionClick();
    final hasSource = await native.invokeMethod<String>('sourcePath') != null;
    if (!mounted) return;
    final action = await showSettingsSheet(
      context,
      settings: _settings,
      canAdjust: hasSource,
      onChanged: (s) {
        if (s.timeoutSeconds != _settings.timeoutSeconds) {
          native.invokeMethod('setTimeout', s.timeoutSeconds);
        }
        if (s.showOnLockScreen != _settings.showOnLockScreen) {
          native.invokeMethod('setShowOnLockScreen', s.showOnLockScreen);
        }
        _settings = s;
      },
    );
    switch (action) {
      case SettingsAction.changeImage:
        await _chooseImage();
      case SettingsAction.adjustImage:
        final source = await native.invokeMethod<String>('sourcePath');
        if (source != null) await _crop(source);
      case null:
    }
  });

  Future<void> _chooseImage() => _paused(() async {
    if (!await _ensureUnlocked()) return;
    try {
      final picked = await native.invokeMethod<String>('pickImage');
      if (picked != null) await _crop(picked);
    } on PlatformException catch (_) {
      // Picker failed: keep the current card.
    }
  });

  Future<void> _crop(String sourcePath) async {
    if (!mounted) return;
    final png = await Navigator.of(context).push<Uint8List>(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => CropScreen(sourcePath: sourcePath),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (png == null) return;
    try {
      await native.invokeMethod<String>('saveCard', png);
      if (mounted) setState(() => _card = png);
    } on PlatformException catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            return Column(
              children: [
                SizedBox(height: box.maxHeight * 0.06),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _Flick(
                    animation: _flick,
                    travel: MediaQuery.sizeOf(context).height,
                    child: GestureDetector(
                      // Long-press for settings; tap only when there's no card yet.
                      onLongPress: _openSettings,
                      onTap: _card == null && _loaded ? _chooseImage : null,
                      child: _CardFace(bytes: _card, loaded: _loaded),
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                _ReaderPrompt(
                  fadeIn: _readerIn,
                  breathe: _breathe,
                  nfcOn: _nfcOn,
                  onOpenNfcSettings: () => native
                      .invokeMethod('openNfcSettings')
                      .catchError((_) => null),
                ),
                const Spacer(flex: 5),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Flicks the card up from below the screen: it starts tilted back in 3D,
/// turned a little and slightly smaller, and springs flat into place.
class _Flick extends AnimatedWidget {
  const _Flick({
    required Animation<double> animation,
    required this.travel,
    required this.child,
  }) : super(listenable: animation);

  final double travel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    // p: 1 at the start, 0 at rest, slightly negative during the overshoot.
    final p = 1 - t;
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0012) // perspective
      ..translateByDouble(0, p * travel * 0.85, 0, 1)
      ..rotateX(p * 0.95)
      ..rotateZ(p * -0.22)
      ..scaleByDouble(1 - p * 0.10, 1 - p * 0.10, 1, 1);
    return Opacity(
      opacity: (t * 3).clamp(0.0, 1.0),
      child: Transform(
        alignment: Alignment.center,
        transform: m,
        // Filter the rotated card so its edges don't shimmer mid-flight.
        filterQuality: p.abs() > 0.001 ? FilterQuality.medium : null,
        child: child,
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.bytes, required this.loaded});

  final Uint8List? bytes;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final radius = BorderRadius.circular(box.maxWidth * kCardRadius);
        final dpr = MediaQuery.devicePixelRatioOf(context);

        final Widget face;
        if (bytes != null) {
          face = Image.memory(
            bytes!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            // Decode at screen resolution, not the photo's full 12+ MP.
            cacheWidth: (box.maxWidth * dpr).round(),
          );
        } else {
          face = DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: kHairline, width: 1.5),
            ),
            child: Center(
              child: loaded
                  ? const Text(
                      'Tap to choose a card image',
                      style: TextStyle(color: kGrey, fontSize: 15),
                    )
                  : null,
            ),
          );
        }

        return AspectRatio(
          aspectRatio: kCardAspect,
          child: ClipRRect(borderRadius: radius, child: face),
        );
      },
    );
  }
}

/// Thin contactless mark + "Hold Near Reader", fading in after the card lands
/// and then breathing slowly between ~60 % and 100 % opacity.
class _ReaderPrompt extends StatelessWidget {
  const _ReaderPrompt({
    required this.fadeIn,
    required this.breathe,
    required this.nfcOn,
    required this.onOpenNfcSettings,
  });

  final Animation<double> fadeIn;
  final Animation<double> breathe;
  final bool nfcOn;
  final VoidCallback onOpenNfcSettings;

  @override
  Widget build(BuildContext context) {
    final inCurve = CurvedAnimation(parent: fadeIn, curve: Curves.easeOut);
    final breathCurve = CurvedAnimation(
      parent: breathe,
      curve: Curves.easeInOutSine,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size.square(40),
          painter: _ContactlessMark(color: kGrey, crossedOut: !nfcOn),
        ),
        const SizedBox(height: 12),
        Text(
          nfcOn ? 'Hold Near Reader' : 'NFC is off',
          style: const TextStyle(
            color: kGrey,
            fontSize: 16,
            fontWeight: FontWeight.w300,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );

    return AnimatedBuilder(
      animation: Listenable.merge([inCurve, breathCurve]),
      builder: (context, child) {
        final breath = nfcOn ? 0.6 + 0.4 * breathCurve.value : 1.0;
        return Opacity(opacity: inCurve.value * breath, child: child);
      },
      child: nfcOn
          ? content
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenNfcSettings,
              child: Padding(padding: const EdgeInsets.all(12), child: content),
            ),
    );
  }
}

/// Four thin concentric arcs: the contactless symbol, drawn so stroke weight
/// can be finer than any icon font allows.
class _ContactlessMark extends CustomPainter {
  const _ContactlessMark({required this.color, this.crossedOut = false});

  final Color color;
  final bool crossedOut;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.042
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final center = Offset(s * 0.08, s / 2);
    const sweep = math.pi * 0.44;
    for (var i = 0; i < 4; i++) {
      final r = s * (0.17 + i * 0.19);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        -sweep / 2,
        sweep,
        false,
        paint,
      );
    }
    if (crossedOut) {
      canvas.drawLine(
        Offset(s * 0.12, s * 0.1),
        Offset(s * 0.95, s * 0.9),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ContactlessMark old) =>
      old.color != color || old.crossedOut != crossedOut;
}
