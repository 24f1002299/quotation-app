/// Day 9 — Voice capture and reviewable transcript UX.
///
/// Implements:
/// - Microphone permission handling with recovery path
/// - Start, stop, cancel controls with pulse animation
/// - Elapsed time display with conservative 60-second limit and auto-stop
/// - Language choice: Hindi, Marathi, Hinglish / Auto
/// - Uploads over HTTPS to authenticated Spring Boot endpoint (Grok STT default)
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
import '../models/transcript_draft.dart';
import '../parser/demo_transcripts.dart';
import '../parser/transcript_parser.dart';
import '../screens/review_screen.dart';
import '../storage/transcript_draft_repository.dart';
import '../theme.dart';
import '../voice/transcription_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State machine
// ─────────────────────────────────────────────────────────────────────────────
enum _RecordState { idle, recording, transcribing, hasTranscript }

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

  // Selected language for Grok STT
  String _selectedLanguage = 'auto'; // 'auto', 'hi', 'mr'

  // Pulse animation on the mic button while recording
  late final AnimationController _pulse;

  // Elapsed duration counter while recording
  int _recSeconds = 0;
  Timer? _timer;
  File? _currentAudioFile;

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

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/quote_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final targetFile = File(path);

    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
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
    _timer?.cancel();
    final path = await _recorder.stop();

    if (path == null || !(await File(path).exists())) {
      _showError('Recording failed — try again or enter details manually.');
      setState(() => _state = _RecordState.idle);
      return;
    }

    final recordedFile = File(path);
    _currentAudioFile = recordedFile;

    setState(() => _state = _RecordState.transcribing);
    await _transcribeAudio(recordedFile, _recSeconds);
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    await _recorder.stop();

    if (_currentAudioFile != null) {
      await TranscriptionService.deleteTemporaryAudio(_currentAudioFile);
      _currentAudioFile = null;
    }

    setState(() {
      _state = _RecordState.idle;
      _recSeconds = 0;
    });
  }

  // ── Grok Transcription ────────────────────────────────────────────────────

  Future<void> _transcribeAudio(File audio, int duration) async {
    try {
      final result = await TranscriptionService.transcribe(
        audioFile: audio,
        durationSeconds: duration,
        languageHint: _selectedLanguage,
        provider: kDefaultSttProvider,
      );

      if (!mounted) return;

      setState(() {
        _transcriptCtrl.text = result.transcript;
        _uncertainty = result.uncertainty;
        _state = _RecordState.hasTranscript;
        _errorMessage = null;
      });

      // Save draft immediately
      _onTranscriptChanged();

      // Clean up temporary audio file after successful transcription
      await TranscriptionService.deleteTemporaryAudio(audio);
      _currentAudioFile = null;
    } catch (e) {
      if (!mounted) return;

      // Clean up temporary audio file on failure
      await TranscriptionService.deleteTemporaryAudio(audio);
      _currentAudioFile = null;

      final msg = e is SocketException
          ? 'Transcription needs internet connection. Your draft is safe.'
          : 'We could not turn this recording into text. Your draft is safe.';

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
    final text = widget.trade == Trade.tiling
        ? kTilingDemoTranscript
        : kPaintingDemoTranscript;
    _transcriptCtrl.text = text;
    setState(() {
      _state = _RecordState.hasTranscript;
      _errorMessage = null;
    });
  }

  // ── Navigate to review ────────────────────────────────────────────────────

  void _createQuote() {
    final text = _transcriptCtrl.text.trim();
    if (text.isEmpty) return;

    final result = const TranscriptParser().parse(text);

    if (result.hasWarnings) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.warnings.first),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          action: result.warnings.length > 1
              ? SnackBarAction(
                  label: '+${result.warnings.length - 1} more',
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
          parsingWarnings: result.warnings,
          initialLineItems:
              result.items.map((i) => i.toQuoteLineItem()).toList(),
        ),
      ),
    );
  }

  void _reRecord() {
    _cancelRecording();
    _transcriptCtrl.clear();
    TranscriptDraftRepository.clearDraft(widget.trade);
    setState(() => _state = _RecordState.idle);
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
      backgroundColor: cs.primary.withOpacity(0.15),
      side: BorderSide(color: cs.primary.withOpacity(0.4)),
      visualDensity: VisualDensity.compact,
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Speak Quote / बोलें'),
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
                  onRetry: _state == _RecordState.idle ? _startRecording : null,
                  onManual: _createManually,
                ),

              const SizedBox(height: 12),

              // ── Central area (state-dependent) ──────────────────────────
              Expanded(
                child: _state == _RecordState.hasTranscript
                    ? _TranscriptEditor(
                        ctrl: _transcriptCtrl,
                        uncertainty: _uncertainty,
                        onReRecord: _reRecord,
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
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
                              color: cs.onSurface.withOpacity(0.7),
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

                          // Status text & timer
                          if (_state == _RecordState.idle)
                            ..._idleHint(tt)
                          else if (_state == _RecordState.recording)
                            ..._recordingHint(tt, cs)
                          else if (_state == _RecordState.transcribing)
                            ..._transcribingHint(tt, cs),
                        ],
                      ),
              ),

              // ── Bottom actions ──────────────────────────────────────────
              if (_state == _RecordState.hasTranscript) ...[
                ElevatedButton.icon(
                  onPressed: _createQuote,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Create Quote / कोटेशन बनाएं'),
                ),
                const SizedBox(height: 12),
              ],

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
              'Transcription needs internet · Grok STT',
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
        'Recording… tap the mic to stop',
        style: tt.bodyMedium,
        textAlign: TextAlign.center,
      ),
    ];
  }

  List<Widget> _transcribingHint(TextTheme tt, ColorScheme cs) => [
        CircularProgressIndicator(color: cs.primary),
        const SizedBox(height: 20),
        Text(
          'Transcribing with Grok STT…',
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
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
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
            color: color.withOpacity(isRecording ? 0.2 : 0.15),
            border: Border.all(
              color: color,
              width: isRecording ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Transcript / प्रतिलेख', style: tt.titleMedium),
            const SizedBox(width: 8),
            if (uncertainty.isUncertain)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
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
        const SizedBox(height: 10),
        Text(
          'You can correct any mistakes before creating the quote. Draft is auto-saved.',
          style: tt.bodySmall,
          textAlign: TextAlign.center,
        ),
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
        color: Colors.amber.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.5)),
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
        color: cs.error.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withOpacity(0.4)),
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
