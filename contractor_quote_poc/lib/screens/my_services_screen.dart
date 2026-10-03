import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/service_item.dart';
import '../storage/service_item_repository.dart';
import '../templates/template_data.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';

/// The user's own service list for one business type: add, rename, re-rate,
/// delete, and seed from the bundled starter template.
/// Services persist locally via [ServiceItemRepository] and sync when online.
class MyServicesScreen extends StatefulWidget {
  final BusinessType businessType;
  const MyServicesScreen({super.key, required this.businessType});

  @override
  State<MyServicesScreen> createState() => _MyServicesScreenState();
}

class _MyServicesScreenState extends State<MyServicesScreen> {
  List<ServiceItem> _services = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _query = _searchCtrl.text.trim());
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final services = await ServiceItemRepository.getActiveForBusinessType(
      widget.businessType,
    );
    if (!mounted) return;
    setState(() {
      _services = services;
      _loading = false;
    });
  }

  Future<void> _addService() async {
    final saved = await showServiceForm(context, null);
    if (saved == null) return;
    await ServiceItemRepository.upsert(
      name: saved.name,
      unit: saved.unit,
      ratePaise: saved.ratePaise,
      businessType: widget.businessType,
      keywords: saved.keywords,
      sortOrder: _services.length,
    );
    await _load();
  }

  Future<void> _editService(ServiceItem service) async {
    final saved = await showServiceForm(context, service);
    if (saved == null) return;
    await ServiceItemRepository.upsert(
      id: service.id,
      name: saved.name,
      nameHi: saved.nameHi,
      nameMr: saved.nameMr,
      unit: saved.unit,
      ratePaise: saved.ratePaise,
      businessType: widget.businessType,
      keywords: saved.keywords,
      sortOrder: service.sortOrder,
      notes: saved.notes,
    );
    await _load();
  }

  Future<void> _deleteService(ServiceItem service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${AppStrings.of(ctx, 'delete_service')}?'),
        content: Text(service.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: kError),
            child: Text(AppStrings.of(ctx, 'delete_service')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ServiceItemRepository.delete(service.id);
    await _load();
  }

  Future<void> _useTemplate() async {
    await ServiceItemRepository.seedFromTemplate(widget.businessType);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context, 'template_added')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String t(String k) => AppStrings.of(context, k);
    final needle = _query.toLowerCase();
    final visible = needle.isEmpty
        ? _services
        : _services
            .where((s) =>
                s.name.toLowerCase().contains(needle) ||
                s.matchTerms.any((term) => term.contains(needle)))
            .toList(growable: false);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(t('my_services'))),
        body: const Center(child: CircularProgressIndicator(color: kForest)),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(t('my_services')),
        actions: [
          IconButton(
            tooltip: t('use_template'),
            onPressed: _useTemplate,
            icon: const Icon(Icons.auto_awesome_motion_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addService,
        icon: const Icon(Icons.add_rounded),
        label: Text(t('add_service')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDimensions.page),
        children: [
          Text(
            t('my_services_note'),
            style: const TextStyle(fontSize: 13, color: kInkMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: t('search_services'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      tooltip: 'Clear search',
                      onPressed: _searchCtrl.clear,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                t('services_empty'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: kInkMuted),
              ),
            )
          else
            for (final service in visible)
              Card(
                child: ListTile(
                  title: Text(service.name),
                  subtitle: Text(
                    service.ratePaise > 0
                        ? '${service.unit} · ₹${service.rateRupees}'
                        : '${service.unit} · ${t('rate_not_set')}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: t('edit_service'),
                        onPressed: () => _editService(service),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: t('delete_service'),
                        onPressed: () => _deleteService(service),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                  onTap: () => _editService(service),
                ),
              ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

/// Add/edit bottom sheet for one service. Returns an edited copy
/// (or a blank draft) or null when cancelled.
Future<ServiceItem?> showServiceForm(
  BuildContext context,
  ServiceItem? service,
) async {
  final nameCtrl = TextEditingController(text: service?.name ?? '');
  final unitCtrl = TextEditingController(text: service?.unit ?? 'item');
  final rateCtrl = TextEditingController(
    text: (service?.rateRupees ?? 0) > 0 ? '${service!.rateRupees}' : '',
  );
  final keywordsCtrl = TextEditingController(
    text: (service?.keywords ?? const []).join(', '),
  );

  final saved = await showModalBottomSheet<ServiceItem>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        AppDimensions.page,
        AppDimensions.page,
        AppDimensions.page,
        MediaQuery.of(ctx).viewInsets.bottom + AppDimensions.page,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            service == null
                ? AppStrings.of(ctx, 'add_service')
                : AppStrings.of(ctx, 'edit_service'),
            style: Theme.of(ctx).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: AppStrings.of(ctx, 'service_name'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: unitCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(ctx, 'unit'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: rateCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(ctx, 'rate'),
                    prefixText: '₹ ',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: keywordsCtrl,
            decoration: InputDecoration(
              labelText: AppStrings.of(ctx, 'keywords'),
              helperText: AppStrings.of(ctx, 'keywords_note'),
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(
                ctx,
                (service ?? ServiceItem.draft(name: name)).copyWith(
                  name: name,
                  unit: unitCtrl.text.trim().isEmpty
                      ? 'item'
                      : unitCtrl.text.trim(),
                  ratePaise: (int.tryParse(rateCtrl.text.trim()) ?? 0) * 100,
                  keywords: [
                    for (final k in keywordsCtrl.text.split(','))
                      if (k.trim().isNotEmpty) k.trim(),
                  ],
                ),
              );
            },
            child: Text(AppStrings.of(ctx, 'save_changes')),
          ),
        ],
      ),
    ),
  );

  nameCtrl.dispose();
  unitCtrl.dispose();
  rateCtrl.dispose();
  keywordsCtrl.dispose();
  return saved;
}
