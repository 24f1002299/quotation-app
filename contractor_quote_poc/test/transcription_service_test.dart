import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/catalog/catalog.dart';
import 'package:contractor_quote_poc/models/transcript_draft.dart';
import 'package:contractor_quote_poc/storage/transcript_draft_repository.dart';
import 'package:contractor_quote_poc/voice/transcription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TranscriptionService', () {
    late Directory tempDir;
    late File testAudioFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('voice_test_');
      testAudioFile = File('${tempDir.path}/test.m4a');
      await testAudioFile.writeAsBytes([1, 2, 3, 4, 5]);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Successfully parses Grok STT candidate transcript and uncertainty metadata', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        expect(request.url.path, endsWith('/transcribe'));
        if (request is http.MultipartRequest) {
          expect(request.fields['provider'], equals('grok'));
          expect(request.fields['language'], equals('hi'));
        }

        final responseJson = json.encode({
          'transcript': '120 square feet kitchen wall tiles and 40 feet skirting',
          'provider': 'grok',
          'language': 'hi',
          'latencyMs': 420,
          'audioSizeBytes': 5,
          'status': 'CANDIDATE_FOR_REVIEW',
          'uncertaintyMetadata': {
            'isUncertain': false,
            'confidence': 0.95,
            'provider': 'grok',
            'requiresReview': true,
          }
        });

        return http.StreamedResponse(
          Stream.value(utf8.encode(responseJson)),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await TranscriptionService.transcribe(
        audioFile: testAudioFile,
        durationSeconds: 15,
        languageHint: 'hi',
        provider: 'grok',
        client: mockClient,
      );

      expect(result.transcript, equals('120 square feet kitchen wall tiles and 40 feet skirting'));
      expect(result.provider, equals('grok'));
      expect(result.language, equals('hi'));
      expect(result.latencyMs, equals(420));
      expect(result.uncertainty.isUncertain, isFalse);
      expect(result.uncertainty.confidence, equals(0.95));
    });

    test('Throws Rate limit HttpException when backend returns 429', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode(json.encode({'error': 'RATE_LIMIT_EXCEEDED', 'message': 'Rate limit reached.'}))),
          429,
        );
      });

      expect(
        () => TranscriptionService.transcribe(
          audioFile: testAudioFile,
          durationSeconds: 10,
          client: mockClient,
        ),
        throwsA(isA<HttpException>().having(
          (e) => e.message,
          'message',
          contains('Rate limit reached'),
        )),
      );
    });

    test('Pre-upload validation rejects empty audio files', () async {
      final emptyFile = File('${tempDir.path}/empty.m4a');
      await emptyFile.writeAsBytes([]);

      expect(
        () => TranscriptionService.transcribe(
          audioFile: emptyFile,
          durationSeconds: 10,
        ),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('0 bytes'),
        )),
      );
    });

    test('Pre-upload validation rejects duration exceeding maximum limit', () async {
      expect(
        () => TranscriptionService.transcribe(
          audioFile: testAudioFile,
          durationSeconds: 100, // exceeds 60s limit
        ),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Audio duration'),
        )),
      );
    });

    test('deleteTemporaryAudio deletes file safely', () async {
      expect(await testAudioFile.exists(), isTrue);
      await TranscriptionService.deleteTemporaryAudio(testAudioFile);
      expect(await testAudioFile.exists(), isFalse);
    });
  });

  group('TranscriptDraftRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Saves, retrieves, and clears draft for selected trade', () async {
      expect(await TranscriptDraftRepository.getDraft(Trade.tiling), isNull);

      final draft = TranscriptDraft(
        id: 'draft_1',
        trade: Trade.tiling,
        transcript: 'Kitchen wall tiles 120 sq ft',
        language: 'hi',
        provider: 'grok',
        uncertainty: const UncertaintyMetadata(isUncertain: false, confidence: 0.95),
        updatedAt: DateTime.now(),
      );

      await TranscriptDraftRepository.saveDraft(draft);

      final loaded = await TranscriptDraftRepository.getDraft(Trade.tiling);
      expect(loaded, isNotNull);
      expect(loaded!.transcript, equals('Kitchen wall tiles 120 sq ft'));
      expect(loaded.trade, equals(Trade.tiling));
      expect(loaded.language, equals('hi'));
      expect(loaded.provider, equals('grok'));

      await TranscriptDraftRepository.clearDraft(Trade.tiling);
      expect(await TranscriptDraftRepository.getDraft(Trade.tiling), isNull);
    });
  });
}
