// ═══════════════════════════════════════════════════════════════════════
// RECEIPT PARSER — BİRİM TESTLERİ
// ═══════════════════════════════════════════════════════════════════════
// ML Kit'e ihtiyaç DUYMADAN çalışır: ReceiptParser.parseFromElements ile
// metin + koordinat besleyerek gerçek saha mantığını (satır birleştirme +
// tüm regex'ler + KDV/Toplam çapraz doğrulama) uçtan uca test eder.
//
// `_layout(...)` yardımcı fonksiyonu, çok satırlı düz metni gerçekçi
// koordinatlı OCR elemanlarına çevirir: her satır artan y, her kelime artan x.
//
// Çalıştır:  flutter test test/receipt_parser_test.dart
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
    y += 40; // satırlar arası boşluk (tol ~15.6'dan büyük → ayrı satır)
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
  group('Fiyat regex — binlik ayraçsız 1000+ tutar (kritik hata)', () {
    test('1234,56 → 1234.56 (eskiden 234.56 okunuyordu)', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        RESTORAN LEZZET DURAGI
        ISTANBUL CAD. NO 12
        TARIH 08.06.2026 SAAT 13:20
        ADET YEMEK 1234,56
        TOPLAM 1234,56
        NAKIT 1234,56
      '''));
      expect(r.toplamTutar, '1234.56');
    });

    test('binlik ayraçlı 1.234,56 → 1234.56', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        KOFTECI YUSUF
        MERKEZ MAH. SOK 5
        TARIH 08.06.2026
        ARA TOPLAM 1.000,00
        TOPLAM 1.234,56
        KREDI KARTI 1.234,56
      '''));
      expect(r.toplamTutar, '1234.56');
    });

    test('on binli tutar 12.345,67 → 12345.67', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        TEKNOSA ELEKTRONIK A.S.
        BAGDAT CAD. NO 100
        TARIH 02.01.2026
        TUTAR ARA 10.000,00
        GENEL TOPLAM 12.345,67
        BANKA KARTI 12.345,67
      '''));
      expect(r.toplamTutar, '12345.67');
    });
  });

  group('KDV ve Toplam ayrımı', () {
    test('uzun fiş: çok %-satırı varken Toplam ve KDV karışmaz', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        SOK MARKET
        CUMHURIYET MAH.
        TARIH 01.03.2026 SAAT 18:05
        EKMEK %20 5,00
        SUT %1 30,00
        CIKOLATA %20 45,00
        DETERJAN %20 120,00
        ARA TOPLAM 200,00
        TOPKDV 33,50
        TOPLAM 233,50
        KREDI KARTI 233,50
      '''));
      expect(r.toplamTutar, '233.50');
      expect(r.toplamKdv, '33.50');
    });

    test('KDV >= Toplam + matrah varsa: yer değiştirme düzeltilir', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        KONAK CAFE
        DENIZ MAH. SOK 3
        TARIH 12.04.2026
        MATRAH 100,00
        TOPKDV 120,00
        TOPLAM 20,00
        NAKIT 120,00
      '''));
      // 20,00 aslında KDV; 120,00 aslında Toplam → otomatik düzeltilmeli.
      expect(r.toplamTutar, '120.00');
      expect(r.toplamKdv, '20.00');
    });

    test('KDV satırı yoksa matrah + toplamdan türetilir', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        MARKET DUKKAN
        ATATURK BULVARI NO 7
        TARIH 05.05.2026
        MATRAH 100,00
        TOPLAM 120,00
        NAKIT 120,00
      '''));
      expect(r.toplamTutar, '120.00');
      expect(r.toplamKdv, '20.00');
    });

    test('Toplam, KDV değerinden ASLA silinmez (toplam korunur)', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        BIM BIRLESIK MAGAZALAR
        YENI MAH.
        TARIH 09.06.2026
        TOPKDV 820,00
        TOPLAM 820,00
        NAKIT 820,00
      '''));
      // Klasik 820+820 hatası: Toplam korunmalı, KDV elle girilmek üzere sıfırlanmalı.
      expect(r.toplamTutar, '820.00');
      expect(r.toplamKdv, '');
    });
  });

  group('Tarih ve saat', () {
    test('nokta ayraçlı tarih ve saat', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        OPET AKARYAKIT
        SAHIL YOLU NO 1
        TARIH 15.05.2026 SAAT 09:45
        MOTORIN 20,00 LT
        TOPLAM 900,00
        KREDI KARTI 900,00
      '''));
      expect(r.tarih, '15.05.2026');
      expect(r.saat, '09:45');
    });
  });

  group('Vergi no (VKN) ve firma', () {
    test('VD etiketli satırdan 10 haneli VKN', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        MIGROS TICARET A.S.
        KADIKOY VD 1234567890
        TARIH 08.06.2026
        TOPLAM 125,75
        NAKIT 125,75
      '''));
      expect(r.vergiTcNo, '1234567890');
      expect(r.firmaAdi.toUpperCase(), contains('MIGROS'));
    });
  });

  group('TL sembolü "6" olarak okununca (₺→6) düzeltme', () {
    test('₺1.431,21 → 61.431,21 okundu, matrah+KDV ile düzeltilir', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        MARKET X TICARET A.S.
        ISTIKLAL CAD. NO 5
        TARIH 09.06.2026 SAAT 12:00
        MATRAH 1.373,94
        TOPKDV 57,27
        TOPLAM 61.431,21
        NAKIT 1.431,21
      '''));
      expect(r.toplamTutar, '1431.21');
      expect(r.toplamKdv, '57.27');
    });

    test('gerçek büyük tutar (61.431,21) YANLIŞLIKLA düzeltilmez', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        MARKET X TICARET A.S.
        ISTIKLAL CAD. NO 5
        TARIH 09.06.2026
        MATRAH 51.192,68
        TOPKDV 10.238,53
        TOPLAM 61.431,21
        NAKIT 61.431,21
      '''));
      expect(r.toplamTutar, '61431.21');
    });
  });

  group('KDV detayına Genel Toplam sızması', () {
    test('oran satırında fiyat yoksa alttaki TOPLAM satırı KDV sanılmaz', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        SOK MARKET
        CUMHURIYET MAH
        TARIH 09.06.2026
        KDV %20
        TOPLAM 1.431,21
        TOPKDV 57,27
        NAKIT 1.431,21
      '''));
      expect(r.toplamKdv, '57.27');
      expect(r.toplamTutar, '1431.21');
      expect(r.kdvDetay.every((i) => i.tutar != '1431.21'), isTrue);
    });

    test('KDV tutarı = Genel Toplam olan bozuk kalem temizlenir', () {
      final r = ReceiptParser.parseFromElements(_layout('''
        SOK MARKET
        CUMHURIYET MAH
        TARIH 09.06.2026
        %20 1.431,21
        TOPKDV 57,27
        TOPLAM 1.431,21
        NAKIT 1.431,21
      '''));
      expect(r.toplamKdv, '57.27');
      expect(r.kdvDetay.every((i) => i.tutar != '1431.21'), isTrue);
    });
  });

  group('Genel sağlamlık', () {
    test('boş giriş güvenli şekilde uyarı döner', () {
      final r = ReceiptParser.parseFromElements(const []);
      expect(r.toplamTutar, '');
      expect(r.uyari, isNotNull);
    });
  });
}
