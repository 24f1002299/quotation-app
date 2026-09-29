import 'package:flutter/material.dart';

import '../theme.dart';

/// Day 22 — Concise in-app privacy notice.
///
/// Plain language, Hindi-first. Summarises what the app collects, what it
/// never collects, retention, and how to request export/deletion.
/// Full policy lives in docs/privacy-notice.md.
class PrivacyNoticeScreen extends StatelessWidget {
  const PrivacyNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy / गोपनीयता')),
      body: ListView(
        padding: const EdgeInsets.all(kPagePadding),
        children: [
          Text('Your data stays yours / आपका डेटा आपका है', style: tt.titleLarge),
          const SizedBox(height: 12),
          _point(
            tt,
            'What we keep / हम क्या रखते हैं',
            'Your business profile, saved rates, quotations on this phone, '
            'and (only if you opt in) diagnostic correction notes. '
            'Cloud sync keeps the same data privately under your own login.',
          ),
          _point(
            tt,
            'What we never keep / हम क्या नहीं रखते',
            'No voice recordings by default. No diagnostic transcript copy '
            'unless you turn it on in Profile → Privacy. '
            'The OpenAI key stays on our server and never reaches your phone.',
          ),
          _point(
            tt,
            'Microphone / माइक',
            'The mic is used only while you tap record, only to make your '
            'quote. Nothing is uploaded without showing you the record '
            'button and purpose first. You can always type instead.',
          ),
          _point(
            tt,
            'How long / कितने समय तक',
            'Drafts and sent quotes stay until you delete them. Correction '
            'notes are deleted automatically when their quote is deleted. '
            'See Profile → Privacy to export or delete your data anytime.',
          ),
          _point(
            tt,
            'Your rights / आपके अधिकार',
            'Export a copy of your data, delete everything on this phone, '
            'or ask us to delete your cloud copy: Profile → Privacy → '
            'Export / Delete. Support contact is on the Home help link.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/profile'),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Open Privacy settings / सेटिंग खोलें'),
          ),
        ],
      ),
    );
  }

  Widget _point(TextTheme tt, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tt.titleMedium),
          const SizedBox(height: 4),
          Text(body, style: tt.bodyMedium),
        ],
      ),
    );
  }
}
