import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class MailSetupPage extends StatefulWidget {
  const MailSetupPage({super.key});

  @override
  State<MailSetupPage> createState() => _MailSetupPageState();
}

class _MailSetupPageState extends State<MailSetupPage> {
  final TextEditingController _controller = TextEditingController();
  String? _cvPath;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    _controller.text = prefs.getString('emailMessage') ?? '';
    setState(() => _cvPath = prefs.getString('cvPath'));
  }

  Future<void> _saveMessage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emailMessage', _controller.text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message saved successfully')),
    );
  }

 Future<void> _pickAndSaveCV() async {
  // ✅ 1. Demana permisos només si és Android
  if (Platform.isAndroid) {
    if (await Permission.manageExternalStorage.isDenied &&
        await Permission.storage.isDenied) {
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission denied to access files.')),
        );
        return;
      }
    }
  }

  // ✅ 2. Obrir el selector de fitxers
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );

  if (result == null || result.files.single.path == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No file selected.')),
    );
    return;
  }

  final file = File(result.files.single.path!);
  final fileName = file.uri.pathSegments.last;

  try {
    // ✅ 3. Determinar el directori correcte segons la plataforma
    final Directory appDir;
    if (Platform.isAndroid) {
      appDir = Directory('/storage/emulated/0/Download');
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }
    } else {
      // iOS: es guarda al directori privat de l’app
      appDir = await getApplicationDocumentsDirectory();
    }

    // ✅ 4. Copiar el fitxer seleccionat al directori
    final newPath = '${appDir.path}/$fileName';
    final newFile = await file.copy(newPath);

    // ✅ 5. Guardar el path a SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cvPath', newFile.path);
    setState(() => _cvPath = newFile.path);

    // ✅ 6. Confirmació visual
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ CV saved')),
    );
  } catch (e) {
    // ⚠️ Error durant la còpia
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ Error copying file')),
    );
  }
}

  Future<void> _deleteCV() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cvPath');
    setState(() => _cvPath = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CV deleted successfully')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit automatic mail')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Text for the mail',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                minLines: 6,
                maxLines: 10,
                decoration: InputDecoration(
                  hintText: 'Write here your message...',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.blueGrey.shade400, width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saveMessage,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save message'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey.shade300),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickAndSaveCV,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload CV (PDF)'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey.shade300),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  if (_cvPath != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _deleteCV,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar CV'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey.shade200),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        backgroundColor: Colors.grey.shade100,
                      ),
                    ),
                  ],
                ],
              ),
              if (_cvPath != null) ...[
                const SizedBox(height: 10),
                Text(
                  'current CV: ${_cvPath!.split('/').last}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
