import '../catalog/catalog.dart';

/// Day 12 — Contractor profile domain model.
///
/// Stores business identity, contact info, default terms, and logo references.
class ContractorProfile {
  final String id;
  final String name;
  final String businessName;
  final String phone;
  final String city;
  final Trade trade;
  final String? gstin;
  final String? logoPath;
  final String? logoSignedUrl;
  final String quoteTerms;
  final int schemaVersion;
  final int version;
  final DateTime updatedAt;

  const ContractorProfile({
    required this.id,
    this.name = '',
    this.businessName = '',
    this.phone = '',
    this.city = '',
    this.trade = Trade.tiling,
    this.gstin,
    this.logoPath,
    this.logoSignedUrl,
    this.quoteTerms = '50% advance before starting work, balance upon completion.',
    this.schemaVersion = 1,
    this.version = 1,
    required this.updatedAt,
  });

  /// Factory for fresh contractor profile.
  factory ContractorProfile.empty() {
    return ContractorProfile(
      id: 'local_contractor',
      updatedAt: DateTime.now(),
    );
  }

  bool get isConfigured =>
      name.trim().isNotEmpty || businessName.trim().isNotEmpty;

  ContractorProfile copyWith({
    String? id,
    String? name,
    String? businessName,
    String? phone,
    String? city,
    Trade? trade,
    String? gstin,
    String? logoPath,
    String? logoSignedUrl,
    String? quoteTerms,
    int? schemaVersion,
    int? version,
    DateTime? updatedAt,
  }) {
    return ContractorProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      businessName: businessName ?? this.businessName,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      trade: trade ?? this.trade,
      gstin: gstin ?? this.gstin,
      logoPath: logoPath ?? this.logoPath,
      logoSignedUrl: logoSignedUrl ?? this.logoSignedUrl,
      quoteTerms: quoteTerms ?? this.quoteTerms,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      version: version ?? this.version,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': id,
      'name': name,
      'business_name': businessName,
      'phone': phone,
      'city': city,
      'trade': trade.name,
      'gstin': gstin,
      'logo_path': logoPath,
      'logo_signed_url': logoSignedUrl,
      'quote_terms': quoteTerms,
      'schema_version': schemaVersion,
      'version': version,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ContractorProfile.fromJson(Map<String, dynamic> json) {
    final tradeStr = json['trade'] as String? ?? 'tiling';
    final trade = tradeStr.toLowerCase() == 'painting'
        ? Trade.painting
        : Trade.tiling;

    return ContractorProfile(
      id: json['id'] as String? ?? json['user_id'] as String? ?? 'local_contractor',
      name: json['name'] as String? ?? '',
      businessName: json['business_name'] as String? ?? json['businessName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      city: json['city'] as String? ?? '',
      trade: trade,
      gstin: json['gstin'] as String?,
      logoPath: json['logo_path'] as String? ?? json['logoPath'] as String?,
      logoSignedUrl: json['logo_signed_url'] as String? ?? json['logoSignedUrl'] as String?,
      quoteTerms: json['quote_terms'] as String? ?? json['quoteTerms'] as String? ?? '',
      schemaVersion: json['schema_version'] as int? ?? 1,
      version: json['version'] as int? ?? 1,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
