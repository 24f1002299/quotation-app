import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../storage/app_preferences.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';

/// Screen 0 — first-launch language picker (Hindi / English / Marathi).
/// One decision, made once; changeable later in Settings.
class LanguagePickerScreen extends StatefulWidget {
  final ValueChanged<String> onChosen;
  const LanguagePickerScreen({super.key, required this.onChosen});

  @override
  State<LanguagePickerScreen> createState() => _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends State<LanguagePickerScreen> {
  String _pending = 'hi';

  Future<void> _choose(String code) async {
    setState(() => _pending = code);
    HapticFeedback.selectionClick();
    await AppPreferences.setLanguage(code);
    await AppPreferences.setLanguageChosen();
    widget.onChosen(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: kForest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.mic_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.text(_pending, 'app_name'),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: kInk,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                AppStrings.text(_pending, 'choose_language'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: kInk,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _LangButton(
                      label: 'हिंदी',
                      sub: 'Hindi',
                      selected: _pending == 'hi',
                      onTap: () => setState(() => _pending = 'hi'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LangButton(
                      label: 'English',
                      sub: 'English',
                      selected: _pending == 'en',
                      onTap: () => setState(() => _pending = 'en'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _LangButton(
                label: 'मराठी',
                sub: 'Marathi',
                selected: _pending == 'mr',
                onTap: () => setState(() => _pending = 'mr'),
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.text(_pending, 'language_note'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: kInkMuted, height: 1.5),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _choose(_pending),
                child: Text(AppStrings.text(_pending, 'continue')),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangButton extends StatelessWidget {
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  const _LangButton({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? kSage.withValues(alpha: 0.3) : kSurfaceCard,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          border: Border.all(
            color: selected ? kForest : kSurfaceMuted,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: selected ? kForest : kInk,
              ),
            ),
            Text(sub, style: const TextStyle(fontSize: 12, color: kInkMuted)),
          ],
        ),
      ),
    );
  }
}
