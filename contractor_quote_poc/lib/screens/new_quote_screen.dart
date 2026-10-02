import 'package:flutter/material.dart';

import '../parser/demo_transcripts.dart';
import '../parser/transcript_parser.dart';
import '../screens/review_screen.dart';
import '../screens/voice_screen.dart';
import '../storage/service_item_repository.dart';
import '../templates/template_data.dart';
import '../theme.dart';
import '../widgets/business_type_chips.dart';

/// Choose the work you sell, then speak or type the quote.
///
/// The starter template for the chosen business type seeds the user's service
/// list, and [ReviewScreen]'s add-item sheet offers those services.
class NewQuoteScreen extends StatefulWidget {
  const NewQuoteScreen({super.key});

  @override
  State<NewQuoteScreen> createState() => _NewQuoteScreenState();
}

class _NewQuoteScreenState extends State<NewQuoteScreen> {
  BusinessType? _selectedType;

  void _selectType(BusinessType businessType) =>
      setState(() => _selectedType = businessType);

  void _proceed({required bool voiceMode}) {
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose your work first / पहले काम चुनें'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (voiceMode) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VoiceScreen(businessType: _selectedType!),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            businessType: _selectedType,
            initialLineItems: const [],
          ),
        ),
      );
    }
  }

  /// Parse the demo transcript for [businessType] and jump straight to review
  /// with pre-filled line items. Also selects that business type.
  Future<void> _useDemoTranscript(BusinessType businessType) async {
    setState(() => _selectedType = businessType);
    final transcript = businessType == BusinessType.tiling
        ? kTilingDemoTranscript
        : kPaintingDemoTranscript;
    final services = await ServiceItemRepository.seedFromTemplate(businessType);
    final rateMap = await ServiceItemRepository.getRateMap(businessType);
    final result = const TranscriptParser()
        .parse(transcript, services: services, savedRates: rateMap);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          businessType: businessType,
          originalTranscript: transcript,
          parsingWarnings: result.warnings,
          initialLineItems: result.items.map((i) => i.toQuoteLineItem()).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New Quote / नया कोटेशन')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(kPagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),

              Text('Choose your work / काम चुनें', style: tt.titleLarge),
              const SizedBox(height: 16),

              BusinessTypeChips(
                selected: _selectedType ?? BusinessType.tiling,
                onChanged: _selectType,
              ),

              const SizedBox(height: 20),

              // ── Demo shortcut ──────────────────────────────────────────
              Text(
                '— or try a demo / डेमो देखें —',
                style: tt.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _useDemoTranscript(BusinessType.tiling),
                      icon: const Icon(Icons.grid_4x4_rounded, size: 18),
                      label: const Text('Tiling Demo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _useDemoTranscript(BusinessType.painting),
                      icon: const Icon(Icons.format_paint_rounded, size: 18),
                      label: const Text('Painting Demo'),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              ElevatedButton.icon(
                // Greyed out until a business type is chosen
                onPressed: _selectedType == null
                    ? null
                    : () => _proceed(voiceMode: true),
                icon: const Icon(Icons.mic_rounded),
                label: const Text('Speak Quote / बोलें'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _selectedType == null
                    ? null
                    : () => _proceed(voiceMode: false),
                child: const Text('Enter Manually / खुद भरें'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
