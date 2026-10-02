import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';
import '../theme/dimensions.dart';

export 'mic_button.dart';

/// Thin offline indicator bar (4dp) — replaces banner cards.
class OfflineBar extends StatelessWidget {
  final String label;
  const OfflineBar({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: kAttention,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Draft / Shared / Attention pill badge — always icon + text, never colour alone.
class StatusBadge extends StatelessWidget {
  final String status; // 'draft' | 'shared' | 'attention' | 'ready'
  final String label;
  const StatusBadge({super.key, required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;
    switch (status) {
      case 'shared':
        bg = kSuccess.withValues(alpha: 0.12);
        fg = kSuccess;
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'attention':
        bg = kAttention.withValues(alpha: 0.15);
        fg = const Color(0xFF9A5B00);
        icon = Icons.warning_amber_rounded;
        break;
      default:
        bg = kSage.withValues(alpha: 0.3);
        fg = kForest;
        icon = Icons.description_outlined;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty-state illustration placeholder (text + CTA, no heavy assets).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: kSage.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: kForest),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: kInkMuted, height: 1.5),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

/// Compact single-line quote/draft card used on home + history.
class QuoteCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amount;
  final String? badgeStatus;
  final String? badgeLabel;
  final VoidCallback onTap;

  const QuoteCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.badgeStatus,
    this.badgeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          onTap();
        },
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title.isEmpty ? '—' : title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: kInk,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badgeStatus != null && badgeLabel != null) ...[
                          const SizedBox(width: 8),
                          StatusBadge(
                            status: badgeStatus!,
                            label: badgeLabel!,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: kInkMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: kForest,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: kInkMuted),
            ],
          ),
        ),
      ),
    );
  }
}
