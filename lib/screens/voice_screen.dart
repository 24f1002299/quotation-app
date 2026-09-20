/// Day 6 — Voice capture screen using device microphone + OpenAI Whisper.
///
/// State machine:
///   idle → recording → transcribing → hasTranscript
///                  ↓ (cancel)
///               idle
///
/// The user can also skip recording entirely and use the demo transcript for
/// their selected trade.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../catalog/catalog.dart';
import '../parser/demo_transcripts.dart';
import '../parser/transcript_parser.dart';
import '../screens/review_screen.dart';
import '../theme.dart';
import '../voice/whisper_service.dart';

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
  String? _audioPath;
  String? _errorMessage;

  final _transcriptCtrl = TextEditingController();

  // Pulse animation on the mic button while recording
  late final AnimationController _pulse;

  // Duration counter while recording
  int _recSeconds = 0;
  // ignore: cancel_subscriptions
  late final Stream<int> _ticker;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _ticker = Stream.periodic(const Duration(seconds: 1), (n) => n + 1);
  }

  @override
  void dispose() {
    _recorder.dispose();
    _transcriptCtrl.dispose();
    _pulse.dispose();
    super.dispose();
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _showError('Microphone permission denied.\nPlease grant it in Settings.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/quote_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
        path: path,
      );
      setState(() {
        _state = _RecordState.recording;
        _audioPath = path;
        _recSeconds = 0;
        _errorMessage = null;
      });
    } catch (e) {
      _showError('Could not start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    if (path == null || !(await File(path).exists())) {
      _showError('Recording failed — try again or use the demo.');
      setState(() => _state = _RecordState.idle);
      return;
    }
    setState(() => _state = _RecordState.transcribing);
    await _transcribeFile(File(path));
  }

  Future<void> _cancelRecording() async {
    await _recorder.stop();
    setState(() {
      _state = _RecordState.idle;
      _recSeconds = 0;
    });
  }

  // ── Whisper transcription ─────────────────────────────────────────────────

  Future<void> _transcribeFile(File audio) async {
    try {
      final transcript = await WhisperService.transcribe(audio);
      if (!mounted) return;
      _transcriptCtrl.text = transcript;
      setState(() => _state = _RecordState.hasTranscript);
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString().replaceFirst('Exception: ', ''));
      setState(() => _state = _RecordState.idle);
    }
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

    // Show any parser warnings as a SnackBar before navigation
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
          initialLineItems:
              result.items.map((i) => i.toQuoteLineItem()).toList(),
        ),
      ),
    );
  }

  void _reRecord() {
    _transcriptCtrl.clear();
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
            const SizedBox(width: 10),
            tradeBadge,
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(kPagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Error banner ────────────────────────────────────────────
              if (_errorMessage != null)
                _ErrorBanner(
                  message: _errorMessage!,
                  onDismiss: () => setState(() => _errorMessage = null),
                ),

              const SizedBox(height: 16),

              // ── Central area (state-dependent) ──────────────────────────
              Expanded(
                child: _state == _RecordState.hasTranscript
                    ? _TranscriptEditor(
                        ctrl: _transcriptCtrl,
                        onReRecord: _reRecord,
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Animated mic button
                          _MicButton(
                            state: _state,
                            pulse: _pulse,
                            onStart: _startRecording,
                            onStop: _stopRecording,
                          ),

                          const SizedBox(height: 20),

                          // Status text
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

              // Recording cancel & demo buttons (shown in idle/recording)
              if (_state == _RecordState.recording) ...[
                OutlinedButton(
                  onPressed: _cancelRecording,
                  child: const Text('Cancel / रद्द करें'),
                ),
                const SizedBox(height: 12),
              ],

              if (_state == _RecordState.idle) ...[
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
          'Tap to start speaking',
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
        Text(
          'Powered by OpenAI Whisper',
          style: tt.bodySmall,
          textAlign: TextAlign.center,
        ),
      ];

  List<Widget> _recordingHint(TextTheme tt, ColorScheme cs) => [
        StreamBuilder<int>(
          stream: _ticker,
          builder: (_, snap) {
            final s = snap.data ?? _recSeconds;
            final mm = (s ~/ 60).toString().padLeft(2, '0');
            final ss = (s % 60).toString().padLeft(2, '0');
            return Text(
              '$mm:$ss',
              style: tt.displaySmall?.copyWith(
                color: cs.error,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          'Recording… tap the mic to stop',
          style: tt.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ];

  List<Widget> _transcribingHint(TextTheme tt, ColorScheme cs) => [
        CircularProgressIndicator(color: cs.primary),
        const SizedBox(height: 20),
        Text(
          'Transcribing with Whisper…',
          style: tt.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'This usually takes 2–5 seconds.',
          style: tt.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ];
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
        onTap: isTranscribing
            ? null
            : (isRecording ? onStop : onStart),
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
            isRecording
                ? Icons.stop_rounded
                : Icons.mic_rounded,
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
  final VoidCallback onReRecord;

  const _TranscriptEditor({required this.ctrl, required this.onReRecord});

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
              hintText: 'Edit the transcript if needed…',
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
          'You can correct any mistakes before creating the quote.',
          style: tt.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────────────────

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

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

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
      child: Row(
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
    );
  }
}
