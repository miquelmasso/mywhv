import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AddRestaurantManualPage extends StatefulWidget {
  const AddRestaurantManualPage({super.key});

  @override
  State<AddRestaurantManualPage> createState() => _AddRestaurantManualPageState();
}

class _AddRestaurantManualPageState extends State<AddRestaurantManualPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _facebookController = TextEditingController();
  final TextEditingController _instagramController = TextEditingController();
  final TextEditingController _careersController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _careersController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final double? lat = double.tryParse(_latController.text.trim());
    final double? lng = double.tryParse(_lngController.text.trim());
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introdueix latitud i longitud vàlides.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('restaurants').add({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'facebook_url': _facebookController.text.trim(),
        'instagram_url': _instagramController.text.trim(),
        'careers_page': _careersController.text.trim(),
        'latitude': lat,
        'longitude': lng,
        'blocked': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Restaurant afegit correctament')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error en afegir: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction action = TextInputAction.next,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: action,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Afegir restaurant')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildField(
                  controller: _nameController,
                  label: 'Nom del restaurant',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'El nom és obligatori' : null,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _latController,
                  label: 'Latitud',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) =>
                      (double.tryParse(v ?? '') == null) ? 'Introdueix una latitud vàlida' : null,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _lngController,
                  label: 'Longitud',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) =>
                      (double.tryParse(v ?? '') == null) ? 'Introdueix una longitud vàlida' : null,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _emailController,
                  label: 'Correu electrònic',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _facebookController,
                  label: 'Enllaç de Facebook',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _instagramController,
                  label: 'Enllaç d\'Instagram',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _careersController,
                  label: 'Pàgina de feina (careers)',
                  keyboardType: TextInputType.url,
                  action: TextInputAction.done,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: _saving
                      ? const Text('Guardant...')
                      : const Text('Afegir restaurant'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
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
