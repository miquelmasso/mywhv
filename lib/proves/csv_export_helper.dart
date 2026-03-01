import 'dart:io';

import 'package:path_provider/path_provider.dart';

String csvEscape(String value) {
  final escaped = value.replaceAll('"', '""');
  final mustQuote =
      escaped.contains(',') || escaped.contains('"') || escaped.contains('\n');
  return mustQuote ? '"$escaped"' : escaped;
}

String timestampForFileName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

Future<Directory> resolveCsvExportDirectory() async {
  final appDocuments = await getApplicationDocumentsDirectory();

  // iOS Simulator: try to save directly in host Mac Downloads.
  if (Platform.isIOS) {
    const simulatorMarker = '/Library/Developer/CoreSimulator/Devices/';
    final idx = appDocuments.path.indexOf(simulatorMarker);
    if (idx > 0) {
      final macHome = appDocuments.path.substring(0, idx);
      final downloads = Directory('$macHome/Downloads');
      if (await downloads.exists()) {
        return downloads;
      }
    }
  }

  if (Platform.isAndroid) {
    final external = await getExternalStorageDirectory();
    if (external != null) {
      return external;
    }
  }

  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    final downloads = Directory('$home/Downloads');
    if (await downloads.exists()) {
      return downloads;
    }
  }

  return appDocuments;
}

Future<String> exportRowsAsCsv({
  required String filePrefix,
  required List<String> headers,
  required List<List<String>> rows,
}) async {
  final csvRows = <String>[
    headers.map(csvEscape).join(','),
    ...rows.map((row) => row.map(csvEscape).join(',')),
  ];

  final directory = await resolveCsvExportDirectory();
  final fileName = '${filePrefix}_${timestampForFileName(DateTime.now())}.csv';
  final file = File('${directory.path}/$fileName');
  await file.writeAsString(csvRows.join('\n'), flush: true);
  return file.path;
}
