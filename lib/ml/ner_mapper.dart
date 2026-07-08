// ═══════════════════════════════════════════════════════════════════════
// §5.2 NerResult → ReceiptData map'i (NER birincil, regex tabanı korur)
// ═══════════════════════════════════════════════════════════════════════
// base = regex ReceiptParser çıktısı: NER'in HİÇ modellemediği zengin alanları
// (kategori, adres, yakıt, telefon, seri/zNo/eku, paraBirimi, araToplam, iban,
// ettn) KORUR. NER'in ürettiği çekirdek muhasebe alanları base ÜZERİNE yazılır.
//
// postprocess zaten içeride regex-rescue yaptığı için (NER boş alan → regex
// değeri), buradaki NER alanları gerektiğinde regex değerini taşır; bu katman
// ek olarak yalnız NER'in kapsamadığı alanları base'den geçirir.
//
// Ham §5.2 JSON `nerJson`'a yazılır (saha verisi + Python paritesi).
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';

import '../models/kdv_item.dart';
import '../models/receipt_data.dart';
import 'ner_result.dart';

ReceiptData mapNerToReceipt(NerResult ner, {required ReceiptData base}) {
  // ── tarih: ISO ise dd.mm.yyyy'ye çevir; ham (parse edilememiş) ise base KORU ──
  final nerDateRaw = ner.date?.value as String?;
  String tarih = base.tarih;
  if (nerDateRaw != null) {
    final tr = _isoToTr(nerDateRaw);
    if (tr != null) tarih = tr; // ham ISO-dışı değer base.tarih'i ezmez (regresyon önleme)
  }

  // ── KDV detayı: NER oran/matrah/tutar varsa onları kullan, yoksa base KORU ──
  List<KdvItem> kdvDetay = base.kdvDetay;
  final vat = ner.vat;
  if (vat != null && vat.vat.isNotEmpty) {
    final rates = vat.vat.keys.toList()..sort();
    kdvDetay = [
      for (final r in rates)
        KdvItem(
          oran: '%$r',
          matrah: _money(vat.base[r]),
          tutar: _money(vat.vat[r]),
        ),
    ];
  }

  // ── ödeme yöntemi: NER card/cash bacağından türet, yoksa base KORU ──
  final hasCard = ner.cardPaid != null;
  final hasCash = ner.cashPaid != null;
  String odeme = base.odemeYontemi;
  if (hasCard && hasCash) {
    odeme = 'Kredi Kartı + Nakit';
  } else if (hasCard) {
    odeme = 'Kredi Kartı';
  } else if (hasCash) {
    odeme = 'Nakit';
  }

  // ── güven skorları: regex tabanın üstüne NER alan güvenleri ──
  final scores = <String, double>{...base.confidenceScores};
  if (ner.vendorName != null) scores['firma'] = ner.vendorName!.confidence;
  if (ner.taxId != null) scores['vergi'] = ner.taxId!.confidence;
  if (ner.date != null) scores['tarih'] = ner.date!.confidence;
  if (ner.time != null) scores['saat'] = ner.time!.confidence;
  if (ner.vat?.vatTotal != null) scores['kdv'] = 0.80;
  if (ner.total != null) scores['toplam'] = ner.total!.confidence;
  if (ner.docNo != null) scores['fisNo'] = ner.docNo!.confidence;

  // ── uyarılar: regex uyarısı + NER warnings (truncation/mismatch) ──
  final parts = <String>[];
  if (base.uyari != null && base.uyari!.trim().isNotEmpty) parts.add(base.uyari!);
  parts.addAll(ner.warnings);
  final uyari = parts.isEmpty ? null : parts.join('\n');

  return base.copyWith(
    firmaAdi: _str(ner.vendorName?.value) ?? base.firmaAdi,
    vergiTcNo: ner.taxId?.value ?? base.vergiTcNo,
    vergiDairesi: _str(ner.taxOffice?.value) ?? base.vergiDairesi,
    tarih: tarih,
    saat: _str(ner.time?.value) ?? base.saat,
    fisNo: _str(ner.docNo?.value) ?? base.fisNo,
    toplamTutar: _money(ner.total?.value as double?, fallback: base.toplamTutar),
    toplamKdv: _money(ner.vat?.vatTotal, fallback: base.toplamKdv),
    kdvHaricToplam:
        _money(ner.subtotal?.value as double?, fallback: base.kdvHaricToplam),
    kdvDetay: kdvDetay,
    odemeYontemi: odeme,
    mersisNo: ner.mersisNo?.value ?? base.mersisNo,
    confidenceScores: scores,
    uyari: uyari,
    nerJson: jsonEncode(ner.toJson()),
  );
}

// ── yardımcılar ──────────────────────────────────────────────────────────

/// "YYYY-MM-DD" → "dd.mm.yyyy"; ISO değilse null (base.tarih korunsun).
String? _isoToTr(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  return '${m.group(3)}.${m.group(2)}.${m.group(1)}';
}

/// double para → "0.00" string; null ise [fallback] (varsa) ya da ''.
String _money(double? v, {String fallback = ''}) =>
    v != null ? v.toStringAsFixed(2) : fallback;

/// Boş/null string'i null'a indirger (copyWith'te base'i ezmesin diye).
String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
