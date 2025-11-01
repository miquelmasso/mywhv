import 'package:cloud_firestore/cloud_firestore.dart';

/// 🔥 Uploader simplificat dels codis postals per la Working Holiday Visa (417/462)
/// Basat en la informació oficial del Department of Home Affairs (octubre 2025)
/// Només inclou: 
///   - Tourism and Hospitality (Remote & Very Remote Australia)
///   - Regional Australia
class VisaPostcodesUploader {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> uploadVisaPostcodes() async {
    print('🚀 Iniciant pujada de codis postals...');

    final industriesCollection = _firestore.collection('visa_postcodes');

    // 🧹 Esborra dades antigues (opcional)
    await _clearCollection(industriesCollection);

    // 📋 Només les categories que ens interessen
    final Map<String, List<int>> industryMap = {
      // ────────────────────────────────
      // Tourism & Hospitality (Remote & Very Remote Australia)
      // ────────────────────────────────
      "Tourism and Hospitality (Remote & Very Remote Australia)": [
        ..._expand([
          "2356", "2386", "2387", "2396", "2405", "2406", "2672", "2675",
          "2825", "2826", "2829", "2832-2836", "2838-2840", "2873", "2878",
          "2879", "2898", "2899"
        ]),
        ..._expand([
          "4025", "4183", "4417-4420", "4422", "4423", "4426-4428",
          "4454", "4461", "4462", "4465", "4467", "4468", "4470",
          "4474", "4475", "4477-4482", "4486-4494", "4496", "4497",
          "4680", "4694", "4695", "4697", "4699-4707", "4709-4714",
          "4717", "4720-4728", "4730-4733", "4735-4746", "4750",
          "4751", "4753", "4754", "4756", "4757", "4798-4812",
          "4814-4825", "4828-4830", "4849", "4850", "4852", "4854-4856",
          "4858-4861", "4865", "4868-4888", "4890-4892", "4895",
          "4406", "4416", "4498", "7215"
        ]),
        ..._expand(["3424", "3506", "3509", "3512", "3889-3892"]),
        ..._expand([
          "5220-5223", "5302-5304", "5440", "5576", "5577", "5582",
          "5583", "5602-5607", "5611", "5630-5633", "5640-5642",
          "5650-5655", "5660", "5661", "5670", "5671", "5680",
          "5690", "5713", "5715", "5717", "5719", "5720",
          "5722-5725", "5730-5734"
        ]),
        ..._expand(["7139", "7255-7257", "7466-7470"]),
        ..._expand([
          "6161", "6335-6338", "6341", "6343", "6346", "6348",
          "6350-6353", "6355-6359", "6361", "6363", "6365",
          "6367-6369", "6373", "6375", "6385", "6386",
          "6418-6429", "6431", "6434", "6436-6438", "6440",
          "6443", "6445-6448", "6450", "6452", "6466-6468",
          "6470", "6472", "6473", "6475-6477", "6479", "6480",
          "6484", "6487-6490", "6515", "6517-6519", "6536",
          "6605", "6606", "6608", "6609", "6612-6614", "6616",
          "6620", "6623", "6625", "6627", "6628", "6630-6632",
          "6635", "6638-6640", "6731", "6733", "6798", "6799"
        ]),
        // NT all
        // ..._expand(["0800-0999"]),
      ],

      // ────────────────────────────────
      // Regional Australia
      // ────────────────────────────────
      "Regional Australia": [
        ..._expand([
          "2311-2312", "2328-2411", "2420-2490", "2536-2551",
          "2575-2594", "2618-2739", "2787-2899"
        ]),
        ..._expand([
          "3139", "3211-3334", "3340-3424", "3430-3649", "3658-3749",
          "3753", "3756", "3758", "3762", "3764", "3778-3781",
          "3783", "3797", "3799", "3810-3909", "3921-3925",
          "3945-3974", "3979", "3981-3996"
        ]),
        ..._expand([
          "4124-4125", "4133", "4211", "4270-4272", "4275", "4280",
          "4285", "4287", "4307-4499", "4510", "4512", "4515-4519",
          "4522-4899"
        ]),
        ..._expand([
          "6041-6044", "6055-6056", "6069", "6076", "6083-6084",
          "6111", "6121-6126", "6200-6799",
        ]),
        // NT (0800-0999), SA (5000-5999), TAS (7000-7999)
      ],
    };

    // 🔁 Sincronitza amb Firestore
    for (final entry in industryMap.entries) {
      final industry = entry.key;
      final postcodes = entry.value.toSet().toList();

      await industriesCollection.doc(industry).set({
        "industry": industry,
        "postcodes": postcodes,
      });

      print("✅ $industry → ${postcodes.length} codis pujats");
    }

    print("🎉 Codis pujats correctament!");
  }

  static Future<void> _clearCollection(CollectionReference ref) async {
    final snapshots = await ref.get();
    for (var doc in snapshots.docs) {
      await doc.reference.delete();
    }
  }

  /// 📦 Expandeix intervals de codis "2800-2803" → [2800, 2801, 2802, 2803]
  static List<int> _expand(List<String> entries) {
    final result = <int>[];
    for (var e in entries) {
      if (e.contains('-')) {
        final parts = e.split('-');
        final start = int.parse(parts[0]);
        final end = int.parse(parts[1]);
        for (var i = start; i <= end; i++) {
          result.add(i);
        }
      } else {
        result.add(int.parse(e));
      }
    }
    return result;
  }
}
