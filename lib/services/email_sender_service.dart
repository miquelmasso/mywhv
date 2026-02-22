import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';

class EmailSenderService {
  static const _emailMessageKey = 'emailMessage';

  static Future<String?> getSavedEmailContent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailMessageKey);
  }

  static Future<void> sendEmail({
    required BuildContext context,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final message = prefs.getString(_emailMessageKey) ?? 'Hola, adjunto mi currículum.';
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
    } catch (e) {
      // Silence UI to avoid disruptive snackbars; surface errors via logs if needed.
    }
  }
}
