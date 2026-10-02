import '../templates/template_data.dart';

/// The business behind the app's quotes: identity, contact details, the
/// business type whose starter template seeded the service list, and the
/// default terms printed on every PDF.
class BusinessProfile {
  final String id;
  final String businessName;
  final String ownerName;
  final String phone;
  final String city;
  final String address;
  final BusinessType businessType;
  final String? gstin;
  final String? logoPath;
  final String? logoSignedUrl;
  final String quoteTerms;
  final int schemaVersion;

  /// Record version for optimistic concurrency and conflict detection.
  final int version;
  final DateTime updatedAt;

  const BusinessProfile({
    required this.id,
    this.businessName = '',
    this.ownerName = '',
    this.phone = '',
    this.city = '',
    this.address = '',
    this.businessType = BusinessType.tiling,
    this.gstin,
    this.logoPath,
    this.logoSignedUrl,
    this.quoteTerms = '50% advance before starting work, balance upon completion.',
    this.schemaVersion = 1,
    this.version = 1,
    required this.updatedAt,
  });

  /// Fresh profile for a new install.
  factory BusinessProfile.empty() => BusinessProfile(
        id: 'local_business',
        updatedAt: DateTime.now(),
      );

  /// The user has entered enough to print a quotation.
  bool get isConfigured =>
      businessName.trim().isNotEmpty || ownerName.trim().isNotEmpty;

  BusinessProfile copyWith({
    String? id,
    String? businessName,
    String? ownerName,
    String? phone,
    String? city,
    String? address,
    BusinessType? businessType,
    String? gstin,
    String? logoPath,
    String? logoSignedUrl,
    String? quoteTerms,
    int? schemaVersion,
    int? version,
    DateTime? updatedAt,
  }) {
    return BusinessProfile(
      id: id ?? this.id,
      businessName: businessName ?? this.businessName,
      ownerName: ownerName ?? this.ownerName,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      address: address ?? this.address,
      businessType: businessType ?? this.businessType,
      gstin: gstin ?? this.gstin,
      logoPath: logoPath ?? this.logoPath,
      logoSignedUrl: logoSignedUrl ?? this.logoSignedUrl,
      quoteTerms: quoteTerms ?? this.quoteTerms,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      version: version ?? this.version,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': id,
        'business_name': businessName,
        'owner_name': ownerName,
        'phone': phone,
        'city': city,
        'address': address,
        'business_type': businessTypeInfo(businessType).id,
        'gstin': gstin,
        'logo_path': logoPath,
        'logo_signed_url': logoSignedUrl,
        'quote_terms': quoteTerms,
        'schema_version': schemaVersion,
        'version': version,
        // Wire contract: ProfileDto.updatedAt is an Instant — zone-less ISO
        // is rejected with 400. Always emit UTC (see SavedQuote.toJson).
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      id: json['id'] as String? ??
          json['user_id'] as String? ??
          'local_business',
      businessName:
          json['business_name'] as String? ?? json['businessName'] as String? ?? '',
      ownerName:
          json['owner_name'] as String? ?? json['ownerName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      city: json['city'] as String? ?? '',
      address: json['address'] as String? ?? '',
      businessType: businessTypeFromId(
        json['business_type'] as String? ?? json['businessType'] as String?,
      ),
      gstin: json['gstin'] as String?,
      logoPath: json['logo_path'] as String? ?? json['logoPath'] as String?,
      logoSignedUrl:
          json['logo_signed_url'] as String? ?? json['logoSignedUrl'] as String?,
      quoteTerms: json['quote_terms'] as String? ?? json['quoteTerms'] as String? ?? '',
      schemaVersion: json['schema_version'] as int? ?? 1,
      version: json['version'] as int? ?? 1,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
