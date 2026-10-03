import 'package:flutter/material.dart';

import '../screens/review_screen.dart';
import '../screens/voice_screen.dart';
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
