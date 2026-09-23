/// Day 9 — Voice capture and reviewable transcript UX.
///
/// Implements:
/// - Microphone permission handling with recovery path
/// - Start, stop, cancel controls with pulse animation
/// - Elapsed time display with conservative 60-second limit and auto-stop
/// - Language choice: Hindi, Marathi, Hinglish / Auto
/// - Uploads over HTTPS to authenticated Spring Boot endpoint (Groq Whisper default)
/// - Temporary audio file deleted immediately upon transcription or cancellation
/// - Draft persistence with uncertainty metadata
/// - Safe error handling: never loses typed draft on failure
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../catalog/catalog.dart';
import '../config/api_config.dart';
import '../models/extraction_models.dart';
import '../models/transcript_draft.dart';
import '../parser/demo_transcripts.dart';
import '../parser/transcript_parser.dart';
import '../screens/review_screen.dart';
import '../storage/rate_memory_repository.dart';
import '../storage/transcript_draft_repository.dart';
import '../theme.dart';
import '../voice/extraction_service.dart';
import '../voice/transcription_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State machine
// ─────────────────────────────────────────────────────────────────────────────
enum _RecordState { idle, recording, transcribing, extracting, hasTranscript }

// ─────────────────────────────────────────────────────────────────────────────
// VoiceScreen
// ─────────────────────────────────────────────────────────────────────────────
class VoiceScreen extends StatefulWidget {
  final Trade trade;
  const VoiceScreen({super.key, required this.trade});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen>
    with SingleTickerProviderStateMixin {
  _RecordState _state = _RecordState.idle;
  final _recorder = AudioRecorder();

  String? _errorMessage;
  bool _permissionDenied = false;

  final _transcriptCtrl = TextEditingController();
  UncertaintyMetadata _uncertainty = const UncertaintyMetadata();

  // Selected language for Groq Whisper STT
  String _selectedLanguage = 'auto'; // 'auto', 'hi', 'mr'

  // Pulse animation on the mic button while recording
  late final AnimationController _pulse;

  // Elapsed duration counter while recording
  int _recSeconds = 0;
  Timer? _timer;
  File? _currentAudioFile;

  // Guards against stale async results overwriting a newer sample:
  // every new recording/transcription bumps this; completions with an old
  // sequence number are ignored. Also prevents the saved draft loaded at
  // startup from clobbering a fresh transcription.
  int _transcriptionSeq = 0;

  // Extraction incremental status
  String _extractionStatusMessage = 'Extracting items... / काम और मात्रा ढूंढ रहे हैं...';
  Timer? _extractionTimer;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _transcriptCtrl.addListener(_onTranscriptChanged);
    _loadExistingDraft();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _extractionTimer?.cancel();
    _recorder.dispose();
    _transcriptCtrl.removeListener(_onTranscriptChanged);
    _transcriptCtrl.dispose();
    _pulse.dispose();
    super.dispose();
  }

  // ── Draft loading & auto-save ─────────────────────────────────────────────

  Future<void> _loadExistingDraft() async {
    final draft = await TranscriptDraftRepository.getDraft(widget.trade);
    if (!mounted || draft == null || draft.transcript.trim().isEmpty) return;
    // Don't clobber a fresh transcription that already populated the field
    // while the async draft load was in flight.
    if (_transcriptCtrl.text.trim().isNotEmpty) return;

    setState(() {
      _transcriptCtrl.text = draft.transcript;
      _selectedLanguage = draft.language;
      _uncertainty = draft.uncertainty;
      _state = _RecordState.hasTranscript;
    });
  }

  void _onTranscriptChanged() {
    final text = _transcriptCtrl.text.trim();
    if (text.isEmpty) return;

    final draft = TranscriptDraft(
      id: 'draft_${widget.trade.name}',
      trade: widget.trade,
      transcript: text,
      language: _selectedLanguage,
      provider: kDefaultSttProvider,
      uncertainty: _uncertainty,
      updatedAt: DateTime.now(),
    );
    TranscriptDraftRepository.saveDraft(draft);
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      setState(() {
        _permissionDenied = true;
        _errorMessage =
            'Microphone permission is needed to record. You can still type a quote.';
      });
      return;
    }

    setState(() {
      _permissionDenied = false;
      _errorMessage = null;
    });

    // Invalidate any in-flight transcription from a previous sample.
    _transcriptionSeq++;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/quote_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final targetFile = File(path);

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
        ),
        path: path,
      );

      _currentAudioFile = targetFile;
      _recSeconds = 0;

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          _recSeconds++;
        });

        // Conservative maximum duration limit: automatically stop and process
        if (_recSeconds >= kMaxRecordingDurationSeconds) {
          _stopRecording();
        }
      });

      setState(() {
        _state = _RecordState.recording;
      });
    } catch (e) {
      _showError('Could not start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (_state != _RecordState.recording) return;
    _timer?.cancel();
    final path = await _recorder.stop();

    if (path == null || !(await File(path).exists())) {
      _showError('Recording failed — try again or enter details manually.');
      setState(() => _state = _RecordState.idle);
      return;
    }

    final recordedFile = File(path);
    _currentAudioFile = recordedFile;

    final length = await recordedFile.length();
    if (length == 0) {
      _showError('No voice detected or recording was empty. Please speak clearly into the microphone and try again.');
      setState(() => _state = _RecordState.idle);
      return;
    }
    // Crumb guard: a fraction of a second of audio (accidental tap, or the
    // auto-started re-record stopped instantly) makes Whisper hallucinate
    // fluent text instead of failing. Don't send crumbs to STT at all.
    if (length < 4 * 1024 || _recSeconds < 2) {
      debugPrint(
          '[Voice] recording too short/quiet: ${length}B, ${_recSeconds}s — '
          'asking user to re-record instead of sending to STT');
      await TranscriptionService.deleteTemporaryAudio(recordedFile);
      _currentAudioFile = null;
      setState(() {
        _errorMessage =
            'Recording was too short — we probably didn\'t catch anything. '
            'Tap Re-record (it starts listening immediately), speak for a few seconds, then tap stop.';
        _state = _RecordState.idle;
        _recSeconds = 0;
      });
      return;
    }
    // Emulator / silent-mic guard: a few seconds of real speech at 16 kHz mono
    // AAC is tens of KB. Anything under ~8 KB is almost certainly silence
    // (emulator mic muted, host mic permission missing), and Whisper will
    // hallucinate instead of transcribing — which looks like "wrong transcript".
    if (length < 8 * 1024 || _recSeconds < 2) {
      debugPrint(
          '[Voice] suspiciously small/quiet recording: ${length}B, ${_recSeconds}s — '
          'likely silent mic, still sending to STT for diagnosis');
    } else {
      debugPrint('[Voice] recording ready: ${length}B, ${_recSeconds}s -> sending to STT');
    }

    setState(() => _state = _RecordState.transcribing);
    await _transcribeAudio(recordedFile, _recSeconds);
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }

    if (_currentAudioFile != null) {
      await TranscriptionService.deleteTemporaryAudio(_currentAudioFile);
      _currentAudioFile = null;
    }

    if (_state == _RecordState.recording && mounted) {
      setState(() {
        _state = _RecordState.idle;
        _recSeconds = 0;
      });
    } else {
      _recSeconds = 0;
    }
  }

  // ── Groq Whisper Transcription ─────────────────────────────────────────────

  Future<void> _transcribeAudio(File audio, int duration) async {
    final seq = ++_transcriptionSeq;
    debugPrint(
        '[Voice] transcribe start seq=$seq lang=$_selectedLanguage duration=${duration}s');
    try {
      final result = await TranscriptionService.transcribe(
        audioFile: audio,
        durationSeconds: duration,
        languageHint: _selectedLanguage,
        provider: kDefaultSttProvider,
      );
      debugPrint(
          '[Voice] transcribe done seq=$seq provider=${result.provider} '
          'chars=${result.transcript.length} text="${result.transcript.length > 120 ? '${result.transcript.substring(0, 120)}…' : result.transcript}"');

      if (!mounted || seq != _transcriptionSeq) {
        // A newer recording superseded this one — discard the stale result
        // but still clean up its temp file.
        await TranscriptionService.deleteTemporaryAudio(audio);
        return;
      }

      final newTranscript = result.transcript.trim();
      if (newTranscript.isEmpty) {
        setState(() {
          _errorMessage =
              'Transcription came back empty. Please try again or type the quote manually.';
          _state = _transcriptCtrl.text.trim().isNotEmpty
              ? _RecordState.hasTranscript
              : _RecordState.idle;
        });
        await TranscriptionService.deleteTemporaryAudio(audio);
        _currentAudioFile = null;
        return;
      }

      setState(() {
        // Assign via value (not just .text) so the field visibly refreshes
        // even when the previous sample had content.
        _transcriptCtrl.value = TextEditingValue(
          text: result.transcript,
          selection: TextSelection.collapsed(offset: result.transcript.length),
        );
        _uncertainty = result.uncertainty;
        _state = _RecordState.hasTranscript;
        // Server-side clarity warning (e.g. mic noise transcribed as a foreign
        // language): show it prominently instead of silently accepting garbage.
        _errorMessage = result.uncertainty.reason;
      });

      // Overwrite the saved draft with THIS sample (not via listener ordering).
      final draft = TranscriptDraft(
        id: 'draft_${widget.trade.name}',
        trade: widget.trade,
        transcript: result.transcript,
        language: _selectedLanguage,
        provider: result.provider,
        uncertainty: result.uncertainty,
        updatedAt: DateTime.now(),
      );
      await TranscriptDraftRepository.saveDraft(draft);

      // Clean up temporary audio file after successful transcription
      await TranscriptionService.deleteTemporaryAudio(audio);
      _currentAudioFile = null;
    } catch (e) {
      if (!mounted || seq != _transcriptionSeq) {
        await TranscriptionService.deleteTemporaryAudio(audio);
        return;
      }

      // Clean up temporary audio file on failure
      await TranscriptionService.deleteTemporaryAudio(audio);
      _currentAudioFile = null;

      String msg;
      final errStr = e.toString();
      final lowerErr = errStr.toLowerCase();
      if (e is SocketException ||
          errStr.contains('Connection refused') ||
          errStr.contains('Failed host lookup') ||
          errStr.contains('ClientException')) {
        msg = 'Cannot connect to backend server ($kApiBaseUrl).\n'
            'Start the Spring Boot API (cd spring-api; .\\run-dev.ps1) or use "Use Demo" below to test.';
      } else if (lowerErr.contains('incorrect api key') ||
          lowerErr.contains('invalid api key') ||
          lowerErr.contains('xai_api_key') ||
          lowerErr.contains('grok stt') ||
          lowerErr.contains('whisper') ||
          lowerErr.contains('groq')) {
        msg = 'Voice service key is missing or invalid on the server (Groq Whisper).\n'
            'Check GROQ key in spring-api/.env (OPENAI_API_KEY=gsk-..., OPENAI_STT_URL=https://api.groq.com/openai/v1/audio/transcriptions, OPENAI_STT_MODEL=whisper-large-v3-turbo), '
            'restart the API (cd spring-api; .\\run-dev.ps1) and try again.';
      } else if (e is HttpException) {
        msg = e.message;
      } else {
        msg = 'Could not transcribe recording: $e. Your draft is safe.';
      }

      setState(() {
        _errorMessage = msg;
        // Keep in transcript mode if user already typed anything, else idle
        _state = _transcriptCtrl.text.trim().isNotEmpty
            ? _RecordState.hasTranscript
            : _RecordState.idle;
      });
    }
  }

  // ── Manual Quote Fallback ─────────────────────────────────────────────────

  void _createManually() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          trade: widget.trade,
          initialLineItems: const [],
        ),
      ),
    );
  }

  // ── Demo shortcut ─────────────────────────────────────────────────────────

  void _useDemo() {
    // Cancel any in-flight transcription so it can't overwrite the demo text.
    _transcriptionSeq++;
    final text = widget.trade == Trade.tiling
        ? kTilingDemoTranscript
        : kPaintingDemoTranscript;
    _transcriptCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _state = _RecordState.hasTranscript;
      _errorMessage = null;
    });
    _onTranscriptChanged();
  }

  // ── Navigate to review ────────────────────────────────────────────────────

  void _createQuote() async {
    final text = _transcriptCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _state = _RecordState.extracting;
      _extractionStatusMessage = 'Extracting items... / काम और मात्रा ढूंढ रहे हैं...';
      _errorMessage = null;
    });

    _extractionTimer?.cancel();
    int step = 0;
    _extractionTimer = Timer.periodic(const Duration(milliseconds: 900), (t) {
      if (!mounted || _state != _RecordState.extracting) {
        t.cancel();
        return;
      }
      step++;
      setState(() {
        if (step == 1) {
          _extractionStatusMessage = 'Checking catalog... / कैटलॉग से मिला रहे हैं...';
        } else if (step >= 2) {
          _extractionStatusMessage = 'Applying saved rates... / दरें जोड़ रहे हैं...';
        }
      });
    });

    try {
      final result = await ExtractionService.extract(
        transcript: text,
        trade: widget.trade,
        languageHint: _selectedLanguage,
      );

      _extractionTimer?.cancel();
      if (!mounted) return;

      final warnings = <String>[
        if (result.errorMessage != null) result.errorMessage!,
        ...result.unknowns.map((u) => 'Review needed: ${u.text} (${u.reason})'),
      ];

      if (warnings.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(warnings.first),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: warnings.length > 1
                ? SnackBarAction(
                    label: '+${warnings.length - 1} more',
                    onPressed: () {},
                  )
                : null,
          ),
        );
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            trade: widget.trade,
            originalTranscript: text,
            parsingWarnings: warnings,
            initialLineItems:
                result.lineItems.map((i) => i.toQuoteLineItem()).toList(),
          ),
        ),
      );
    } catch (e) {
      _extractionTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _state = _RecordState.hasTranscript;
        _errorMessage =
            'Could not extract quote details: $e. Your transcript is saved.';
      });
    }
  }

  void _reRecord() async {
    // Invalidate any in-flight transcription so a late response can't
    // repopulate the field right after the user cleared it.
    _transcriptionSeq++;
    await _cancelRecording();
    _transcriptCtrl.clear();
    await TranscriptDraftRepository.clearDraft(widget.trade);
    if (!mounted) return;
    setState(() {
      _state = _RecordState.idle;
      _errorMessage = null;
    });
    // Start recording immediately: previously Re-record only cleared the field
    // and went idle, so speaking right after did nothing — the mic was never
    // open. That is the "re-record doesn't pick up my voice" bug.
    await _startRecording();
  }

  void _showError(String msg) {
    setState(() => _errorMessage = msg);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final tradeBadge = Chip(
      label: Text(
        widget.trade == Trade.tiling ? '🪣 Tiling' : '🖌️ Painting',
        style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      backgroundColor: cs.primary.withValues(alpha: 0.15),
      side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                'Speak Quote',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            tradeBadge,
          ],
        ),
        actions: [
          // Language selector dropdown as per design.md
          _LanguagePicker(
            selected: _selectedLanguage,
            onChanged: (lang) => setState(() => _selectedLanguage = lang),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Keep the Create-Quote CTA above the keyboard instead of inside the
      // body Column: previously the editor (Expanded) + buttons + keyboard
      // exceeded the viewport by ~31px (RenderFlex bottom overflow).
      bottomNavigationBar: _state == _RecordState.hasTranscript
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    kPagePadding, 8, kPagePadding, kPagePadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _createQuote,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label:
                          const Text('Create Quote / कोटेशन बनाएं'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _createManually,
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text(
                          'Type quote instead / लिखकर बनाएं'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(kPagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Permission Recovery Banner ──────────────────────────────
              if (_permissionDenied)
                _PermissionRecoveryBanner(
                  onAllow: _startRecording,
                  onTypeManually: _createManually,
                ),

              // ── Error banner ────────────────────────────────────────────
              if (_errorMessage != null && !_permissionDenied)
                _ErrorBanner(
                  message: _errorMessage!,
                  onDismiss: () => setState(() => _errorMessage = null),
                  onRetry: _state == _RecordState.idle
                      ? _startRecording
                      : (_state == _RecordState.hasTranscript
                          // Low-clarity transcript (mic warning): retry means
                          // re-record, not extraction of garbage text.
                          ? (_uncertainty.reason != null
                              ? _reRecord
                              : _createQuote)
                          : null),
                  onManual: _createManually,
                ),

              const SizedBox(height: 12),

              // ── Central area (state-dependent) ──────────────────────────
              // Flexible (not Expanded) + scrollable idle content so the
              // keyboard can shrink this area without overflowing.
              Flexible(
                child: _state == _RecordState.hasTranscript
                    ? _TranscriptEditor(
                        ctrl: _transcriptCtrl,
                        uncertainty: _uncertainty,
                        onReRecord: _reRecord,
                      )
                    : SingleChildScrollView(
                        child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_state != _RecordState.extracting) ...[
                            // Guidance hint
                            Text(
                              'Tell us the work and quantities',
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.trade == Trade.tiling
                                  ? 'Example: “Kitchen wall tiles, 120 square feet.”'
                                  : 'Example: “Wall putty, 1200 square feet.”',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 36),

                            // Animated mic button
                            _MicButton(
                              state: _state,
                              pulse: _pulse,
                              onStart: _startRecording,
                              onStop: _stopRecording,
                            ),

                            const SizedBox(height: 24),
                          ],

                          // Status text & timer
                          if (_state == _RecordState.idle)
                            ..._idleHint(tt)
                          else if (_state == _RecordState.recording)
                            ..._recordingHint(tt, cs)
                          else if (_state == _RecordState.transcribing)
                            ..._transcribingHint(tt, cs)
                          else if (_state == _RecordState.extracting)
                            ..._extractingHint(tt, cs),
                        ],
                      ),
                      ),

              ),

              // ── Bottom actions ──────────────────────────────────────────
              if (_state == _RecordState.hasTranscript)
                const SizedBox(height: 8),

              // Recording controls (Cancel during recording)
              if (_state == _RecordState.recording) ...[
                OutlinedButton(
                  onPressed: _cancelRecording,
                  child: const Text('Cancel / रद्द करें'),
                ),
                const SizedBox(height: 12),
              ],

              if (_state == _RecordState.idle) ...[
                OutlinedButton.icon(
                  onPressed: _createManually,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Type quote instead / लिखकर बनाएं'),
                ),
                const SizedBox(height: 16),
                const _DemoSection(),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _useDemo,
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: Text(
                    widget.trade == Trade.tiling
                        ? 'Use Tiling Demo / टाइलिंग डेमो'
                        : 'Use Painting Demo / पेंटिंग डेमो',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── State-specific hint widgets ───────────────────────────────────────────

  List<Widget> _idleHint(TextTheme tt) => [
        Text(
          'Tap to speak / बोलने के लिए टैप करें',
          style: tt.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Hindi · Marathi · Hinglish',
          style: tt.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_rounded, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              'Transcription needs internet · Whisper STT',
              style: tt.bodySmall?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ];

  List<Widget> _recordingHint(TextTheme tt, ColorScheme cs) {
    final mm = (_recSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_recSeconds % 60).toString().padLeft(2, '0');
    final maxMm = (kMaxRecordingDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final maxSs = (kMaxRecordingDurationSeconds % 60).toString().padLeft(2, '0');

    return [
      Text(
        '$mm:$ss / $maxMm:$maxSs',
        style: tt.displaySmall?.copyWith(
          color: cs.error,
          fontWeight: FontWeight.bold,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Recording voice… Tap mic button when finished to transcribe',
        style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
    ];
  }

  List<Widget> _transcribingHint(TextTheme tt, ColorScheme cs) => [
        CircularProgressIndicator(color: cs.primary),
        const SizedBox(height: 20),
        Text(
          'Transcribing with Whisper STT…',
          style: tt.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Turning audio into text. Takes ~2–4 seconds.',
          style: tt.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ];

  List<Widget> _extractingHint(TextTheme tt, ColorScheme cs) => [
        CircularProgressIndicator(color: cs.primary),
        const SizedBox(height: 20),
        Text(
          _extractionStatusMessage,
          style: tt.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Matching catalog & applying saved rates. Your transcript is safe.',
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// _LanguagePicker — visible in app bar
// ─────────────────────────────────────────────────────────────────────────────
class _LanguagePicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _LanguagePicker({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: selected,
      onSelected: onChanged,
      tooltip: 'Language selection',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 16),
            const SizedBox(width: 6),
            Text(
              _labelFor(selected),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'auto',
          child: Text('Auto (Hinglish/हिंदी/मराठी)'),
        ),
        PopupMenuItem(
          value: 'hi',
          child: Text('Hindi (हिंदी)'),
        ),
        PopupMenuItem(
          value: 'mr',
          child: Text('Marathi (मराठी)'),
        ),
      ],
    );
  }

  String _labelFor(String code) {
    switch (code) {
      case 'hi':
        return 'हिंदी';
      case 'mr':
        return 'मराठी';
      default:
        return 'Auto';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MicButton
// ─────────────────────────────────────────────────────────────────────────────
class _MicButton extends StatelessWidget {
  final _RecordState state;
  final AnimationController pulse;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _MicButton({
    required this.state,
    required this.pulse,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRecording = state == _RecordState.recording;
    final isTranscribing = state == _RecordState.transcribing;
    final color = isRecording ? cs.error : cs.primary;

    return AnimatedBuilder(
      animation: pulse,
      builder: (_, child) {
        final scale = isRecording ? 1.0 + 0.08 * pulse.value : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: GestureDetector(
        onTap: isTranscribing ? null : (isRecording ? onStop : onStart),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: isRecording ? 0.2 : 0.15),
            border: Border.all(
              color: color,
              width: isRecording ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: isRecording ? 24 : 10,
                spreadRadius: isRecording ? 4 : 0,
              ),
            ],
          ),
          child: Icon(
            isRecording ? Icons.stop_rounded : Icons.mic_rounded,
            size: 54,
            color: color,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TranscriptEditor — editable text area shown after transcription
// ─────────────────────────────────────────────────────────────────────────────
class _TranscriptEditor extends StatelessWidget {
  final TextEditingController ctrl;
  final UncertaintyMetadata uncertainty;
  final VoidCallback onReRecord;

  const _TranscriptEditor({
    required this.ctrl,
    required this.uncertainty,
    required this.onReRecord,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    // Hide the helper hint while the keyboard is open to save ~30px and
    // avoid the RenderFlex bottom overflow seen with ime visible.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                'Transcript / प्रतिलेख',
                style: tt.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (uncertainty.isUncertain)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber),
                    SizedBox(width: 4),
                    Text('Review needed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: onReRecord,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Re-record'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: ctrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: tt.bodyLarge,
            decoration: InputDecoration(
              hintText: 'Edit the transcript if needed… / यहाँ सुधार करें',
              hintStyle: const TextStyle(color: Color(0xFF9E9BA8)),
              filled: true,
              fillColor: const Color(0xFF13131F),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF2E2E42)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF2E2E42)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ),
        if (!keyboardOpen) ...[
          const SizedBox(height: 10),
          Text(
            'You can correct any mistakes before creating the quote. Draft is auto-saved.',
            style: tt.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Permission & Error Recovery Banners
// ─────────────────────────────────────────────────────────────────────────────

class _PermissionRecoveryBanner extends StatelessWidget {
  final VoidCallback onAllow;
  final VoidCallback onTypeManually;

  const _PermissionRecoveryBanner({
    required this.onAllow,
    required this.onTypeManually,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mic_off_rounded, color: Colors.amber, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Microphone permission is needed to record. You can still type a quote.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onTypeManually,
                child: const Text('Type quote'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: onAllow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  minimumSize: const Size(0, 36),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Allow microphone'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  final VoidCallback? onRetry;
  final VoidCallback? onManual;

  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
    this.onRetry,
    this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: cs.error, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message, style: tt.bodyMedium),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (onRetry != null || onManual != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onManual != null)
                  TextButton(
                    onPressed: onManual,
                    child: const Text('Create manually'),
                  ),
                if (onRetry != null) ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DemoSection extends StatelessWidget {
  const _DemoSection();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('or use a demo', style: tt.bodySmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
