// ═══════════════════════════════════════════════════════════════════════
// BIO ENTITY TOPLAMA PARİTE TESTİ — output_contract.md §2 worked example
// ═══════════════════════════════════════════════════════════════════════
// Gerçek gold fişi (img_9ddd905bcc28) için belgelenen BIO tahminlerinden
// sentetik one-hot logits üretilir; NerEntities.collect çıktısının §2'deki
// toplanmış entity havuzuyla BİREBİR eşleştiği assert edilir.
//
// Çalıştır: flutter test test/ner_entities_test.dart
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_app/ml/ner_entities.dart';
import 'package:receipt_app/ml/ner_labels.dart';

// label string → id (kId2Label'ın tersi).
int _id(String label) => kId2Label.indexOf(label);

// 31 sınıflı one-hot logit vektörü (hot indeks = label id).
List<double> _oneHot(String label) {
  final v = List<double>.filled(kId2Label.length, 0.0);
  v[_id(label)] = 1.0;
  return v;
}

void main() {
  test('output_contract §2: img_9ddd905bcc28 entity toplama', () {
    // input_contract §5(a) ham token sırası (ilk 24) + [TYPE=FIS] prefix.
    final words = <String>[
      '[TYPE=FIS]', // 0
      'AAKUSfu', // 1  B-VENDOR_NAME
      'Kor', // 2
      'Ge', // 3
      'EFETI', // 4  B-VENDOR_NAME
      'KARAL', // 5  I-VENDOR_NAME
      'ut', // 6
      'TUZLUAYER', // 7
      'M', // 8
      '8', // 9
      'CD', // 10
      'piKiMEVvi', // 11
      'vD.tri9610', // 12 B-TAX_ID
      '08/112025', // 13 B-DATE
      '20:20', // 14 B-TIME
      'YlYECEK', // 15
      '"/00,00', // 16
      'KDV', // 17
      '*63,64', // 18 B-VAT_TOTAL
      'TOPLAM', // 19
      '*700,00', // 20 B-TOTAL
      'Kredi', // 21
      'Karli', // 22
      '/00,00', // 23
      '1ARM:e.11', // 24
    ];

    // Kelime başına etiket (varsayılan O); §2'deki "O olmayanlar".
    final labels = List<String>.filled(words.length, 'O');
    labels[1] = 'B-VENDOR_NAME';
    labels[4] = 'B-VENDOR_NAME';
    labels[5] = 'I-VENDOR_NAME';
    labels[12] = 'B-TAX_ID';
    labels[13] = 'B-DATE';
    labels[14] = 'B-TIME';
    labels[18] = 'B-VAT_TOTAL';
    labels[20] = 'B-TOTAL';

    // Sentetik 1:1 hizalama: her kelime tam bir subword (pos = kelime indeksi).
    final wordIds = <int?>[for (int i = 0; i < words.length; i++) i];
    final logits = <List<double>>[for (final l in labels) _oneHot(l)];

    final ner = NerEntities.collect(logits, wordIds, words);

    expect(ner['VENDOR_NAME'], ['AAKUSfu', 'EFETI KARAL']);
    expect(ner['TAX_ID'], ['vD.tri9610']);
    expect(ner['DATE'], ['08/112025']);
    expect(ner['TIME'], ['20:20']);
    expect(ner['VAT_TOTAL'], ['*63,64']);
    expect(ner['TOTAL'], ['*700,00']);
    // O olan kelimeler hiçbir tipe girmez.
    expect(ner.containsKey('O'), isFalse);
    expect(ner.length, 6);
  });

  test('truncation: ilk subword düşen kelime açık entity\'yi kapatır', () {
    // 3 kelime: B-TOTAL, I-TOTAL ama 2. kelime truncation ile düşmüş (wordId yok).
    final words = ['[TYPE=FIS]', '*700', ',00'];
    // wordIds yalnız 0 ve 1'i içeriyor; kelime 2 truncate edilmiş.
    final wordIds = <int?>[0, 1];
    final logits = <List<double>>[_oneHot('O'), _oneHot('B-TOTAL')];

    final ner = NerEntities.collect(logits, wordIds, words);
    // Kelime 2 düştüğü için entity '*700' ile kapanır.
    expect(ner['TOTAL'], ['*700']);
  });
}
