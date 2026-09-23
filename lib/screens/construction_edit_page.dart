import 'package:flutter/material.dart';

import '../models/construction_category.dart';
import '../services/construction_pending_publish_service.dart';
import '../services/construction_sqlite_store.dart';
import '../services/map_markers_service.dart';
import '../services/postcode_state_helper.dart';
import 'add_construction_manual_page.dart';

typedef ConstructionCompanyLoader =
    Future<Map<String, dynamic>?> Function(String companyId);
typedef ConstructionCompanySaver =
    Future<void> Function(String companyId, Map<String, dynamic> updates);

class ConstructionEditResult {
  const ConstructionEditResult({
    required this.changed,
    required this.companyId,
    required this.previousStatus,
    required this.newStatus,
  });

  final bool changed;
  final String companyId;
  final String previousStatus;
  final String newStatus;
}

class ConstructionEditPage extends StatefulWidget {
  const ConstructionEditPage({
    super.key,
    this.initialSearch,
    this.companyId,
    this.initialCompany,
    this.loadCompany,
    this.saveCompany,
  });

  final String? initialSearch;
  final String? companyId;
  final Map<String, dynamic>? initialCompany;
  final ConstructionCompanyLoader? loadCompany;
  final ConstructionCompanySaver? saveCompany;

  @override
  State<ConstructionEditPage> createState() => _ConstructionEditPageState();
}

class _ConstructionEditPageState extends State<ConstructionEditPage> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _postcodeController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _websiteController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _careersController = TextEditingController();
  final _store = ConstructionSqliteStore.instance;

  List<Map<String, dynamic>> _results = const [];
  Map<String, dynamic>? _selected;
  bool _blocked = false;
  ConstructionCategory _category = ConstructionCategory.other;
  bool _saving = false;
  bool _deleting = false;
  bool _loading = false;
  String? _loadError;

  bool get _exactCompanyMode =>
      widget.initialCompany != null ||
      (widget.companyId ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final initialCompany = widget.initialCompany;
    if (initialCompany != null) {
      final requestedId = widget.companyId?.trim() ?? '';
      final rowId = (initialCompany['docId'] ?? initialCompany['id'] ?? '')
          .toString();
      if (requestedId.isNotEmpty && rowId != requestedId) {
        _loadError = 'The requested local company did not match.';
        return;
      }
      _applySelected(initialCompany);
      return;
    }
    final companyId = widget.companyId?.trim() ?? '';
    if (companyId.isNotEmpty) {
      _loadExactCompany(companyId);
      return;
    }
    final initial = widget.initialSearch?.trim() ?? '';
    if (initial.isNotEmpty) {
      _searchController.text = initial;
      _search(initial, autoSelect: true);
    }
  }

  Future<void> _loadExactCompany(String companyId) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final loader = widget.loadCompany ?? _loadLocalCompany;
      final company = await loader(companyId);
      if (!mounted) return;
      if (company == null) {
        setState(() => _loadError = 'This company is not available locally.');
        return;
      }
      final loadedId = (company['docId'] ?? company['id'] ?? '').toString();
      if (loadedId != companyId) {
        setState(
          () => _loadError = 'The requested local company did not match.',
        );
        return;
      }
      _select(company);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Could not load this company locally.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>?> _loadLocalCompany(String companyId) async {
    await _store.init();
    return _store.getById(companyId);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _postcodeController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _websiteController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _careersController.dispose();
    super.dispose();
  }

  Future<void> _search(String query, {bool autoSelect = false}) async {
    if (query.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _store.init();
      final results = await _store.searchByName(query);
      if (!mounted) return;
      setState(() => _results = results);
      if (autoSelect && results.isNotEmpty) _select(results.first);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Could not search local companies.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(Map<String, dynamic> company) {
    _applySelected(company);
    setState(() => _results = const []);
  }

  void _applySelected(Map<String, dynamic> company) {
    _selected = Map<String, dynamic>.from(company);
    _searchController.text = (company['name'] ?? '').toString();
    _nameController.text = (company['name'] ?? '').toString();
    _addressController.text = (company['address'] ?? '').toString();
    _postcodeController.text =
        (company['postcode_display'] ?? company['postcode'] ?? '').toString();
    _latitudeController.text = (company['latitude'] ?? company['lat'] ?? '')
        .toString();
    _longitudeController.text = (company['longitude'] ?? company['lng'] ?? '')
        .toString();
    _websiteController.text = (company['website'] ?? '').toString();
    _phoneController.text = (company['phone'] ?? '').toString();
    _emailController.text = (company['email'] ?? '').toString();
    _facebookController.text = (company['facebook_url'] ?? '').toString();
    _instagramController.text = (company['instagram_url'] ?? '').toString();
    _careersController.text = (company['careers_page'] ?? '').toString();
    _blocked = company['blocked'] == true || company['blocked'] == 1;
    _category = ConstructionCategory.classifyRow(company);
  }

  Map<String, dynamic>? _updates() {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    final postcode = _postcodeController.text.trim().padLeft(4, '0');
    if (_nameController.text.trim().isEmpty ||
        latitude == null ||
        longitude == null ||
        !RegExp(r'^\d{4}$').hasMatch(postcode)) {
      return null;
    }
    return <String, dynamic>{
      'name': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'postcode': postcode,
      'postcode_display': postcode,
      'state': getStateFromPostcode(postcode),
      'latitude': latitude,
      'longitude': longitude,
      'website': _websiteController.text.trim(),
      'phone': _phoneController.text.trim(),
      'email': _emailController.text.trim(),
      'facebook_url': _facebookController.text.trim(),
      'instagram_url': _instagramController.text.trim(),
      'careers_page': _careersController.text.trim(),
      'blocked': _blocked,
      'place_type': 'construction',
      'marker_kind': 'construction',
      'construction_category': _category.id,
      'construction_category_label': _category.label,
      'contact_enrichment_status': 'completed',
      'contact_enrichment_source': 'manual_review',
      'website_checked_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null) return;
    final updates = _updates();
    if (updates == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check name, postcode and coordinates.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final docId = (selected['docId'] ?? selected['id']).toString();
      final previousStatus = (selected['contact_enrichment_status'] ?? '')
          .toString();
      final saver = widget.saveCompany;
      if (saver != null) {
        await saver(docId, updates);
      } else {
        await MapMarkersService.updateLocalConstructionCompanyFields(
          docId,
          updates,
        );
        await ConstructionPendingPublishService.instance.markPending([docId]);
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        ConstructionEditResult(
          changed: true,
          companyId: docId,
          previousStatus: previousStatus,
          newStatus: (updates['contact_enrichment_status'] ?? '').toString(),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update the construction company.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final selected = _selected;
    if (selected == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete construction company?'),
        content: Text(
          'This will permanently delete ${(selected['name'] ?? 'this company')} from Firebase and this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      final docId = (selected['docId'] ?? selected['id']).toString();
      await MapMarkersService.deleteConstructionCompany(docId);
      if (!mounted) return;
      setState(() {
        _selected = null;
        _searchController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Construction company deleted.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete the construction company.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType keyboardType = TextInputType.text,
    bool isUrl = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          keyboardType: isUrl ? TextInputType.url : keyboardType,
          autocorrect: !isUrl,
          enableSuggestions: !isUrl,
          textCapitalization: isUrl
              ? TextCapitalization.none
              : TextCapitalization.sentences,
          smartDashesType: isUrl
              ? SmartDashesType.disabled
              : SmartDashesType.enabled,
          smartQuotesType: isUrl
              ? SmartQuotesType.disabled
              : SmartQuotesType.enabled,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    onPressed: controller.clear,
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit construction')),
      body: _loading && _selected == null
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null && _selected == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 42),
                    const SizedBox(height: 12),
                    Text(_loadError!, textAlign: TextAlign.center),
                    if ((widget.companyId ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => _loadExactCompany(widget.companyId!),
                        child: const Text('Try again'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (!_exactCompanyMode)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final changed = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const AddConstructionManualPage(),
                              ),
                            );
                            if (changed == true && mounted) {
                              await _search(_searchController.text);
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add company manually'),
                        ),
                      ),
                    if (!_exactCompanyMode) const SizedBox(height: 12),
                    if (!_exactCompanyMode)
                      TextField(
                        controller: _searchController,
                        onChanged: _search,
                        decoration: const InputDecoration(
                          labelText: 'Search construction companies',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    if (_loading) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(),
                    ],
                    if (_loadError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _loadError!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    if (_results.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.black12),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final company = _results[index];
                            return ListTile(
                              title: Text(
                                (company['name'] ?? 'No name').toString(),
                              ),
                              subtitle: Text(
                                (company['postcode_display'] ??
                                        company['postcode'] ??
                                        '')
                                    .toString(),
                              ),
                              onTap: () => _select(company),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (_selected != null) ...[
                      _field(_nameController, 'Company name'),
                      _field(_addressController, 'Address'),
                      _field(
                        _postcodeController,
                        'Postcode',
                        keyboardType: TextInputType.number,
                      ),
                      _field(
                        _latitudeController,
                        'Latitude',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                      _field(
                        _longitudeController,
                        'Longitude',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                      _field(_websiteController, 'Website', isUrl: true),
                      _field(_phoneController, 'Phone'),
                      _field(_emailController, 'Email'),
                      _field(_facebookController, 'Facebook', isUrl: true),
                      _field(_instagramController, 'Instagram', isUrl: true),
                      _field(_careersController, 'Careers page', isUrl: true),
                      DropdownButtonFormField<String>(
                        initialValue: _category.id,
                        decoration: const InputDecoration(
                          labelText: 'Construction category',
                          border: OutlineInputBorder(),
                        ),
                        items: ConstructionCategory.values
                            .map(
                              (category) => DropdownMenuItem(
                                value: category.id,
                                child: Text(
                                  category.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (id) => setState(
                          () => _category = ConstructionCategory.fromId(id),
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('Block company'),
                        value: _blocked,
                        onChanged: (value) => setState(() => _blocked = value),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _saving || _deleting ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Saving...' : 'Save changes'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                      ),
                      if (!_exactCompanyMode) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _saving || _deleting ? null : _delete,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            _deleting ? 'Deleting...' : 'Delete company',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            minimumSize: const Size(double.infinity, 50),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
