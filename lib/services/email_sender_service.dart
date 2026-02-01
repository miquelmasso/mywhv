import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';

class EmailSenderService {
  static Future<void> sendEmail({
    required BuildContext context,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final message =
        prefs.getString('emailMessage') ?? 'Hola, adjunto mi currículum.';
    final cvPath = prefs.getString('cvPath');

    final attachments = <String>[];
    if (cvPath != null && cvPath.isNotEmpty) {
      attachments.add(cvPath);
    }

    final emailToSend = Email(
      body: message,
      subject: 'Working with you',
      recipients: [email.trim()],
      attachmentPaths: attachments,
      isHTML: false,
    );

    try {
      await FlutterEmailSender.send(emailToSend);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correu preparat amb èxit!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error en enviar el correu: $e')),
      );
    }
  }
}
