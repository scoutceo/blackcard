import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// How long the screen stays up waiting for a reader before closing itself.
const kTimeout = Duration(seconds: 60);

const kBlack = Color(0xFF000000);
const kGrey = Color(0xFF8E8E93);

/// ISO/IEC 7810 ID-1 card proportions (85.60 × 53.98 mm).
const kCardAspect = 85.60 / 53.98;

const _native = MethodChannel('blackcard/native');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: kBlack,
    systemNavigationBarColor: kBlack,
    systemNavigationBarDividerColor: kBlack,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const BlackcardApp());
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

class _PayScreenState extends State<PayScreen>
    with SingleTickerProviderStateMixin {
  Uint8List? _card;
  bool _loaded = false;
  Timer? _timeout;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void initState() {
    super.initState();
    _native.setMethodCallHandler((call) async {
      if (call.method == 'shown') _onShown();
    });
    _onShown();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _intro.dispose();
    super.dispose();
  }

  /// Called on every launch (the engine is pre-warmed and reused).
  Future<void> _onShown() async {
    _restartTimeout();
    _intro.forward(from: 0);
    if (!_loaded) await _loadCard();
  }

  void _restartTimeout() {
    _timeout?.cancel();
    _timeout = Timer(kTimeout, () => _native.invokeMethod('close'));
  }

  Future<void> _loadCard() async {
    Uint8List? bytes;
    try {
      final path = await _native.invokeMethod<String>('cardPath');
      if (path != null) bytes = await File(path).readAsBytes();
    } on PlatformException catch (_) {
      // Not running on the Android host (e.g. widget tests): show placeholder.
    } on MissingPluginException catch (_) {}
    if (!mounted) return;
    setState(() {
      _card = bytes;
      _loaded = true;
    });
  }

  Future<void> _pickCard() async {
    _timeout?.cancel();
    try {
      final path = await _native.invokeMethod<String>('pickCard');
      if (path != null) {
        final bytes = await File(path).readAsBytes();
        if (mounted) setState(() => _card = bytes);
      }
    } on PlatformException catch (_) {
      // Picker cancelled or copy failed: keep the current card.
    } finally {
      _restartTimeout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);

    return Scaffold(
      backgroundColor: kBlack,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          return Column(
            children: [
              SizedBox(height: box.maxHeight * 0.06),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: FadeTransition(
                  opacity: curve,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.12),
                      end: Offset.zero,
                    ).animate(curve),
                    child: GestureDetector(
                      // Long-press the card to change it; tap only when empty.
                      onLongPress: _pickCard,
                      onTap: _card == null && _loaded ? _pickCard : null,
                      child: _CardFace(bytes: _card, loaded: _loaded),
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 5),
              FadeTransition(opacity: curve, child: const _HoldNearReader()),
              const Spacer(flex: 4),
            ],
          );
        }),
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
    return LayoutBuilder(builder: (context, box) {
      final radius = BorderRadius.circular(box.maxWidth * 0.045);
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
            border: Border.all(color: const Color(0xFF2C2C2E), width: 1.5),
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
    });
  }
}

class _HoldNearReader extends StatelessWidget {
  const _HoldNearReader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.contactless_outlined, color: kGrey, size: 44),
        SizedBox(height: 10),
        Text(
          'Hold Near Reader',
          style: TextStyle(
            color: kGrey,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}
