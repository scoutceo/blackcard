import 'package:flutter/services.dart';

const kBlack = Color(0xFF000000);
const kGrey = Color(0xFF8E8E93);
const kSheet = Color(0xFF1C1C1E);
const kHairline = Color(0xFF2C2C2E);
const kWhite = Color(0xFFF2F2F7);

/// ISO/IEC 7810 ID-1 card proportions (85.60 × 53.98 mm).
const kCardAspect = 85.60 / 53.98;

/// Corner radius of a card, as a fraction of its width.
const kCardRadius = 0.045;

/// Talks to MainActivity.kt.
const native = MethodChannel('blackcard/native');
