import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_config.dart';
import '../models/transcript_draft.dart';

/// Result object returned by [TranscriptionService.transcribe].
class TranscriptionResult {
  final String transcript;
  final String provider;
  final String language;
  final int latencyMs;
  final int audioSizeBytes;
  final UncertaintyMetadata uncertainty;

  const TranscriptionResult({
    required this.transcript,
    required this.provider,
    required this.language,
    required this.latencyMs,
    required this.audioSizeBytes,
    required this.uncertainty,
  });
}

/// Day 9 — Production-grade voice transcription client.
///
/// Sends audio only to the authenticated Spring Boot backend.
/// Grok STT and OpenAI credentials stay strictly on the server.
class TranscriptionService {
  const TranscriptionService._();

  /// Uploads [audioFile] to the authenticated Spring Boot transcription endpoint.
  ///
  /// Enforces conservative size and duration constraints before network transit.
  /// Does not write raw audio or transcripts to logs.
  static Future<TranscriptionResult> transcribe({
    required File audioFile,
    required int durationSeconds,
    String languageHint = 'auto',
    String provider = kDefaultSttProvider,
    http.Client? client,
  }) async {
    // 1. Pre-upload file validation
    if (!await audioFile.exists()) {
      throw const FileSystemException('Audio recording file not found on device.');
    }

    final fileSizeBytes = await audioFile.length();
    if (fileSizeBytes == 0) {
      throw const FormatException('Recorded audio is empty (0 bytes).');
    }

    if (fileSizeBytes > kMaxAudioFileSizeBytes) {
      throw FormatException(
        'Audio size (${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB) '
        'exceeds the 10 MB maximum limit.',
      );
    }

    if (durationSeconds > kMaxRecordingDurationSeconds + 5) {
      throw FormatException(
        'Audio duration ($durationSeconds s) exceeds the maximum allowed limit.',
      );
    }

    final httpClient = client ?? http.Client();
    final uri = Uri.parse('$kApiBaseUrl/transcribe');

    final request = http.MultipartRequest('POST', uri);

    // 2. Attach authenticated Supabase JWT session token if available
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && session.accessToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    } catch (_) {
      // In dev mode / mock without active Supabase session, server handles dev fallback
    }

    // 3. Add parameters
    request.fields['provider'] = provider;
    request.fields['language'] = languageHint;
    request.fields['durationSeconds'] = durationSeconds.toString();

    // 4. Attach audio file
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        audioFile.path,
        filename: 'recording.m4a',
      ),
    );

    // 5. Send with 30s timeout
    try {
      final streamedResponse = await httpClient.send(request).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw const SocketException(
          'Transcription request timed out. Please check your internet connection.',
        ),
      );

      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 429) {
        throw const HttpException(
          'Rate limit reached. Please wait a moment before sending another recording.',
        );
      }

      if (streamedResponse.statusCode == 413) {
        throw const HttpException('The audio recording is too large for the server.');
      }

      if (streamedResponse.statusCode == 401) {
        throw const HttpException('Authentication error. Please sign in again.');
      }

      if (streamedResponse.statusCode != 200) {
        String serverMsg = 'Server error (${streamedResponse.statusCode})';
        try {
          final errJson = json.decode(responseBody) as Map<String, dynamic>;
          if (errJson.containsKey('message')) {
            serverMsg = errJson['message'] as String;
          }
        } catch (_) {}
        throw HttpException(serverMsg);
      }

      final jsonMap = json.decode(responseBody) as Map<String, dynamic>;

      final transcript = (jsonMap['transcript'] as String? ?? '').trim();
      final actualProvider = jsonMap['provider'] as String? ?? provider;
      final actualLang = jsonMap['language'] as String? ?? languageHint;
      final latencyMs = jsonMap['latencyMs'] as int? ?? 0;
      final audioSize = jsonMap['audioSizeBytes'] as int? ?? fileSizeBytes;

      final uncertainty = UncertaintyMetadata.fromJson(
        jsonMap['uncertaintyMetadata'] as Map<String, dynamic>?,
      );

      return TranscriptionResult(
        transcript: transcript,
        provider: actualProvider,
        language: actualLang,
        latencyMs: latencyMs,
        audioSizeBytes: audioSize,
        uncertainty: uncertainty,
      );
    } on SocketException catch (_) {
      throw const SocketException(
        'Transcription requires an internet connection. Please check your network and retry.',
      );
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Safely deletes the temporary audio recording file after processing or cancellation.
  static Future<void> deleteTemporaryAudio(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup failures to not disturb the user
    }
  }
}
