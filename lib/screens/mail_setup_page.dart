import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
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
      const SnackBar(content: Text('Missatge desat correctament')),
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
          const SnackBar(content: Text('Permís denegat per accedir als fitxers.')),
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
      const SnackBar(content: Text('No s’ha seleccionat cap fitxer.')),
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
      SnackBar(content: Text('✅ CV desat correctament a: ${newFile.path}')),
    );
  } catch (e) {
    // ⚠️ Error durant la còpia
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ Error en copiar el fitxer: $e')),
    );
  }
}

  Future<void> _deleteCV() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cvPath');
    setState(() => _cvPath = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CV eliminat correctament')),
    );
  }

  Future<void> _testEmailSend() async {
    final prefs = await SharedPreferences.getInstance();
    final message = prefs.getString('emailMessage') ?? 'Hola, adjunto mi currículum.';
    final cvPath = prefs.getString('cvPath');

    if (cvPath == null || !File(cvPath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Has de pujar el teu CV abans d’enviar el correu.')),
      );
      return;
    }

    final email = Email(
      body: message,
      subject: 'Working with you',
      recipients: [''],
      attachmentPaths: [cvPath],
      isHTML: false,
    );

    try {
      await FlutterEmailSender.send(email);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correu obert amb èxit!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error en enviar el correu: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar correu automàtic')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Text per al correu automàtic:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Escriu aquí el missatge que vols enviar...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _saveMessage,
                icon: const Icon(Icons.save),
                label: const Text('Desar missatge'),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pickAndSaveCV,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Pujar CV (PDF)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_cvPath != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _deleteCV,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar CV'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade300,
                          foregroundColor: Colors.black87,
                        ),
                      ),
                    ),
                ],
              ),

              if (_cvPath != null) ...[
                const SizedBox(height: 8),
                Text(
                  'CV actual: ${_cvPath!.split('/').last}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],

              const Divider(height: 32),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _testEmailSend,
                  icon: const Icon(Icons.mark_email_read_outlined),
                  label: const Text('Provar missatge'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
