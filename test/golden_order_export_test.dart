// ═══════════════════════════════════════════════════════════════════════
// GOLDEN ORDER EXPORT — dart_order.json üretici
// ═══════════════════════════════════════════════════════════════════════
// Arkadaşın model eğitimi için: ortak OCR (test/fixtures/golden_docs.json)
// uygulamanın GERÇEK satır-sıralama mantığından (ReceiptParser._buildRows)
// geçirilir ve okuma sırası + tam parse çıktısı `dart_order.json` olarak
// repo köküne yazılır.
//
// Arkadaşın AYNI golden_docs.json'dan Python'da `python_order.json` üretip
// diff'lersiniz. Karşılaştırma kuralı dosyanın "row_grouping" başlığındadır.
//
// Çalıştır:  flutter test test/golden_order_export_test.dart
// Çıktı:     dart_order.json   (repo kökü)
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_app/models/receipt_data.dart';
import 'package:receipt_app/utils/receipt_parser.dart';

void main() {
  test('golden_docs.json → dart_order.json üret', () {
    final inFile = File('test/fixtures/golden_docs.json');
    expect(inFile.existsSync(), isTrue,
        reason: 'test/fixtures/golden_docs.json bulunamadı.');

    final root = jsonDecode(inFile.readAsStringSync()) as Map<String, dynamic>;
    final docs = (root['documents'] as List).cast<Map<String, dynamic>>();

    final outDocs = <Map<String, dynamic>>[];

    for (final doc in docs) {
      final imageId = doc['image_id'] as String;

      // blok → satır → eleman akış sırasını koruyarak düzleştir.
      final els = <({String text, double x, double y, double w, double h})>[];
      for (final block in (doc['blocks'] as List)) {
        for (final line in ((block as Map)['lines'] as List)) {
          for (final el in ((line as Map)['elements'] as List)) {
            final bb = (el as Map)['bounding_box'] as Map<String, dynamic>;
            final left = (bb['left'] as num).toDouble();
            final top = (bb['top'] as num).toDouble();
            final right = (bb['right'] as num).toDouble();
            final bottom = (bb['bottom'] as num).toDouble();
            els.add((
              text: el['text'] as String,
              x: left,
              y: top,
              w: right - left,
              h: bottom - top,
            ));
          }
        }
      }

      final order = ReceiptParser.orderFromElements(els);
      final parsed = ReceiptParser.parseFromElements(els);

      outDocs.add({
        'image_id': imageId,
        'element_count': els.length,
        'row_count': order.length,
        'order': order,
        'parsed': _receiptToJson(parsed),
      });
    }

    final out = <String, dynamic>{
      'generated_by': 'dart',
      'source': 'golden_docs.json',
      // Python tarafının BİREBİR taklit etmesi gereken kurallar:
      'row_grouping': {
        'y_center': '(top + bottom) / 2',
        'tolerance': 'clamp(height * 0.65, 8, 28)   (height = bottom - top)',
        'assign': 'eleman akış sırasında, |row.yCenter - yc| < tol olan İLK '
            'satıra eklenir; satır yCenter\'ı çalışan ortalama ile güncellenir',
        'row_sort': 'yCenter artan; eşitlikte satırdaki min input-order',
        'token_sort': 'left artan; eşitlikte input-order (stable)',
        'note': 'order.text HAM token birleşimidir (OCR düzeltmesi yok).',
      },
      'documents': outDocs,
    };

    final outFile = File('dart_order.json');
    outFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(out));

    // ignore: avoid_print
    print('✅ dart_order.json yazıldı → ${outFile.absolute.path} '
        '(${outDocs.length} belge)');

    expect(outDocs.length, docs.length);
  });
}

/// ReceiptData → düz JSON (model dosyasını kirletmemek için burada).
Map<String, dynamic> _receiptToJson(ReceiptData r) => {
      'firmaAdi': r.firmaAdi,
      'firmaAdresi': r.firmaAdresi,
      'vergiDairesi': r.vergiDairesi,
      'vergiTcNo': r.vergiTcNo,
      'belgeTuru': r.belgeTuru,
      'fisNo': r.fisNo,
      'seriNo': r.seriNo,
      'zNo': r.zNo,
      'ekuNo': r.ekuNo,
      'ettn': r.ettn,
      'mersisNo': r.mersisNo,
      'iban': r.iban,
      'tarih': r.tarih,
      'saat': r.saat,
      'kdvDetay': [
        for (final k in r.kdvDetay)
          {'oran': k.oran, 'matrah': k.matrah, 'tutar': k.tutar}
      ],
      'toplamKdv': r.toplamKdv,
      'kdvHaricToplam': r.kdvHaricToplam,
      'araToplam': r.araToplam,
      'toplamTutar': r.toplamTutar,
      'odemeYontemi': r.odemeYontemi,
      'paraUstu': r.paraUstu,
      'paraBirimi': r.paraBirimi,
      'yakitTuru': r.yakitTuru,
      'yakitLitre': r.yakitLitre,
      'pompaNo': r.pompaNo,
      'aracPlakasi': r.aracPlakasi,
      'telefon': r.telefon,
      'kategori': r.kategori,
      'uyari': r.uyari,
    };
