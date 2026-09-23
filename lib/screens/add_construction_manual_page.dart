import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/construction_category.dart';
import '../services/construction_pending_publish_service.dart';
import '../services/map_markers_service.dart';
import '../services/postcode_state_helper.dart';

class AddConstructionManualPage extends StatefulWidget {
  const AddConstructionManualPage({super.key});

  @override
  State<AddConstructionManualPage> createState() =>
      _AddConstructionManualPageState();
}

class _AddConstructionManualPageState extends State<AddConstructionManualPage> {
  final _formKey = GlobalKey<FormState>();
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
  bool _saving = false;
  ConstructionCategory _category = ConstructionCategory.residentialCommercial;

  @override
  void dispose() {
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude == null || longitude == null) return;

    setState(() => _saving = true);
    try {
      final postcode = _postcodeController.text.trim().padLeft(4, '0');
      final now = DateTime.now().toUtc().toIso8601String();
      final docId = 'manual_${DateTime.now().microsecondsSinceEpoch}';
      final company = <String, dynamic>{
        'id': docId,
        'docId': docId,
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
        'blocked': false,
        'worked_here_count': 0,
        'place_type': 'construction',
        'marker_kind': 'construction',
        'construction_category': _category.id,
        'construction_category_label': _category.label,
        'source': 'manual',
        'timestamp': now,
      };
      await MapMarkersService.upsertLocalConstructionCompanies([company]);
      await ConstructionPendingPublishService.instance.markPending([docId]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Construction company added.')),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add the construction company.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'Paste',
            icon: const Icon(Icons.content_paste_go_outlined),
            onPressed: () async {
              final data = await Clipboard.getData('text/plain');
              final text = data?.text ?? '';
              if (text.isNotEmpty && mounted) {
                setState(() => controller.text = text);
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add construction company')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _field(
                  controller: _nameController,
                  label: 'Company name',
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Name is required'
                      : null,
                ),
                _field(controller: _addressController, label: 'Address'),
                _field(
                  controller: _postcodeController,
                  label: 'Postcode',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final postcode = (value ?? '').trim().padLeft(4, '0');
                    return RegExp(r'^\d{4}$').hasMatch(postcode)
                        ? null
                        : 'Enter a valid postcode';
                  },
                ),
                _field(
                  controller: _latitudeController,
                  label: 'Latitude',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (value) => double.tryParse(value ?? '') == null
                      ? 'Enter a valid latitude'
                      : null,
                ),
                _field(
                  controller: _longitudeController,
                  label: 'Longitude',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (value) => double.tryParse(value ?? '') == null
                      ? 'Enter a valid longitude'
                      : null,
                ),
                _field(
                  controller: _websiteController,
                  label: 'Website',
                  keyboardType: TextInputType.url,
                ),
                _field(
                  controller: _phoneController,
                  label: 'Phone',
                  keyboardType: TextInputType.phone,
                ),
                _field(
                  controller: _emailController,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
                _field(controller: _facebookController, label: 'Facebook'),
                _field(controller: _instagramController, label: 'Instagram'),
                _field(controller: _careersController, label: 'Careers page'),
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
                          child: Row(
                            children: [
                              Icon(category.icon, color: category.color),
                              const SizedBox(width: 10),
                              Flexible(child: Text(category.label)),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (id) => setState(
                    () => _category = ConstructionCategory.fromId(id),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving...' : 'Add company'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
