import 'package:flutter/material.dart';

// ── Primary palette (design.md light system, warm-tinted surface) ──
const Color kSurface = Color(0xFFF7F7F5); // warm off-white page background
const Color kSurfaceCard = Color(0xFFFFFFFF); // card backgrounds
const Color kSurfaceMuted = Color(0xFFE8E8E6); // dividers, disabled fills
const Color kForest = Color(0xFF475841); // primary CTA, headings, totals
const Color kForestLight = Color(0xFF5A7350); // pressed state
const Color kSage = Color(0xFF9FB8AD); // info highlights, selected states
const Color kInk = Color(0xFF2D2D2D); // primary body text
const Color kInkMuted = Color(0xFF737373); // secondary / hint text

// ── Semantic colors ──
const Color kAttention = Color(0xFFE8890B); // warnings (saffron kept here)
const Color kError = Color(0xFFD93025); // destructive actions
const Color kSuccess = Color(0xFF1B8A4B); // confirmations

// ── Legacy design.md aliases (kept so old imports keep compiling) ──
const Color appBackground = kSurface;
const Color surfaceMuted = kSurfaceMuted;
const Color sage = kSage;
const Color forest = kForest;
const Color ink = kInk;
