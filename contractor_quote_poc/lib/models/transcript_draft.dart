import '../catalog/catalog.dart';

/// Day 9 — Uncertainty metadata returned by the Grok / Whisper STT backend.
class UncertaintyMetadata {
  final bool isUncertain;
  final double confidence;
  final String provider;
  final bool requiresReview;

  const UncertaintyMetadata({
    this.isUncertain = false,
    this.confidence = 1.0,
    this.provider = 'grok',
    this.requiresReview = true,
  });

  factory UncertaintyMetadata.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const UncertaintyMetadata();
    }
    return UncertaintyMetadata(
      isUncertain: json['isUncertain'] as bool? ?? false,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      provider: json['provider'] as String? ?? 'grok',
      requiresReview: json['requiresReview'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'isUncertain': isUncertain,
        'confidence': confidence,
        'provider': provider,
        'requiresReview': requiresReview,
      };
}

/// Day 9 — Local draft of an audio transcript and user edits.
///
/// Ensures contractor work is never lost on network or parser failures.
class TranscriptDraft {
  final String id;
  final Trade? trade;
  final String transcript;
  final String language;
  final String provider;
  final UncertaintyMetadata uncertainty;
  final DateTime updatedAt;

  const TranscriptDraft({
    required this.id,
    this.trade,
    required this.transcript,
    this.language = 'auto',
    this.provider = 'grok',
    this.uncertainty = const UncertaintyMetadata(),
    required this.updatedAt,
  });

  TranscriptDraft copyWith({
    String? id,
    Trade? trade,
    String? transcript,
    String? language,
    String? provider,
    UncertaintyMetadata? uncertainty,
    DateTime? updatedAt,
  }) {
    return TranscriptDraft(
      id: id ?? this.id,
      trade: trade ?? this.trade,
      transcript: transcript ?? this.transcript,
      language: language ?? this.language,
      provider: provider ?? this.provider,
      uncertainty: uncertainty ?? this.uncertainty,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'trade': trade?.name,
        'transcript': transcript,
        'language': language,
        'provider': provider,
        'uncertainty': uncertainty.toJson(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TranscriptDraft.fromJson(Map<String, dynamic> json) {
    Trade? parsedTrade;
    if (json['trade'] != null) {
      final tStr = json['trade'] as String;
      parsedTrade = Trade.values.cast<Trade?>().firstWhere(
            (t) => t?.name == tStr,
            orElse: () => null,
          );
    }

    return TranscriptDraft(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      trade: parsedTrade,
      transcript: json['transcript'] as String? ?? '',
      language: json['language'] as String? ?? 'auto',
      provider: json['provider'] as String? ?? 'grok',
      uncertainty: UncertaintyMetadata.fromJson(
        json['uncertainty'] as Map<String, dynamic>?,
      ),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
