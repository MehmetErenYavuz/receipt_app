import 'kdv_item.dart';

class ReceiptData {
  // ── Firma Bilgileri ─────────────────────────────────────────────
  String firmaAdi;
  String firmaAdresi;
  String vergiDairesi;
  String vergiTcNo; // 10 hane = VKN, 11 hane = TC

  // ── Belge Bilgileri ─────────────────────────────────────────────
  String belgeTuru; // "ÖKC Fişi" / "e-Arşiv Fatura" / "Banka Pos Dekontu" vs.
  String fisNo;
  String seriNo;
  String zNo;

  // ── Zaman ───────────────────────────────────────────────────────
  String tarih;
  String saat;

  // ── Tutar Bilgileri ─────────────────────────────────────────────
  List<KdvItem> kdvDetay;
  String toplamKdv;
  String kdvHaricToplam; // Matrah
  String toplamTutar;
  String odemeYontemi;
  String paraUstu;

  // ── Sınıflandırma ve Medya ──────────────────────────────────────
  String kategori;
  String? imagePath; // YENİ: Fotoğrafın telefondaki konumu

  // ── Kalite ──────────────────────────────────────────────────────
  Map<String, double> confidenceScores;
  String? uyari;

  ReceiptData({
    this.firmaAdi = '',
    this.firmaAdresi = '',
    this.vergiDairesi = '',
    this.vergiTcNo = '',
    this.belgeTuru = '',
    this.fisNo = '',
    this.seriNo = '',
    this.zNo = '',
    this.tarih = '',
    this.saat = '',
    List<KdvItem>? kdvDetay,
    this.toplamKdv = '',
    this.kdvHaricToplam = '',
    this.toplamTutar = '',
    this.odemeYontemi = '',
    this.paraUstu = '',
    this.kategori = 'Diğer',
    this.imagePath,
    Map<String, double>? confidenceScores,
    this.uyari,
  }) : kdvDetay = kdvDetay ?? [],
       confidenceScores = confidenceScores ?? {};

  // ── Hesaplanan Özellikler ────────────────────────────────────────

  double get averageConfidence {
    if (confidenceScores.isEmpty) return 0.0;
    final double sum = confidenceScores.values.fold(
      0.0,
      (double a, double b) => a + b,
    );
    return sum / confidenceScores.length;
  }

  bool get isHighConfidence => averageConfidence >= 0.75;

  bool get hasCriticalFields =>
      toplamTutar.isNotEmpty && (tarih.isNotEmpty || fisNo.isNotEmpty);

  /// VKN mi TC mi?
  String get kimlikTuru {
    if (vergiTcNo.isEmpty) return '';
    return vergiTcNo.length == 11 ? 'TC Kimlik No' : 'Vergi No (VKN)';
  }

  /// KDV + TOPLAM tutarlılık kontrolü
  bool get kdvVeToplamTutarli {
    if (toplamKdv.isEmpty || toplamTutar.isEmpty) return true;
    final kdv = double.tryParse(toplamKdv) ?? -1;
    final top = double.tryParse(toplamTutar) ?? -1;
    if (kdv < 0 || top < 0) return true;
    // KDV, TOPLAM'dan küçük olmalı
    return kdv < top;
  }

  /// Detay KDV toplamı ile TOPKDV çakışıyor mu?
  bool get kdvDetayTutarli {
    if (toplamKdv.isEmpty || kdvDetay.isEmpty) return true;
    double detayToplam = kdvDetay.fold(0.0, (sum, item) {
      return sum + (double.tryParse(item.tutar) ?? 0.0);
    });
    final parsedKdv = double.tryParse(toplamKdv) ?? 0.0;
    return (detayToplam - parsedKdv).abs() < 0.10; // 10 kuruş tolerans
  }
}
