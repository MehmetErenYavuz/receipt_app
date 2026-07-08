// ═══════════════════════════════════════════════════════════════════════
// RECEIPT PARSER — GERÇEK TÜRK FİŞ/FATURA YAPILARI (uçtan uca)
// ═══════════════════════════════════════════════════════════════════════
// Yaygın Türk belge biçimlerinin (ÖKC market fişi, e-Arşiv fatura, yakıt
// fişi) doğru ayrıştırıldığını ve her değerin KENDİ alanına yazıldığını
// doğrular. Özellikle KDV ↔ Genel Toplam izolasyonunu gerçekçi verilerle
// test eder.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
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
  test('ÖKC market fişi — TOPKDV ve TOPLAM ayrı kalır', () {
    final r = ReceiptParser.parseFromElements(_layout('''
      A101 YENI MAGAZACILIK A.S.
      KARTAL SUBESI
      TARIH: 09/06/2026 SAAT: 14:23
      COLA %20 30,00
      EKMEK %1 5,00
      ARA TOPLAM 35,00
      TOPKDV 5,05
      TOPLAM 40,05
      KREDI KARTI 40,05
    '''));
    expect(r.toplamTutar, '40.05');
    expect(r.toplamKdv, '5.05');
    expect(r.tarih, '09.06.2026');
    expect(r.saat, '14:23');
    expect(r.odemeYontemi, 'Kredi Kartı');
  });

  test('e-Arşiv fatura — VERGİLER DAHİL TOPLAM toplamdır, HESAPLANAN KDV ise KDV', () {
    final r = ReceiptParser.parseFromElements(_layout('''
      ABC BILISIM TICARET LTD STI
      MERKEZ MAH ATATURK CAD NO 10
      VERGI NO 1234567890
      E-ARSIV FATURA
      TARIH 09.06.2026
      MAL HIZMET TOPLAM 1.000,00
      HESAPLANAN KDV 200,00
      VERGILER DAHIL TOPLAM 1.200,00
      KREDI KARTI 1.200,00
    '''));
    expect(r.toplamTutar, '1200.00');
    expect(r.toplamKdv, '200.00');
    expect(r.vergiTcNo, '1234567890');
    expect(r.belgeTuru.toLowerCase(), contains('arşiv'));
  });

  test('Yakıt fişi — KDV dahil fiyatta KDV/Toplam karışmaz', () {
    final r = ReceiptParser.parseFromElements(_layout('''
      SHELL PETROL DAGITIM A.S.
      TARIH 09.06.2026 SAAT 08:15
      MOTORIN 25,50 LT
      POMPA NO 3
      ARA TOPLAM 1.000,00
      TOPKDV 166,67
      TOPLAM 1.000,00
      KREDI KARTI 1.000,00
    '''));
    expect(r.toplamTutar, '1000.00');
    expect(r.toplamKdv, '166.67');
    expect(r.yakitTuru, 'Motorin');
    expect(r.kategori, 'Yakıt');
  });

  test('Restoran fişi — yıldızlı (*) KDV formatı', () {
    final r = ReceiptParser.parseFromElements(_layout('''
      KOFTECI YUSUF
      TARIH 09.06.2026 SAAT 20:10
      IZGARA KOFTE 250,00
      ARA TOPLAM 250,00
      TOPKDV *25,00
      TOPLAM *275,00
      NAKIT *275,00
    '''));
    expect(r.toplamTutar, '275.00');
    expect(r.toplamKdv, '25.00');
  });
}
