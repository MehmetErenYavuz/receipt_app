// ═══════════════════════════════════════════════════════════════════════
// REGEX KURTARMA HAVUZU KÖPRÜSÜ — postprocess_logic.md NER-öncelik kuralı
// ═══════════════════════════════════════════════════════════════════════
// Olgun `ReceiptParser` çıktısı (ReceiptData) → postprocess'in beklediği
// `regex` aday havuzu {LABEL: [aday, ...]}. Bu havuz YALNIZ NER boşken
// doldurur (NER'i EZMEZ — postprocess §0). Değerler zaten normalize edilmiş
// ("700.00", "08.11.2025") → parse_money/parse_date doğrudan kabul eder.
//
// VENDOR_NAME / TAX_OFFICE haritalanmaz: postprocess bu alanlarda regex
// kurtarma kullanmaz (sözleşme öncelik tablosu — NER yalnız).
// ═══════════════════════════════════════════════════════════════════════

import '../models/receipt_data.dart';

class NerRegexPool {
  static Map<String, List<String>> fromReceiptData(ReceiptData r) {
    final pool = <String, List<String>>{};
    void add(String key, String? val) {
      if (val != null && val.trim().isNotEmpty) {
        (pool[key] ??= <String>[]).add(val.trim());
      }
    }

    add('TOTAL', r.toplamTutar);
    add('TAX_ID', r.vergiTcNo);
    add('DATE', r.tarih);
    add('TIME', r.saat);
    add('DOC_NO', r.fisNo); // e-arşiv doc no'su da _fisNo'da yakalanır
    add('MERSIS_NO', r.mersisNo);
    add('VAT_TOTAL', r.toplamKdv);
    add('SUBTOTAL', r.kdvHaricToplam);

    // Oran-bazlı KDV tutarları (yalnız 1/10/20; 8/18 inference yolunda ele alınır).
    for (final item in r.kdvDetay) {
      final oran = item.oran.replaceAll(RegExp(r'[^0-9]'), '');
      if (oran == '1' || oran == '10' || oran == '20') {
        add('VAT_$oran', item.tutar);
      }
    }

    // Ödeme bacağı kurtarma: parser ödeme satırlarından gerçek nakit/kart
    // tutarını çıkardıysa onu kullan (parçalı ödeme dahil). Yoksa ödeme
    // yöntemi etiketinden tek bacak = toplam tahmini (kaba geri-düşüş).
    final hasReal = r.nakitTutar.trim().isNotEmpty || r.kartTutar.trim().isNotEmpty;
    if (hasReal) {
      add('CASH_PAID', r.nakitTutar);
      add('CARD_PAID', r.kartTutar);
    } else if (r.toplamTutar.trim().isNotEmpty) {
      final odeme = r.odemeYontemi.toUpperCase();
      if (odeme.contains('NAKİT') || odeme.contains('NAKIT')) {
        add('CASH_PAID', r.toplamTutar);
      } else if (odeme.contains('KART') ||
          odeme.contains('KREDİ') ||
          odeme.contains('KREDI') ||
          odeme.contains('BANKA') ||
          odeme.contains('TEMASSIZ')) {
        add('CARD_PAID', r.toplamTutar);
      }
    }

    return pool;
  }
}
