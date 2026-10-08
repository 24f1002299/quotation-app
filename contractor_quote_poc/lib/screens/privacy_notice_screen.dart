import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
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
      appBar: AppBar(title: Text(AppStrings.of(context, 'privacy_notice'))),
      body: ListView(
        padding: const EdgeInsets.all(kPagePadding),
        children: [
          Text(AppStrings.of(context, 'privacy_title'),
              style: tt.titleLarge),
          const SizedBox(height: 12),
          _point(
            tt,
            AppStrings.of(context, 'privacy_keep_title'),
            AppStrings.of(context, 'privacy_keep_body'),
          ),
          _point(
            tt,
            AppStrings.of(context, 'privacy_never_title'),
            AppStrings.of(context, 'privacy_never_body'),
          ),
          _point(
            tt,
            AppStrings.of(context, 'privacy_mic_title'),
            AppStrings.of(context, 'privacy_mic_body'),
          ),
          _point(
            tt,
            AppStrings.of(context, 'privacy_retention_title'),
            AppStrings.of(context, 'privacy_retention_body'),
          ),
          _point(
            tt,
            AppStrings.of(context, 'privacy_rights_title'),
            AppStrings.of(context, 'privacy_rights_body'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/profile'),
            icon: const Icon(Icons.settings_outlined),
            label: Text(AppStrings.of(context, 'open_privacy_settings')),
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
