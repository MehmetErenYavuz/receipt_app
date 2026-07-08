// ═══════════════════════════════════════════════════════════════════════
// RECEIPT PARSER — KDV / TOPLAM AYRIM TESTLERİ (Türk fiş yapıları)
// ═══════════════════════════════════════════════════════════════════════
// Kullanıcı raporu: "KDV tutarının üstündeki/KDV kısmında Toplam tutarın
// değeri yazıyor." Bu dosya, KDV alanına Genel Toplam / Matrah sızmasının
// tüm bilinen yollarını kapatan regresyon testlerini içerir.
//
// Çalıştır:  flutter test test/receipt_parser_kdv_test.dart
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_app/utils/receipt_parser.dart';

/// Çok satırlı metni koordinatlı OCR elemanlarına çevirir.
List<({String text, double x, double y, double w, double h})> _layout(
    String raw) {
  final out = <({String text, double x, double y, double w, double h})>[];
  final lines = raw.split('\n');
  double y = 0;
  for (final line in lines) {
    final trimmed = line.trim();
    y += 40;
    if (trimmed.isEmpty) continue;
    double x = 0;
    for (final word in trimmed.split(RegExp(r'\s+'))) {
      final w = word.length * 12.0;
      out.add((text: word, x: x, y: y, w: w, h: 24.0));
      x += w + 14;
    }
  }
  return out;
}

void main() {
  group('KDV tutarı asla Genel Toplam göstermez', () {
    test('"KDV DAHİL TOPLAM" satırı KDV alanına yazılmaz', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        CAFE KEYIF
        DENIZ MAH SOK 3
        TARIH 09.06.2026 SAAT 10:00
        ARA TOPLAM 200,00
        KDV DAHIL TOPLAM 233,50
        NAKIT 233,50
      '''));
      expect(r.toplamTutar, '233.50');
      expect(r.toplamKdv == '233.50', isFalse);
    });

    test('"TOPLAM KDV DAHİL" satırı KDV olarak okunmaz; HESAPLANAN KDV gerçek değer', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        MARKET DUKKAN
        ATATURK BULVARI NO 7
        TARIH 05.05.2026
        MATRAH 200,00
        HESAPLANAN KDV 33,50
        TOPLAM KDV DAHIL 233,50
        NAKIT 233,50
      '''));
      expect(r.toplamTutar, '233.50');
      expect(r.toplamKdv, '33.50');
    });

    test('"ÖDENECEK" toplamı KDV ile karışmaz', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        SOK MARKET
        CUMHURIYET MAH
        TARIH 09.06.2026
        ODENECEK 233,50
        KDV 33,50
        NAKIT 233,50
      '''));
      expect(r.toplamTutar, '233.50');
      expect(r.toplamKdv, '33.50');
    });

    test('KDV oranı toplamın %30\'unu aşamaz — saçma KDV temizlenir', () {
      // KDV alanına yanlışlıkla 200 (ara toplam) okunmuş; matematiksel olarak
      // imkânsız (200/233.50 = %85). Düzeltilmeli ya da boşaltılmalı.
      final r = ReceiptParser.parseFromElements(_layout('''
        BAKKAL
        TARIH 09.06.2026
        MATRAH 200,00
        KDV 200,00
        TOPLAM 233,50
        NAKIT 233,50
      '''));
      expect(r.toplamTutar, '233.50');
      // 200 saçma; matrah+toplamdan 33.50 türetilmeli (ya da en azından 200 olmamalı).
      expect(r.toplamKdv == '200.00', isFalse);
    });
  });

  group('KDV kırılımı (detay) yanlış değer göstermez', () {
    test('%oran satırındaki tek matrah, KDV tutarı sanılmaz', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        SOK MARKET
        CUMHURIYET MAH
        TARIH 09.06.2026
        %20 200,00
        TOPKDV 33,50
        TOPLAM 233,50
        NAKIT 233,50
      '''));
      expect(r.toplamKdv, '33.50');
      expect(r.toplamTutar, '233.50');
      // 200,00 matrahtır; hiçbir KDV kırılımı tutarı 200.00 olmamalı.
      expect(r.kdvDetay.every((i) => i.tutar != '200.00'), isTrue);
    });

    test('"KDV" kelimeli satırdaki tek tutar KDV olarak alınır', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        RESTORAN LEZZET
        TARIH 09.06.2026
        ARA TOPLAM 200,00
        KDV %8 16,00
        GENEL TOPLAM 216,00
        NAKIT 216,00
      '''));
      expect(r.toplamTutar, '216.00');
      expect(r.toplamKdv, '16.00');
    });

    test('Ürün satırlarındaki %oranlar KDV kırılımına matrah/total sızdırmaz', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        BIM MARKET
        YENI MAH
        TARIH 09.06.2026
        EKMEK %20 5,00
        SUT %1 30,00
        DETERJAN %20 120,00
        ARA TOPLAM 155,00
        TOPKDV 21,00
        TOPLAM 176,00
        KREDI KARTI 176,00
      '''));
      expect(r.toplamTutar, '176.00');
      expect(r.toplamKdv, '21.00');
      // Ürün fiyatları (120,00 gibi) KDV tutarı olarak görünmemeli.
      expect(r.kdvDetay.every((i) => i.tutar != '120.00'), isTrue);
      expect(r.kdvDetay.every((i) => i.tutar != '155.00'), isTrue);
    });

    test('Tablo formatı: %oran matrah kdv → doğru matrah ve KDV', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        MIGROS
        TARIH 09.06.2026
        %20 200,00 40,00
        ARA TOPLAM 200,00
        TOPLAM 240,00
        NAKIT 240,00
      '''));
      expect(r.toplamTutar, '240.00');
      // Tablo satırından KDV 40,00 okunmalı.
      expect(r.toplamKdv, '40.00');
    });
  });

  group('Genel toplam — KDV dahil etiketli satırdan okunur', () {
    test('Sadece "KDV DAHİL TOPLAM" varsa toplam yine bulunur', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        LOKANTA X
        TARIH 09.06.2026
        KDV DAHIL TOPLAM 489,90
        KREDI KARTI 489,90
      '''));
      expect(r.toplamTutar, '489.90');
    });
  });
}
