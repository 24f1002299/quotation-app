/// Day 6 — OpenAI Whisper API wrapper.
///
/// Accepts a recorded audio [File] and returns the transcribed text.
/// Pure Dart — no Flutter import.
library;

import 'dart:io';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class WhisperService {
  const WhisperService._();

  static const _endpoint =
      'https://api.openai.com/v1/audio/transcriptions';

  /// Send [audioFile] to OpenAI Whisper and return the transcript string.
  ///
  /// Throws an [Exception] if the API key is not configured or if the API
  /// returns a non-200 status.  The caller should catch and surface the error
  /// to the user rather than crashing.
  static Future<String> transcribe(File audioFile) async {
    // Guard against a missing key so the error is developer-friendly.
    if (kOpenAiApiKey.isEmpty || kOpenAiApiKey == 'YOUR_OPENAI_API_KEY') {
      throw Exception(
        'OpenAI API key not configured.\n'
        'Open lib/config/api_config.dart and replace the placeholder with '
        'your key from https://platform.openai.com/api-keys',
      );
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(_endpoint),
    );

    request.headers['Authorization'] = 'Bearer $kOpenAiApiKey';

    // Whisper model — whisper-1 is the current production model.
    request.fields['model'] = 'whisper-1';

    // Prompt Whisper to produce Hinglish (Latin script) rather than pure
    // Devanagari, so our parser can match catalog synonyms and unit keywords.
    request.fields['prompt'] =
        'A contractor speaking a building quotation in Hindi or Hinglish. '
        'Items include tiles, skirting, wall putty, painting. '
        'Use Roman script (Hinglish) in the transcription.';

    // Omit "language" so Whisper auto-detects; constraining to "hi" forces
    // Devanagari output which our parser also handles but Latin is preferred.

    // Ask for plain text — easiest to parse, no JSON overhead.
    request.fields['response_format'] = 'text';

    request.files.add(
      await http.MultipartFile.fromPath('file', audioFile.path),
    );

    final streamed = await request.send().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception(
        'Whisper request timed out. Check your internet connection.',
      ),
    );

    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception(
        'Whisper API error ${streamed.statusCode}: $body',
      );
    }

    return body.trim();
  }
}
