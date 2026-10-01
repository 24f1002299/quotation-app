import 'package:flutter/material.dart';

import '../../models/quote.dart';

/// Mutable line-item data class for the review flow.
///
/// The immutable [QuoteLineItem] model (used for calculations) is created
/// on demand from these fields via [toLineItem].
class EditableItem {
  TextEditingController description;
  TextEditingController quantity;
  TextEditingController unit;
  TextEditingController rate;
  final double? confidence;
  final String? uncertaintyNote;
  final String? sourceSpan;
  final bool isUnknown;
  bool requiresReview;
  bool acknowledged;

  /// Day 21: catalog id the model picked (if any), carried for feedback.
  final String? catalogItemId;

  EditableItem({
    String description = '',
    String quantity = '',
    String unit = 'sq ft',
    String rate = '',
    this.confidence,
    this.uncertaintyNote,
    this.sourceSpan,
    this.isUnknown = false,
    this.requiresReview = false,
    this.acknowledged = false,
    this.catalogItemId,
  })  : description = TextEditingController(text: description),
        quantity = TextEditingController(text: quantity),
        unit = TextEditingController(text: unit),
        rate = TextEditingController(text: rate);

  void dispose() {
    description.dispose();
    quantity.dispose();
    unit.dispose();
    rate.dispose();
  }

  bool get hasValidEssentials {
    final parsedQuantity = int.tryParse(quantity.text.trim()) ?? 0;
    final parsedRate = int.tryParse(rate.text.trim()) ?? 0;
    return description.text.trim().isNotEmpty &&
        parsedQuantity > 0 &&
        unit.text.trim().isNotEmpty &&
        parsedRate > 0;
  }

  EditableItem copy() {
    return EditableItem(
      description: description.text,
      quantity: quantity.text,
      unit: unit.text,
      rate: rate.text,
      confidence: confidence,
      uncertaintyNote: uncertaintyNote,
      sourceSpan: sourceSpan,
      isUnknown: isUnknown,
      requiresReview: requiresReview,
      acknowledged: acknowledged,
      catalogItemId: catalogItemId,
    );
  }

  QuoteLineItem toLineItem() => QuoteLineItem(
        description: description.text.trim(),
        quantity: int.tryParse(quantity.text.trim()) ?? 0,
        unit: unit.text.trim(),
        unitRatePaise: (int.tryParse(rate.text.trim()) ?? 0) * 100,
        confidence: confidence,
        uncertaintyNote: uncertaintyNote,
        sourceSpan: sourceSpan,
        isUnknown: isUnknown,
        requiresReview: requiresReview,
        acknowledged: acknowledged,
        catalogItemId: catalogItemId,
      );
}
