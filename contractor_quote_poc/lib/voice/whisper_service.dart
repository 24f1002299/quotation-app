/// Day 6 — OpenAI Whisper API wrapper.
///
/// Accepts a recorded audio [File] and returns the transcribed text.
/// Pure Dart — no Flutter import.
library;

import 'dart:io';
import 'transcription_service.dart';

class WhisperService {
  const WhisperService._();

  /// Deprecated legacy entrypoint — delegates to the secure [TranscriptionService].
  static Future<String> transcribe(File audioFile) async {
    final result = await TranscriptionService.transcribe(
      audioFile: audioFile,
      durationSeconds: 15,
    );
    return result.transcript;
  }
}

