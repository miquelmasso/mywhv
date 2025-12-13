import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  await Firebase.initializeApp();

  final file = File('harvest_2025.json');
  final data = jsonDecode(await file.readAsString());

  final firestore = FirebaseFirestore.instance;
  final batch = firestore.batch();

  int docs = 0;

  for (final state in data['states']) {
    final stateCode = state['state'];

    for (final region in state['regions']) {
      final regionName = region['region_name'];
      final postcode = region['postcode'] ?? '';

      final docId =
          '${stateCode}_${postcode}_${regionName}'.replaceAll(' ', '_');

      final ref =
          firestore.collection('harvest_calendar').doc(docId);

      batch.set(ref, {
        'state': stateCode,
        'region_name': regionName,
        'postcode': postcode,
        'map_url': region['map_url'],
        'crops': region['crops'],
        'source': 'backpackerjobboard',
        'year': 2025,
        'timestamp': FieldValue.serverTimestamp(),
      });

      docs++;
    }
  }

  await batch.commit();
  print('✅ Imported $docs harvest regions');
}
