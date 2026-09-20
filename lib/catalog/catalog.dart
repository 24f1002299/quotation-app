/// Day 4 — Local catalog of the six supported demo items.
///
/// This is a plain Dart file (no JSON, no network) so it compiles into
/// the app and works fully offline.  Each [CatalogItem] carries:
///   - a stable [id]
///   - a bilingual [displayName] (English / Hindi)
///   - a [defaultUnit] used as the pre-filled unit in the Add-item sheet
///   - a list of [synonyms] in Hindi/Marathi/Hinglish — used by the Day-5
///     parser to recognise these items in spoken transcripts
///   - the [trade] it belongs to (tiling or painting)

enum Trade { tiling, painting }

class CatalogItem {
  final String id;
  final String displayName; // English + Hindi, shown in UI
  final String defaultUnit;
  final List<String> synonyms; // lower-case; checked by the parser
  final Trade trade;

  const CatalogItem({
    required this.id,
    required this.displayName,
    required this.defaultUnit,
    required this.synonyms,
    required this.trade,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// The six POC items.
// Synonym lists are intentionally small: only what appears in the two demo
// phrases plus close variants a contractor is likely to say.
// ─────────────────────────────────────────────────────────────────────────────
const List<CatalogItem> kCatalog = [
  // ── Tiling ──────────────────────────────────────────────────────────────
  CatalogItem(
    id: 'tile_labour',
    displayName: 'Tile Labour / टाइल मजदूरी',
    defaultUnit: 'sq ft',
    trade: Trade.tiling,
    synonyms: [
      'tile labour',
      'tile labor',
      'tiles labour',
      'tiles labor',
      'tiling labour',
      'tiling labor',
      'टाइल मजदूरी',
      'टाइल लेबर',
      'tiles lagana',
      'tile lagana',
      'टाइल लगाना',
      'floor tile',
      'floor tiles',
    ],
  ),
  CatalogItem(
    id: 'skirting',
    displayName: 'Skirting / स्कर्टिंग',
    defaultUnit: 'rft',
    trade: Trade.tiling,
    synonyms: [
      'skirting',
      'skirting tile',
      'skirting tiles',
      'स्कर्टिंग',
      'skirt',
      'border tile',
      'border tiles',
      'दीवार टाइल',
    ],
  ),
  CatalogItem(
    id: 'waterproofing',
    displayName: 'Waterproofing / वॉटरप्रूफिंग',
    defaultUnit: 'sq ft',
    trade: Trade.tiling,
    synonyms: [
      'waterproofing',
      'water proofing',
      'वॉटरप्रूफिंग',
      'waterproof',
      'paani rokna',
      'पानी रोकना',
      'leakage proofing',
    ],
  ),

  // ── Painting ─────────────────────────────────────────────────────────────
  CatalogItem(
    id: 'wall_putty',
    displayName: 'Wall Putty / वॉल पुट्टी',
    defaultUnit: 'sq ft',
    trade: Trade.painting,
    synonyms: [
      'wall putty',
      'putty',
      'वॉल पुट्टी',
      'patti',
      'पट्टी',
      'white cement putty',
      'putty work',
      'patti kaam',
    ],
  ),
  CatalogItem(
    id: 'primer',
    displayName: 'Primer / प्राइमर',
    defaultUnit: 'sq ft',
    trade: Trade.painting,
    synonyms: [
      'primer',
      'प्राइमर',
      'prime coat',
      'priming',
      'primer coat',
      'first coat',
    ],
  ),
  CatalogItem(
    id: 'painting',
    displayName: 'Painting / पेंटिंग',
    defaultUnit: 'sq ft',
    trade: Trade.painting,
    synonyms: [
      'painting',
      'paint',
      'पेंटिंग',
      'paint work',
      'रंगाई',
      'rangai',
      'wall painting',
      'emulsion',
      'distemper',
    ],
  ),
];

/// Returns only the items belonging to [trade].
List<CatalogItem> catalogForTrade(Trade trade) =>
    kCatalog.where((item) => item.trade == trade).toList();

/// Looks up a catalog item by [id].  Returns null if not found.
CatalogItem? catalogItemById(String id) {
  try {
    return kCatalog.firstWhere((item) => item.id == id);
  } catch (_) {
    return null;
  }
}
