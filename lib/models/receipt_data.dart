import 'kdv_item.dart';

class ReceiptData {
  // --- Firma Bilgileri ---
  String firmaAdi;
  String firmaAdresi;
  String vergiDairesi;
  String vergiTcNo; // 10 hane VKN veya 11 hane TC

  // --- Belge Bilgileri ---
  String belgeTuru; // "ÖKC FİŞİ" / "FATURA" / "SERBEST MESLEK"
  String fisNo;
  String seriNo;
  String zNo; // Günlük Z rapor no

  // --- Zaman ---
  String tarih;
  String saat;

  // --- Tutar Bilgileri ---
  List<KdvItem> kdvDetay; // Her KDV oranı ayrı ayrı
  String toplamKdv;
  String kdvHaricToplam; // Matrah
  String toplamTutar; // GENEL TOPLAM (KDV dahil)
  String odemeYontemi; // Nakit / Kredi Kartı / Banka Kartı
  String paraUstu;

  // --- Sınıflandırma ---
  String kategori;

  // --- Kalite ---
  Map<String, double> confidenceScores;
  String? uyari; // Kullanıcıya gösterilecek uyarı

  ReceiptData({
    this.firmaAdi = "",
    this.firmaAdresi = "",
    this.vergiDairesi = "",
    this.vergiTcNo = "",
    this.belgeTuru = "",
    this.fisNo = "",
    this.seriNo = "",
    this.zNo = "",
    this.tarih = "",
    this.saat = "",
    List<KdvItem>? kdvDetay,
    this.toplamKdv = "",
    this.kdvHaricToplam = "",
    this.toplamTutar = "",
    this.odemeYontemi = "",
    this.paraUstu = "",
    this.kategori = "Diğer",
    Map<String, double>? confidenceScores,
    this.uyari,
  }) : kdvDetay = kdvDetay ?? [],
       confidenceScores = confidenceScores ?? {};

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

  /// Toplam tutarı çift kontrol: KDV detaylarından hesapla
  bool get kdvTutarTutarliMi {
    if (toplamKdv.isEmpty || kdvDetay.isEmpty) return true;
    double detayToplam = kdvDetay.fold(0.0, (sum, item) {
      return sum + (double.tryParse(item.tutar) ?? 0.0);
    });
    double parsedKdv = double.tryParse(toplamKdv) ?? 0.0;
    return (detayToplam - parsedKdv).abs() < 0.05;
  }
}
