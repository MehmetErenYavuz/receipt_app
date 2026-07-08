// ═══════════════════════════════════════════════════════════════════════
// RECEIPT PARSER — MODEL HİZALAMA TESTLERİ
// ═══════════════════════════════════════════════════════════════════════
// NER modelinin etiketlerine (TAX_ID, CARD_PAID, CASH_PAID) yönelik regex
// iyileştirmelerini doğrular:
//  - TAX_ID: VKN/TCKN checksum ile sahte 10-11 hane elenir, geçerli tercih edilir
//  - CARD/CASH: ödeme satırlarından gerçek tutar (parçalı ödeme dahil) çıkarılır
//  - NerRegexPool bu tutarları CASH_PAID/CARD_PAID olarak rescue havuzuna taşır
//
// Çalıştır: flutter test test/receipt_parser_model_align_test.dart
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_app/ml/ner_regex_pool.dart';
import 'package:receipt_app/models/receipt_data.dart';
import 'package:receipt_app/utils/receipt_parser.dart';

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
  group('TAX_ID — VKN/TCKN checksum', () {
    test('checksum geçen VKN, başka 10-haneli gürültüye tercih edilir', () {
      // 6980042624 = geçerli VKN (GİB). 1111111111 = etiketsiz gürültü.
      final r = ReceiptParser.parseFromElements(_layout('''
        ACME GIDA LTD STI
        MUSTERI NO 1111111111
        KADIKOY VD 6980042624
        TARIH 08.06.2026
        TOPLAM 100,00
        NAKIT 100,00
      '''));
      expect(r.vergiTcNo, '6980042624');
    });

    test('checksum geçen aday yoksa best-effort (geri uyumlu) döner', () {
      // 6980042625 = checksum BOZUK (geçerli VKN'nin son hanesi değiştirilmiş).
      final r = ReceiptParser.parseFromElements(_layout('''
        BAKKAL TICARET
        KADIKOY VD 6980042625
        TARIH 08.06.2026
        TOPLAM 100,00
        NAKIT 100,00
      '''));
      expect(r.vergiTcNo, '6980042625');
    });
  });

  group('CARD/CASH — gerçek ödeme tutarı (parçalı ödeme)', () {
    test('NAKİT + KREDİ KARTI ayrı tutarlar çıkar', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        RESTORAN LEZZET
        TARIH 08.06.2026
        ARA TOPLAM 250,00
        TOPLAM 250,00
        NAKIT 100,00
        KREDI KARTI 150,00
      '''));
      expect(r.nakitTutar, '100.00');
      expect(r.kartTutar, '150.00');
      expect(r.toplamTutar, '250.00');
    });
  });

  group('₺/TL yanındaki rakam kaybı — eksik toplam düzeltme', () {
    test('toplam ₺ nedeniyle eksik okunmuş, matrah+KDV+ödeme ile düzeltilir', () {
      // Gerçek toplam 1431,21 ama ₺ baştaki 1 yutulmuş → "431,21" okunmuş.
      final r = ReceiptParser.parseFromElements(_layout('''
        MARKET X TICARET A.S.
        ISTIKLAL CAD. NO 5
        TARIH 14.06.2026
        MATRAH 1.373,94
        TOPKDV 57,27
        TOPLAM 431,21
        NAKIT 1.431,21
      '''));
      expect(r.toplamTutar, '1431.21');
      expect(r.toplamKdv, '57.27');
    });

    test('matrah+KDV ≈ toplam ise dokunulmaz (yanlış-pozitif yok)', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        MARKET X TICARET A.S.
        TARIH 14.06.2026
        MATRAH 400,00
        TOPKDV 31,21
        TOPLAM 431,21
        NAKIT 431,21
      '''));
      expect(r.toplamTutar, '431.21');
    });
  });

  group('Para üstü — nakit ödemede mal bedeli = verilen − para üstü', () {
    test('toplam yok, nakit+para üstü → mal bedeli düzeltilir', () {
      // Mal 11,50; müşteri 12,00 verdi; para üstü 0,50. Toplam 12 sanılmamalı.
      final r = ReceiptParser.parseFromElements(_layout('''
        BAKKAL
        TARIH 14.06.2026
        NAKIT 12,00
        PARA USTU 0,50
      '''));
      expect(r.toplamTutar, '11.50');
    });

    test('doğru toplam varken para üstü ile yanlış düzeltme yapılmaz', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        MARKET
        TARIH 14.06.2026
        TOPLAM 11,50
        NAKIT 12,00
        PARA USTU 0,50
      '''));
      expect(r.toplamTutar, '11.50');
    });
  });

  group('Fatura toplamı — FAT.TOP / FAT . TOP. genel toplamdır', () {
    test('FAT.TOP, MAL HİZMET TOPLAM (alt-toplam) yerine genel toplam olur', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        ABC BILISIM TICARET LTD STI
        E-ARSIV FATURA
        TARIH 14.06.2026
        MAL HIZMET TOPLAM 1.000,00
        HESAPLANAN KDV 200,00
        FAT.TOP 1.200,00
        KREDI KARTI 1.200,00
      '''));
      expect(r.toplamTutar, '1200.00');
      expect(r.toplamKdv, '200.00');
    });

    test('boşluklu "FAT . TOP." varyantı da yakalanır', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        XYZ LTD STI
        TARIH 14.06.2026
        ARA TOPLAM 415,00
        FAT . TOP. 489,90
        KREDI KARTI 489,90
      '''));
      expect(r.toplamTutar, '489.90');
    });
  });

  group('VKN — checksum-korumalı OCR onarımı (5↔6 vb.)', () {
    test('VD satırında 5→6 okunmuş VKN, checksum ile onarılır', () {
      // 1000500015 geçerli VKN; OCR 5'i 6 okumuş → 1000600015 (geçersiz).
      // Tek-haneli OCR onarımı BENZERSİZ olarak 1000500015'e döndürür.
      final r = ReceiptParser.parseFromElements(_layout('''
        ACME GIDA LTD STI
        KADIKOY VD 1000600015
        TARIH 14.06.2026
        TOPLAM 100,00
        NAKIT 100,00
      '''));
      expect(r.vergiTcNo, '1000500015');
    });
  });

  group('Tek-oran KDV-dahil ters hesap (toplam × oran / (100+oran))', () {
    test('KDV hiç okunmadıysa tek orandan türetilir (fill)', () {
      // %10, toplam 110, KDV satırı yok → KDV = 110×10/110 = 10, matrah 100.
      final r = ReceiptParser.parseFromElements(_layout('''
        KAHVE DUNYASI
        TARIH 14.06.2026
        %10
        GENEL TOPLAM 110,00
        NAKIT 110,00
      '''));
      expect(r.toplamKdv, '10.00');
      expect(r.kdvHaricToplam, '100.00');
    });

    test('okunan KDV, tek görünen oranla EZİLMEZ (çok-oranlı maskesi koruması)', () {
      // Tek "%20" markeri var ama okunan TOPKDV 44 (≈ çok-oranlı karışım olabilir).
      // Mevcut KDV ezilmez → okunan değer korunur (yanlış-pozitif önleme).
      final r = ReceiptParser.parseFromElements(_layout('''
        KOFTECI YUSUF
        TARIH 14.06.2026
        %20
        ARA TOPLAM 200,00
        TOPKDV 44,00
        GENEL TOPLAM 240,00
        NAKIT 240,00
      '''));
      expect(r.toplamTutar, '240.00');
      expect(r.toplamKdv, '44.00');
    });

    test('eski oran %8 derive edilmez; okunan KDV korunur', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        RESTORAN
        TARIH 14.06.2026
        %8
        ARA TOPLAM 200,00
        TOPKDV 16,00
        GENEL TOPLAM 216,00
        NAKIT 216,00
      '''));
      expect(r.toplamKdv, '16.00');
    });

    test('çok oranlı fişte tek-oran ters hesap devreye girmez', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        MARKET
        TARIH 14.06.2026
        EKMEK %20 60,00
        SUT %10 33,00
        TOPKDV 33,00
        GENEL TOPLAM 233,00
        NAKIT 233,00
      '''));
      expect(r.toplamKdv, '33.00');
    });
  });

  group('NerRegexPool — gerçek CARD/CASH tutarı rescue havuzuna geçer', () {
    test('nakit/kart tutarı CASH_PAID/CARD_PAID olur (toplam kabası değil)', () {
      final data = ReceiptData(
        toplamTutar: '250.00',
        odemeYontemi: 'Kredi Kartı',
        nakitTutar: '100.00',
        kartTutar: '150.00',
      );
      final pool = NerRegexPool.fromReceiptData(data);
      expect(pool['CASH_PAID'], ['100.00']);
      expect(pool['CARD_PAID'], ['150.00']);
    });
  });
}
