import 'kdv_item.dart';

class ReceiptData {
  int? id; // Güncelleme işlemleri için ID (Lokal DB)
  bool isApproved; // Onay durumu (Lokal DB'de tutulacak)

  // ── Firma Bilgileri ──
  String firmaAdi;
  String firmaAdresi;
  String vergiDairesi;
  String vergiTcNo;

  // ── Belge Bilgileri ──
  String belgeTuru;
  String fisNo;
  String seriNo;
  String zNo;
  String ekuNo;
  String ettn;
  String mersisNo;
  String iban;

  // ── Zaman ──
  String tarih;
  String saat;

  // ── Tutar Bilgileri ──
  List<KdvItem> kdvDetay;
  String toplamKdv;
  String kdvHaricToplam;
  String araToplam;
  String toplamTutar;
  String odemeYontemi;
  String paraUstu;
  String paraBirimi;

  // ── Ödeme bacağı tutarları (in-memory; DB'ye yazılmaz) ──
  // NER rescue havuzu (CARD_PAID/CASH_PAID) + ₺→6 teyidi için parser doldurur.
  String nakitTutar;
  String kartTutar;

  // ── Yakıt Fişi Özel Alanları ──
  String? yakitTuru;
  String? yakitLitre;
  String? pompaNo;
  String? aracPlakasi;

  // ── İletişim ──
  String? telefon;

  // ── Sınıflandırma ve Medya ──
  String kategori;
  String? imagePath;

  // ── Kalite ──
  Map<String, double> confidenceScores;
  String? uyari;

  // ── NER (on-device model) ──
  /// §5.2 ham NER çıktısı (output_contract.md şeması, JSON string). Saha verisi
  /// toplama + arkadaşın Python çıktısıyla parite kıyası için saklanır. NER
  /// çalışmadıysa (model yok / fallback) null.
  String? nerJson;

  ReceiptData({
    this.id,
    this.isApproved = false, // Varsayılan olarak onay bekliyor
    this.firmaAdi = '',
    this.firmaAdresi = '',
    this.vergiDairesi = '',
    this.vergiTcNo = '',
    this.belgeTuru = '',
    this.fisNo = '',
    this.seriNo = '',
    this.zNo = '',
    this.ekuNo = '',
    this.ettn = '',
    this.mersisNo = '',
    this.iban = '',
    this.tarih = '',
    this.saat = '',
    List<KdvItem>? kdvDetay,
    this.toplamKdv = '',
    this.kdvHaricToplam = '',
    this.araToplam = '',
    this.toplamTutar = '',
    this.odemeYontemi = '',
    this.paraUstu = '',
    this.paraBirimi = 'TL',
    this.nakitTutar = '',
    this.kartTutar = '',
    this.yakitTuru,
    this.yakitLitre,
    this.pompaNo,
    this.aracPlakasi,
    this.telefon,
    this.kategori = 'Diğer',
    this.imagePath,
    Map<String, double>? confidenceScores,
    this.uyari,
    this.nerJson,
  }) : kdvDetay = kdvDetay ?? [],
       confidenceScores = confidenceScores ?? {};

  // ── Clean Code Standardı: CopyWith Metodu ────────────────────────
  // UI güncellemelerinde objenin referansını değiştirmeden sadece
  // istediğimiz alanları güncellememizi sağlar.
  ReceiptData copyWith({
    int? id,
    bool? isApproved,
    String? firmaAdi,
    String? firmaAdresi,
    String? vergiDairesi,
    String? vergiTcNo,
    String? belgeTuru,
    String? fisNo,
    String? seriNo,
    String? zNo,
    String? ekuNo,
    String? ettn,
    String? mersisNo,
    String? iban,
    String? tarih,
    String? saat,
    List<KdvItem>? kdvDetay,
    String? toplamKdv,
    String? kdvHaricToplam,
    String? araToplam,
    String? toplamTutar,
    String? odemeYontemi,
    String? paraUstu,
    String? paraBirimi,
    String? nakitTutar,
    String? kartTutar,
    String? yakitTuru,
    String? yakitLitre,
    String? pompaNo,
    String? aracPlakasi,
    String? telefon,
    String? kategori,
    String? imagePath,
    Map<String, double>? confidenceScores,
    String? uyari,
    String? nerJson,
  }) {
    return ReceiptData(
      id: id ?? this.id,
      isApproved: isApproved ?? this.isApproved,
      firmaAdi: firmaAdi ?? this.firmaAdi,
      firmaAdresi: firmaAdresi ?? this.firmaAdresi,
      vergiDairesi: vergiDairesi ?? this.vergiDairesi,
      vergiTcNo: vergiTcNo ?? this.vergiTcNo,
      belgeTuru: belgeTuru ?? this.belgeTuru,
      fisNo: fisNo ?? this.fisNo,
      seriNo: seriNo ?? this.seriNo,
      zNo: zNo ?? this.zNo,
      ekuNo: ekuNo ?? this.ekuNo,
      ettn: ettn ?? this.ettn,
      mersisNo: mersisNo ?? this.mersisNo,
      iban: iban ?? this.iban,
      tarih: tarih ?? this.tarih,
      saat: saat ?? this.saat,
      kdvDetay: kdvDetay ?? this.kdvDetay,
      toplamKdv: toplamKdv ?? this.toplamKdv,
      kdvHaricToplam: kdvHaricToplam ?? this.kdvHaricToplam,
      araToplam: araToplam ?? this.araToplam,
      toplamTutar: toplamTutar ?? this.toplamTutar,
      odemeYontemi: odemeYontemi ?? this.odemeYontemi,
      paraUstu: paraUstu ?? this.paraUstu,
      paraBirimi: paraBirimi ?? this.paraBirimi,
      nakitTutar: nakitTutar ?? this.nakitTutar,
      kartTutar: kartTutar ?? this.kartTutar,
      yakitTuru: yakitTuru ?? this.yakitTuru,
      yakitLitre: yakitLitre ?? this.yakitLitre,
      pompaNo: pompaNo ?? this.pompaNo,
      aracPlakasi: aracPlakasi ?? this.aracPlakasi,
      telefon: telefon ?? this.telefon,
      kategori: kategori ?? this.kategori,
      imagePath: imagePath ?? this.imagePath,
      confidenceScores: confidenceScores ?? this.confidenceScores,
      uyari: uyari ?? this.uyari,
      nerJson: nerJson ?? this.nerJson,
    );
  }

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

  /// Yakıt fişi mi?
  bool get isYakitFisi => yakitTuru != null && yakitTuru!.isNotEmpty;

  /// e-Arşiv fatura mı?
  bool get isEArsiv => belgeTuru.contains('e-Arşiv') || ettn.isNotEmpty;
}
