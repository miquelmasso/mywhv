import 'dart:io';
import 'package:http/io_client.dart';

/// 🔐 Crea un client HTTP que ignora certificats invàlids (només per proves)
HttpClient createUnsafeClient() {
  final client = HttpClient();
  client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  return client;
}

final ioClient = IOClient(createUnsafeClient());
