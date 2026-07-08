// ═══════════════════════════════════════════════════════════════════════
// POSTPROCESS PARİTE TESTİ — output_contract.md §3 worked example + math
// ═══════════════════════════════════════════════════════════════════════
// img_9ddd905bcc28'in §2 entity havuzu → NerPostprocess.build → §5.2 JSON;
// dokümandaki belgelenen §5.2 çıktısıyla BİREBİR karşılaştırılır. Ek olarak
// parse_money float tuzağı, VKN/TCKN checksum, infer_vat_rate, sum_distinct.
//
// ONNX gerekmez (saf Dart) → flutter test ile koşar. INT8 sayısal uyumu
// arkadaş tarafından torch'a karşı zaten doğrulandı (0.967).
//
// Çalıştır: flutter test test/ner_postprocess_test.dart
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_app/ml/doctype_classifier.dart';
import 'package:receipt_app/ml/ner_postprocess.dart';

void main() {
  group('output_contract §3 worked example (img_9ddd905bcc28)', () {
    test('§2 entity havuzu → §5.2 JSON birebir', () {
      final ner = <String, List<String>>{
        'VENDOR_NAME': ['AAKUSfu', 'EFETI KARAL'],
        'TAX_ID': ['vD.tri9610'],
        'DATE': ['08/112025'],
        'TIME': ['20:20'],
        'VAT_TOTAL': ['*63,64'],
        'TOTAL': ['*700,00'],
      };

      final res = NerPostprocess.build(
        ner: ner,
        regex: const {},
        doctype: const DoctypeResult('fis', 1.0),
        truncated: false,
      );

      // postprocess_logic §5: NER yalnız lump VAT_TOTAL verdi, oran (10)
      // infer_vat_rate ile çıkarıldı → vat_10/base_10 türetildi, _source "derived".
      final expected = <String, dynamic>{
        'doc_type': 'fis',
        'doc_type_confidence': 1.0,
        'fields': {
          'vendor_name': {'value': 'AAKUSfu', 'confidence': 0.80},
          'tax_id': {
            'value': '9610', // OCR VKN'yi bozmuş; NER yerini buldu → korunur
            'kind': null,
            'checksum_ok': false,
            'confidence': 0.80,
          },
          'date': {'value': '08/112025', 'confidence': 0.80}, // ayraçsız → ham
          'time': {'value': '20:20', 'confidence': 0.80},
          'total': {'value': 700.0, 'confidence': 0.80},
          'subtotal': {'value': 636.36, 'confidence': 0.55}, // türetildi
          'vat': {
            'vat_10': 63.64,
            'base_10': 636.4,
            'vat_total': 63.64,
            '_source': 'derived',
          },
        },
        'warnings': <String>[],
      };

      expect(res.toJson(), expected);
    });
  });

  group('parse_money — TR para + FLOAT TUZAĞI', () {
    test('sayısal girdi DOĞRUDAN döner (60.0 → 60.0, ASLA 600.0)', () {
      expect(NerPostprocess.parseMoney(60.0), 60.0);
      expect(NerPostprocess.parseMoney(700), 700.0);
    });
    test('TR ondalık/binlik kuralları', () {
      expect(NerPostprocess.parseMoney('1.234,56'), 1234.56);
      expect(NerPostprocess.parseMoney('432.40'), 432.40);
      expect(NerPostprocess.parseMoney('45,80'), 45.80);
      expect(NerPostprocess.parseMoney('1,234.56'), 1234.56);
      expect(NerPostprocess.parseMoney('1.234'), 1234.0); // ondalık yok → binlik
      expect(NerPostprocess.parseMoney('₺1.234,56'), 1234.56);
      expect(NerPostprocess.parseMoney('*15,00*'), 15.00);
      expect(NerPostprocess.parseMoney(''), isNull);
      expect(NerPostprocess.parseMoney(null), isNull);
    });
  });

  group('TAX_ID checksum', () {
    test('geçerli VKN (GİB algoritması)', () {
      expect(NerPostprocess.vknValid('6980042624'), isTrue);
      expect(NerPostprocess.taxidKind('6980042624'), 'VKN');
    });
    test('geçersizler', () {
      expect(NerPostprocess.taxidKind('9610'), isNull); // çok kısa
      expect(NerPostprocess.vknValid('6980042625'), isFalse); // check hanesi bozuk
      expect(NerPostprocess.tcknValid('06980042624'), isFalse); // n[0]=='0'
    });
  });

  group('infer_vat_rate ve sum_distinct', () {
    test('infer_vat_rate tek-oran tahmini', () {
      expect(NerPostprocess.inferVatRate('*63,64', '*700,00'), 10);
      expect(NerPostprocess.inferVatRate('45,80', '274,80'), 20);
      // sapma > %3 → null (uydurma yok)
      expect(NerPostprocess.inferVatRate('100,00', '150,00'), isNull);
    });
    test('sum_distinct tekrarı eler, farklıyı toplar', () {
      expect(NerPostprocess.sumDistinct(['350,00', '350,00', '200,00']), 550.0);
      expect(NerPostprocess.sumDistinct(['200,00', '206,80']), 406.80);
    });
  });
}
