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
  bool _cvUploaded = false;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    _controller.text = prefs.getString('emailMessage') ?? '';
    setState(() {
      _cvPath = prefs.getString('cvPath');
      _cvUploaded = _cvPath != null;
    });
  }

  Future<void> _saveMessage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emailMessage', _controller.text);
  }

 Future<void> _pickAndSaveCV() async {
  // ✅ 1. Demana permisos només si és Android
  if (Platform.isAndroid) {
    if (await Permission.manageExternalStorage.isDenied &&
        await Permission.storage.isDenied) {
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
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
    setState(() {
      _cvPath = newFile.path;
      _cvUploaded = true;
    });

    // ✅ 6. Confirmació visual (suprimim missatges emergents)
  } catch (e) {
    // ⚠️ Error durant la còpia (silenciat)
  }
}

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveMessage();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Automatic email editing')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Email content',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300, width: 1.1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _controller,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      decoration: InputDecoration(
                        hintText: 'Write here your message...',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _saveMessage,
                      icon: const Icon(Icons.save_outlined, size: 22),
                      label: const Text('Save message'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF81C784),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        elevation: 2.5,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _pickAndSaveCV,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF64B5F6),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        elevation: 2.5,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.upload_file_outlined, size: 22),
                          const SizedBox(width: 12),
                          Text(
                            _cvUploaded ? 'Replace CV (PDF)' : 'Upload CV (PDF)',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _cvPath != null ? 'Current CV: ${_cvPath!.split('/').last}' : 'Current CV: none',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ),
                    Icon(
                      _cvUploaded ? Icons.check_circle : Icons.check_circle_outline,
                      color: _cvUploaded ? Colors.green : Colors.grey,
                      size: 22,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
