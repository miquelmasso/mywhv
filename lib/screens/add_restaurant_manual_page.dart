import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../services/email_extractor.dart';
import '../services/facebook_extractor.dart';

class AddRestaurantManualPage extends StatefulWidget {
  const AddRestaurantManualPage({super.key});

  @override
  State<AddRestaurantManualPage> createState() => _AddRestaurantManualPageState();
}

class _AddRestaurantManualPageState extends State<AddRestaurantManualPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _facebookController = TextEditingController();
  final TextEditingController _instagramController = TextEditingController();
  final TextEditingController _careersController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  bool _saving = false;
  bool _isExtracting = false;
  String? _extractError;
  final EmailExtractor _emailExtractor = EmailExtractor();
  final FacebookExtractor _facebookExtractor = FacebookExtractor();

  String? _extractInstagram(String html) {
    final regex = RegExp(
      r'https?://(www\.)?instagram\.com/[^\s"<>]+',
      caseSensitive: false,
    );
    final match = regex.firstMatch(html);
    return match?.group(0);
  }

  String? _extractFacebookFromHtml(String html) {
    final regex = RegExp(
      r'https?://(www\.)?(facebook\.com|fb\.me)/[^\s"<>]+',
      caseSensitive: false,
    );
    final match = regex.firstMatch(html);
    return match?.group(0);
  }

  Future<Map<String, dynamic>> scrapeContactsFromUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('URL no vàlida (ha de ser http/https)');
    }

    final res = await http.get(
      uri,
      headers: {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'text/html',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }

    final html = res.body;

    final emailRegex = RegExp(
      r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
      caseSensitive: false,
    );
    final phoneRegex = RegExp(r'(\+?\d[\d\s().-]{7,}\d)');

    final emails = {
      ...emailRegex.allMatches(html).map((m) => m.group(0) ?? '').where((e) => e.isNotEmpty),
    };
    final phones = {
      ...phoneRegex.allMatches(html).map((m) => m.group(0) ?? '').where((p) => p.isNotEmpty),
    };

    String? instagram = _extractInstagram(html);
    String? facebook = _extractFacebookFromHtml(html);

    final extractedEmail = await _emailExtractor.extract(
      url,
      businessName: _nameController.text,
    );
    if (extractedEmail != null) {
      emails.add(extractedEmail);
    }

    final fbResult = await _facebookExtractor.find(
      baseUrl: url,
      businessName: _nameController.text,
      address: '',
      phone: _phoneController.text,
    );
    final fbLink = fbResult != null ? fbResult['link'] as String? : null;
    if (fbLink != null && fbLink.isNotEmpty) {
      facebook = fbLink;
    }

    return {
      'emails': emails.toList(),
      'phones': phones.toList(),
      'instagram': instagram,
      'facebook': facebook,
    };
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameController.dispose();
    _phoneController.dispose();
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
        'phone': _phoneController.text.trim(),
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
    bool enablePaste = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: action,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: enablePaste
            ? IconButton(
                icon: const Icon(Icons.content_paste_go_outlined),
                tooltip: 'Paste',
                onPressed: () => _pasteValue(controller),
              )
            : null,
      ),
    );
  }

  Future<void> _pasteValue(TextEditingController controller) async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    setState(() {
      controller.text = text;
    });
  }

  Future<void> _autoFillFromLink() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() {
        _extractError = 'Introdueix una URL';
      });
      return;
    }

    setState(() {
      _extractError = null;
      _isExtracting = true;
    });

    try {
      debugPrint('Scraping contacts from $url');
      final data = await scrapeContactsFromUrl(url);

      final emails = (data['emails'] as List?)?.whereType<String>().toList() ?? [];
      final phones = (data['phones'] as List?)?.whereType<String>().toList() ?? [];
      final instagram = data['instagram'] as String?;
      final facebook = data['facebook'] as String?;

      if (_emailController.text.trim().isEmpty && emails.isNotEmpty) {
        _emailController.text = emails.first;
      }
      if (_phoneController.text.trim().isEmpty && phones.isNotEmpty) {
        _phoneController.text = phones.first;
      }
      if (_instagramController.text.trim().isEmpty && (instagram ?? '').isNotEmpty) {
        _instagramController.text = instagram!;
      }
      if (_facebookController.text.trim().isEmpty && (facebook ?? '').isNotEmpty) {
        _facebookController.text = facebook!;
      }
    } catch (e, st) {
      debugPrint('scrapeContactsFromUrl error: $e\n$st');
      setState(() {
        _extractError = 'No s\'ha pogut extreure la informació. Torna-ho a provar.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExtracting = false;
        });
      }
    }
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
                  controller: _urlCtrl,
                  label: 'URL',
                  keyboardType: TextInputType.url,
                  enablePaste: true,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: ElevatedButton.icon(
                      onPressed: _isExtracting ? null : _autoFillFromLink,
                      icon: _isExtracting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(_isExtracting ? 'Carregant...' : 'Auto-omplir dades'),
                    ),
                  ),
                ),
                if (_extractError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _extractError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
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
                  enablePaste: true,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _lngController,
                  label: 'Longitud',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) =>
                      (double.tryParse(v ?? '') == null) ? 'Introdueix una longitud vàlida' : null,
                  enablePaste: true,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _phoneController,
                  label: 'Telèfon',
                  keyboardType: TextInputType.phone,
                  enablePaste: true,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _emailController,
                  label: 'Correu electrònic',
                  keyboardType: TextInputType.emailAddress,
                  enablePaste: true,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _facebookController,
                  label: 'Enllaç de Facebook',
                  keyboardType: TextInputType.url,
                  enablePaste: true,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _instagramController,
                  label: 'Enllaç d\'Instagram',
                  keyboardType: TextInputType.url,
                  enablePaste: true,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _careersController,
                  label: 'Pàgina de feina (careers)',
                  keyboardType: TextInputType.url,
                  action: TextInputAction.done,
                  enablePaste: true,
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
