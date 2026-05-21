import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
// Kendi proje adına göre ayarladığımız garanti import yolları:
import 'package:receipt_app/models/receipt_data.dart';
import 'package:receipt_app/models/kdv_item.dart';
import 'package:receipt_app/extensions/string_extensions.dart'; // ── EKLENTİ BURADA ──

// ═══════════════════════════════════════════════════════════════════════
// YARDIMCI: Koordinat Tabanlı Satır
// ═══════════════════════════════════════════════════════════════════════
class _Row {
  double yCenter;
  final List<TextElement> elements;

  _Row(this.yCenter, this.elements);

  // ── Standart temizlik (kamera/galeri fişleri için yeterli) ──
  String get text {
    final raw = elements.map((e) => e.text).join(' ');
    String cleaned = raw.fixOcrConfusion;

    // Eğer satırda rakam varsa (yani fiyat ihtimali yüksekse)
    // ek olarak fiyat bağlamı temizliği uygula
    if (RegExp(r'\d').hasMatch(cleaned)) {
      cleaned = cleaned.fixPriceContext;
    }

    return cleaned;
  }

  String get upper => text.toUpperCase();

  // ── YENİ: BURUŞUK FİŞ İÇİN AGRESİF TEMİZLENMİŞ VERSİYON ──
  // Sadece zor durumlarda fallback olarak kullanılır.
  // Daha fazla düzeltme yapar ama yanlış pozitif riski biraz yüksek.
  String get textAggressive {
    final raw = elements.map((e) => e.text).join(' ');
    return raw.crumpledOcrClean;
  }

  String get upperAggressive => textAggressive.toUpperCase();

  List<String> allPrices(RegExp reg) =>
      reg.allMatches(text).map((m) => m.group(0)!).toList();

  // YENİ: Buruşuk için agresif fiyat listesi
  List<String> allPricesAggressive(RegExp reg) =>
      reg.allMatches(textAggressive).map((m) => m.group(0)!).toList();

  String? rightmostPrice(RegExp reg) {
    for (int i = elements.length - 1; i >= 0; i--) {
      final cleaned = _ocrClean(elements[i].text.fixOcrConfusion);
      if (reg.hasMatch(cleaned)) return cleaned;
    }
    final cleaned = _ocrClean(text);
    final all = reg.allMatches(cleaned).map((m) => m.group(0)!).toList();
    return all.isNotEmpty ? all.last : null;
  }
}

class _Field {
  final String value;
  final double confidence;

  const _Field(this.value, this.confidence);
  static const _Field empty = _Field('', 0.0);
  bool get found => value.isNotEmpty;
}

// ═══════════════════════════════════════════════════════════════════════
// GLOBAL OCR DÜZELTME FONKSİYONU — GÜÇLENDİRİLMİŞ (Buruşuk için)
// ═══════════════════════════════════════════════════════════════════════
String _ocrClean(String raw) {
  String s = raw;

  // ─── KATMAN 1: Klasik fiyat bağlamı düzeltmesi ───
  s = s.replaceAllMapped(
    RegExp(r'\d[OoIlBSGZqQ.,]\d|\d[OoIlBSGZqQ]\d{2}[.,]'),
    (m) {
      String match = m.group(0)!;
      return match
          .replaceAll('O', '0')
          .replaceAll('o', '0')
          .replaceAll('I', '1')
          .replaceAll('l', '1')
          .replaceAll('B', '8')
          .replaceAll('S', '5')
          .replaceAll('G', '6')
          .replaceAll('Z', '2')
          .replaceAll('q', '9')
          .replaceAll('Q', '0');
    },
  );

  // ─── YENİ KATMAN 2: Buruşuk için ek karakter düzeltmeleri ───
  // Sayı bloklarındaki karışıklıkları daha geniş kapsamla yakala
  // "1l9,4O" → "119,40", "12O,5O" → "120,50"
  for (int i = 0; i < 2; i++) {
    s = s.replaceAllMapped(RegExp(r'(\d)([OoIlBSGZqQ])(\d)'), (m) {
      final letter = m[2]!;
      final digit = const {
            'O': '0',
            'o': '0',
            'Q': '0',
            'I': '1',
            'l': '1',
            'B': '8',
            'S': '5',
            'G': '6',
            'Z': '2',
            'q': '9',
          }[letter] ??
          letter;
      return '${m[1]}$digit${m[3]}';
    });
  }

  // ─── YENİ KATMAN 3: Boşluk-virgül karışıklığı ───
  // Buruşuk fişlerde virgül kaybolur ve "119 40 TL" gibi gelir
  s = s.replaceAllMapped(
    RegExp(r'(\d{1,4})\s+(\d{2})(?=\s*(?:TL|₺|$|\n))', caseSensitive: false),
    (m) => '${m[1]},${m[2]}',
  );

  // ─── YENİ KATMAN 4: Nokta-virgül normalize (Türk standardı) ───
  // "119.40" → "119,40" (sadece ondalık konumda)
  s = s.replaceAllMapped(
    RegExp(r'(\d{1,4})\.(\d{2})(?!\d)'),
    (m) => '${m[1]},${m[2]}',
  );

  return s;
}

String _cleanRow(String raw) {
  return _ocrClean(raw);
}

// ═══════════════════════════════════════════════════════════════════════
// ANA PARSER (TÜRKİYE ÖKC, E-ARŞİV, YEMEK KARTI, AKARYAKIT, İPTAL UYUMLU)
// + BURUŞUK FİŞ DESTEĞİ
// ═══════════════════════════════════════════════════════════════════════
class ReceiptParser {
  static const List<String> _totalKw = [
    'TOPLAM',
    'GENEL TOPLAM',
    'G.TOPLAM',
    'GENEL TOP',
    'TOP',
    'TOPTUTAR',
    'SATIS TOP',
    'SATISTOPLAM',
    'ODENEN',
    'ÖDENECEK',
    'ÖDENENTOP',
    'ODENECEK TUTAR',
    'TAHSIL',
    'TAHSİL',
    'ODENECEK KDV DAHIL TUTAR',
    'TUTAR',
    'TOPLAM TUTAR',
    'Toplam Tutar',
  ];

  // ── YENİ: BURUŞUK FİŞLER İÇİN TOPLAM ANAHTAR KELİME VARYANTLARI ──
  // OCR'da kelimenin parçalandığı veya bozulduğu durumlar için
  static const List<String> _totalKwLoose = [
    'TOPLA', // TOPLAM'ın son harfi gitmiş
    'OPLAM', // İlk harfi gitmiş
    'TPLAM', // Bir harf eksik
    'TOLAM', // Bir harf eksik
    'TOPM', // Birden fazla harf eksik
    'TOPL',
    'OPLA',
    'ENEL TOP', // GENEL TOP
    'G TOP',
    'GTOP',
    'GNL TOP',
    'EDENEK', // ÖDENECEK
    'DENECEK',
    'ODENEN',
    'ODENECEK',
    'TAHS', // TAHSİL parçalanmış
  ];

  static const List<String> _kdvKw = [
    'TOPKDV',
    'TOP KDV',
    'TOPLAM KDV',
    'KDV TOPLAM',
    'K.D.V',
    'K.D.V.',
    'KDV',
    'KATMA DEGER',
    'KATMA DEĞER',
    'TOPLAM KDV TUTARI',
    'Toplam KDV',
    'KDV TUTARI',
  ];

  static const List<String> _paymentKw = [
    'NAKİT',
    'NAKIT',
    'KREDİ KARTI',
    'KREDI KARTI',
    'BANKA/KREDİ KARTI',
    'BANKA/KREDI KARTI',
    'BANKA KARTI',
    'TEMASSIZ',
    'TEMASSIZ KART',
    'TEMASSIZ İŞLEM',
    'MULTINET',
    'MULTİNET',
    'SODEXO',
    'PLUXEE',
    'TICKET',
    'TİCKET',
    'EDENRED',
    'SETCARD',
    'METROPOL',
    'PAYE',
    'TOKENFLEX',
    'YEMEK KARTI',
    'YEMEK CEKI',
    'YEMEK ÇEKİ',
    'HEDİYE ÇEKİ',
    'HEDIYE CEKI',
    'EFT',
    'EFT-POS',
    'HAVALE',
    'FAST',
    'KART',
  ];

  // ── YENİ: İNDİRİM, PUAN, ETTN ve DİĞER VERİ ÇÖPLERİ EKLENDİ ──
  static const List<String> _skipKw = [
    'T.C.',
    'www.',
    'http',
    'MALİ DEĞER',
    'MALI DEGER',
    'MALİ SEMBOL',
    'EKÜ',
    'EKU',
    'TESEKKUR',
    'TEŞEKKÜR',
    'SADECE TEMASSIZ',
    'BU BELGEYİ',
    'BU BELGEYI',
    'TUTAR KARSILIGI',
    'TUTAR KARŞILIĞI',
    'MUSTERI NUSHASI',
    'MÜŞTERİ NÜSHASI',
    'KART HAMİLİ',
    'KART HAMILI',
    'İŞLEMİNİZ ONAYLANDI',
    'ISLEMINIZ ONAYLANDI',
    'BANKA REFERANS',
    'ONAY KODU',
    'ACQUIRER ID',
    'YİNE BEKLERİZ',
    'YINE BEKLERIZ',
    'AFİYET OLSUN',
    'AFIYET OLSUN',
    'İYİ GÜNLER',
    'IYI GUNLER',
    'HOŞGELDİNİZ',
    'HOSGELDINIZ',
    'MÜŞTERİ',
    'MUSTERI',
    'LÜTFEN',
    'LUTFEN',
    'BİLGİ FİŞİ',
    'BILGI FISI',
    'MERSİS',
    'MERSIS',
    'IBAN',
    'TR',
    'İNDİRİM',
    'INDIRIM',
    'PUAN',
    'MONEY',
    'KAZANCINIZ',
    'ETTN',
  ];

  static const Map<String, String> _belgeKw = {
    'E-ARSIV FATURA': 'e-Arşiv Fatura',
    'E-ARŞİV FATURA': 'e-Arşiv Fatura',
    'E-FATURA': 'e-Fatura',
    'FATURA': 'Fatura',
    'SERBEST MESLEK': 'Serbest Meslek Makbuzu',
    'PERAKENDE SATIS': 'Perakende Satış Fişi',
    'YAZAR KASA': 'ÖKC Fişi',
    'ÖKC FİŞİ': 'ÖKC Fişi',
  };

  static const Map<String, String> _kategoriMap = {
    'MİGROS': 'Market',
    'MIGROS': 'Market',
    'BİM': 'Market',
    'BIM': 'Market',
    'A101': 'Market',
    'A 101': 'Market',
    'ŞOK': 'Market',
    'SOK': 'Market',
    'CARREFOUR': 'Market',
    'FILE': 'Market',
    'FİLE': 'Market',
    'METRO MARKET': 'Market',
    'MAKRO': 'Market',
    'HAKMAR': 'Market',
    'ÖZDILEK': 'Market',
    'GRATIS': 'Market',
    'WATSONS': 'Market',
    'SHELL': 'Yakıt',
    'OPET': 'Yakıt',
    'BP': 'Yakıt',
    'TOTAL': 'Yakıt',
    'LUKOIL': 'Yakıt',
    'PETROL': 'Yakıt',
    'AKARYAKIT': 'Yakıt',
    'MOİL': 'Yakıt',
    'MOIL': 'Yakıt',
    'AUTOPAS': 'Yakıt',
    'ALTINPA': 'Yakıt',
    'MCDONALDS': 'Yeme-İçme',
    'MCDONALD': 'Yeme-İçme',
    'BURGER': 'Yeme-İçme',
    'PIZZA': 'Yeme-İçme',
    'RESTORAN': 'Yeme-İçme',
    'RESTAURANT': 'Yeme-İçme',
    'CAFE': 'Yeme-İçme',
    'KAFETERYA': 'Yeme-İçme',
    'KAHVE': 'Yeme-İçme',
    'COFFEE': 'Yeme-İçme',
    'KUNEFE': 'Yeme-İçme',
    'DÖNER': 'Yeme-İçme',
    'PIDE': 'Yeme-İçme',
    'KEBAP': 'Yeme-İçme',
    'LOKANTA': 'Yeme-İçme',
    'STARBUCKS': 'Yeme-İçme',
    'KONAK CAFE': 'Yeme-İçme',
    'FERROVIA': 'Yeme-İçme',
    'EKREM COSKUN': 'Yeme-İçme',
    'MACKBEAR': 'Yeme-İçme',
    'PEK DÖNER': 'Yeme-İçme',
    'CAFFE DI': 'Yeme-İçme',
    'MIDYECI': 'Yeme-İçme',
    'ANADOLU REST': 'Yeme-İçme',
    'HACIZADE': 'Yeme-İçme',
    'KÖFTECİ YUSUF': 'Yeme-İçme',
    'ECZANE': 'Sağlık',
    'PHARMACY': 'Sağlık',
    'HASTANE': 'Sağlık',
    'KLİNİK': 'Sağlık',
    'TEKNOSA': 'Elektronik',
    'MEDIAMARKT': 'Elektronik',
    'VATAN': 'Elektronik',
    'TURKCELL': 'Elektronik',
    'TÜRK TELEKOM': 'Elektronik',
    'VODAFONE': 'Elektronik',
    'LC WAIKIKI': 'Giyim',
    'LCWAIKIKI': 'Giyim',
    'ZARA': 'Giyim',
    'H&M': 'Giyim',
    'MANGO': 'Giyim',
    'KOTON': 'Giyim',
    'DEFACTO': 'Giyim',
    'NINE WEST': 'Giyim',
    'MAVİ': 'Giyim',
    'BOYNER': 'Giyim',
    'TAXI': 'Ulaşım',
    'TAKSİ': 'Ulaşım',
    'OTOPARK': 'Ulaşım',
    'SIPAY': 'Ulaşım',
    'TCDD': 'Ulaşım',
    'İDO': 'Ulaşım',
    'IDO': 'Ulaşım',
    'BUDO': 'Ulaşım',
    'HAVAS': 'Ulaşım',
    'HAVAİST': 'Ulaşım',
    'HAVAIST': 'Ulaşım',
    'METRO': 'Ulaşım',
    'BİTAKSİ': 'Ulaşım',
    'BITAKSI': 'Ulaşım',
    'UBER': 'Ulaşım',
    'MARTI': 'Ulaşım',
    'MARTİ': 'Ulaşım',
    // ── Ek market markaları ──
    'TARIM KREDI': 'Market',
    'TARIM KREDİ': 'Market',
    'SEÇ': 'Market',
    'SEC MARKET': 'Market',
    'HAPPY': 'Market',
    'KIM': 'Market',
    'KIM MARKET': 'Market',
    'EKO MARKET': 'Market',
    'ONUR MARKET': 'Market',
    'BİZİM': 'Market',
    'BIZIM': 'Market',
    'YUNUS MARKET': 'Market',
    'KILER': 'Market',
    'KİLER': 'Market',
    // ── Ek yakıt ──
    'TURKUVAZ': 'Yakıt',
    'AYTEMİZ': 'Yakıt',
    'AYTEMIZ': 'Yakıt',
    'TP AKARYAKIT': 'Yakıt',
    'PETROL OFISI': 'Yakıt',
    'PETROL OFİSİ': 'Yakıt',
    'POAS': 'Yakıt',
    // ── Ek yeme-içme ──
    'POPEYES': 'Yeme-İçme',
    'KFC': 'Yeme-İçme',
    'DOMINOS': 'Yeme-İçme',
    'DOMİNOS': 'Yeme-İçme',
    'SUBWAY': 'Yeme-İçme',
    'SIMIT SARAYI': 'Yeme-İçme',
    'SİMİT SARAYI': 'Yeme-İçme',
    'KAHVE DUNYASI': 'Yeme-İçme',
    'KAHVE DÜNYASI': 'Yeme-İçme',
    'GLORIA JEANS': 'Yeme-İçme',
    "PAUL'S": 'Yeme-İçme',
    'TATCAFE': 'Yeme-İçme',
    'EATALY': 'Yeme-İçme',
    'BIG CHEFS': 'Yeme-İçme',
    'GUNAYDIN': 'Yeme-İçme',
    'GÜNAYDIN': 'Yeme-İçme',
    'NUSR-ET': 'Yeme-İçme',
    'NUSRET': 'Yeme-İçme',
    // ── Ek sağlık/eczane ──
    'ECZ.': 'Sağlık',
    'MEDİKAL': 'Sağlık',
    'MEDIKAL': 'Sağlık',
    'POLİKLİNİK': 'Sağlık',
    'POLIKLINIK': 'Sağlık',
    'LABORATUVAR': 'Sağlık',
    // ── Ek elektronik ──
    'BIM TEKNO': 'Elektronik',
    'GOLD BILGISAYAR': 'Elektronik',
    'GOLD BİLGİSAYAR': 'Elektronik',
    'TURKCELL ILETISIM': 'Elektronik',
    'TÜRKCELL İLETİŞİM': 'Elektronik',
    // ── Ek giyim ──
    'COLINS': 'Giyim',
    "COLIN'S": 'Giyim',
    'COLİNS': 'Giyim',
    'NETWORK': 'Giyim',
    'POLO': 'Giyim',
    'US POLO': 'Giyim',
    'BERSHKA': 'Giyim',
    'PULL&BEAR': 'Giyim',
    'STRADIVARIUS': 'Giyim',
    'TUDORS': 'Giyim',
    'KIĞILI': 'Giyim',
    'KIGILI': 'Giyim',
    'DAMAT': 'Giyim',
    // ── Faturalar ──
    'ENERJİSA': 'Faturalar',
    'ENERJISA': 'Faturalar',
    'BEDAS': 'Faturalar',
    'BEDAŞ': 'Faturalar',
    'IGDAS': 'Faturalar',
    'İGDAŞ': 'Faturalar',
    'AYEDAS': 'Faturalar',
    'AYEDAŞ': 'Faturalar',
    'ISKI': 'Faturalar',
    'İSKİ': 'Faturalar',
    'ASKI': 'Faturalar',
    'KAYSERIGAZ': 'Faturalar',
    'KAYSERİGAZ': 'Faturalar',
    'TÜRKSAT': 'Faturalar',
    'TURKSAT': 'Faturalar',
    'TURK TELEKOM': 'Faturalar',
    'TTNET': 'Faturalar',
    'SUPERONLINE': 'Faturalar',
  };

  // ═══════════════════════════════════════════════════════════════════
  // REGEX'LER
  // ═══════════════════════════════════════════════════════════════════
  static final RegExp _priceReg = RegExp(
    r'\*?\d{1,3}(?:\.\d{3})*[.,]\d{2}(?!\d)',
  );

  static final RegExp _numOnlyReg = RegExp(
    r'\d{1,3}(?:\.\d{3})*[.,]\d{2}(?!\d)',
  );

  // ── YENİ: BURUŞUK FİŞLER İÇİN TOLERANSLI FİYAT REGEX ──
  // Virgül/nokta yerine boşluk kabul eder
  // "119 40" formatını da yakalar
  static final RegExp _priceRegLoose = RegExp(r'\*?\d{1,4}[\s.,]\d{2}(?!\d)');

  // YENİ EKLENEN REGEX'LER — Türk fiş yapısı için kapsamlı set
  static final RegExp _ettnReg = RegExp(
    r'\b([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\b',
  );

  static final RegExp _mersisReg = RegExp(
    r'MERS[İI]S\s*(?:NO)?[\s:.-]*(\d{16})',
    caseSensitive: false,
  );

  static final RegExp _ibanReg = RegExp(
    r'\b(TR\d{2}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{2})\b',
  );

  static final RegExp _ekuReg = RegExp(
    r'\bEK[ÜU]\s*(?:NO|N0)?[\s:.-]*([A-Z]{0,3}\s?\d{6,12})',
    caseSensitive: false,
  );

  static final RegExp _pompaReg = RegExp(
    r'POMPA\s*(?:NO)?[\s:.-]*(\d+)',
    caseSensitive: false,
  );

  static final RegExp _litreReg = RegExp(
    r'(\d+[.,]\d{1,3})\s*(?:LT|LİT|LITRE|L)\b',
    caseSensitive: false,
  );

  static final RegExp _yakitTuruReg = RegExp(
    r'\b(MOTORIN|MOTORİN|BENZIN|BENZİN|LPG|95\s*OKTAN|97\s*OKTAN|DIESEL|DİZEL|EUROD[İI]ESEL|V/MAX|VMAX|ULTRAFORCE)\b',
    caseSensitive: false,
  );

  static final RegExp _plakaReg = RegExp(
    r'\b(0[1-9]|[1-7][0-9]|8[01])\s?([A-ZŞĞÇİÖÜ]{1,3})\s?(\d{2,4})\b',
  );

  static final RegExp _okcSeriReg = RegExp(r'\b([A-Z]{2}\s?\d{8})\b');

  static final RegExp _eArsivReg = RegExp(r'\b([A-Z]{3}20\d{11})\b');

  static final RegExp _paraBirimiReg = RegExp(
    r'\b(TL|TRY|₺|TURK\s*LIRASI|TÜRK\s*LİRASI|USD|EUR|EURO|GBP)\b',
    caseSensitive: false,
  );

  static final RegExp _araToplamReg = RegExp(
    r'\bARA\s*TOP(?:LAM)?\b',
    caseSensitive: false,
  );

  static final RegExp _telefonReg = RegExp(
    r'\b(0\d{3}[\s-]?\d{3}[\s-]?\d{2}[\s-]?\d{2})\b',
  );

  // ═══════════════════════════════════════════════════════════════════
  // ANA GİRİŞ NOKTASI — BURUŞUK FİŞ DESTEKLİ
  // ═══════════════════════════════════════════════════════════════════
  static ReceiptData parse(RecognizedText ocr) {
    final rows = _buildRows(ocr);
    if (rows.isEmpty) return ReceiptData(uyari: 'Metin okunamadı.');

    // ── YENİ: BURUŞUK FİŞ ALGILAMA ──
    // Buruşuk fişlerde tipik göstergeler:
    // 1. Çok az satır (fiş yırtılmış/parçalanmış)
    // 2. Yüksek bozuk karakter oranı (OCR garip karakterler üretir)
    // 3. Çok sayıda tek-karakterli satır (parçalanma işareti)
    final bool muhtemelenBurusuk = _isCrumpled(rows);

    // ── İPTAL / İADE FİŞİ KONTROLÜ ──
    final bool isIptal = rows.any(
      (r) =>
          r.upper.contains('İPTAL') ||
          r.upper.contains('IPTAL') ||
          r.upper.contains('İADE FİŞİ') ||
          r.upper.contains('IADE FISI'),
    );

    final bool maliDegeriYok = rows.any(
      (r) =>
          r.upper.contains('MALİ DEĞERİ YOKTUR') ||
          r.upper.contains('MALI DEGERI YOKTUR'),
    );

    final bool isBankaDekontu = _isBankaDekontu(rows);

    final firma = _firma(rows);
    final adres = _adres(rows);
    final vd = _vergiDairesi(rows);
    final vkn = _vergiNo(rows);
    final belge = _belgeTuru(rows, maliDegeriYok, isBankaDekontu);
    final fisNo = _fisNo(rows);
    final seri = _seriNo(rows);
    final zNo = _zNo(rows);
    final tarih = _tarih(rows);
    final saat = _saat(rows);
    final kdvDetay = _kdvDetay(rows);
    final topKdv = _toplamKdv(rows, kdvDetay);
    final matrah = _matrah(rows);
    // YENİ: muhtemelenBurusuk parametresi geçiliyor
    final toplam = _toplam(
      rows,
      topKdv,
      isBankaDekontu,
      kdvDetay,
      muhtemelenBurusuk,
    );
    final odeme = _odemeYontemi(rows);
    final paraUstu = _paraUstu(rows);

    // ── YENİ EKLENEN ALANLAR ──────────────────────────────────────
    final ekuNo = _ekuNo(rows);
    final ettn = _ettn(rows);
    final mersis = _mersis(rows);
    final iban = _iban(rows);
    final araToplam = _araToplam(rows);
    final paraBirimi = _paraBirimi(rows);
    final yakitDetay = _yakitDetay(rows);
    final telefon = _telefon(rows);

    final Map<String, double> scores = {
      if (firma.found) 'firma': firma.confidence,
      if (vkn.found) 'vergi': vkn.confidence,
      if (tarih.found) 'tarih': tarih.confidence,
      if (saat.found) 'saat': saat.confidence,
      if (topKdv.found) 'kdv': topKdv.confidence,
      if (toplam.found) 'toplam': toplam.confidence,
      if (fisNo.found) 'fisNo': fisNo.confidence,
    };

    String? uyari;
    if (isIptal) {
      uyari =
          'DİKKAT: Bu bir İPTAL veya İADE belgesidir. Gider olarak kaydedilemez!';
    } else if (maliDegeriYok) {
      uyari = 'Bu fiş Mali Değeri Yoktur — vergi belgesi değildir.';
    } else if (isBankaDekontu) {
      uyari =
          'Bu bir banka pos dekontu — ödeme belgesidir, vergi fişi değildir.';
    } else if (!toplam.found) {
      uyari = 'Toplam tutar tespit edilemedi. Lütfen kontrol edin.';
    } else if (toplam.confidence < 0.60) {
      uyari = 'Toplam tutar düşük güvenle okundu. Kontrol önerilir.';
    }

    // ── YENİ: BURUŞUK FİŞ UYARISI ──
    if (muhtemelenBurusuk && uyari == null) {
      uyari = 'Bu fiş buruşuk veya zor okunan bir görüntüden tarandı. '
          'Lütfen tüm alanları kontrol edin.';
    } else if (muhtemelenBurusuk &&
        uyari != null &&
        !uyari.contains('buruşuk')) {
      uyari =
          uyari + '\nNot: Fiş buruşuk olarak algılandı, alanları kontrol edin.';
    }

    String finalToplamKdv = topKdv.value;
    String finalToplamTutar = toplam.value;

    // ── KDV / TOPLAM MATEMATİKSEL SAĞLAMA MOTORU ──
    if (toplam.found) {
      double tVal = double.tryParse(toplam.value.replaceAll(',', '.')) ?? 0;
      double kVal = double.tryParse(topKdv.value.replaceAll(',', '.')) ?? 0;

      if (kVal > 0 && tVal > 0 && kVal >= tVal) {
        double kdvDetayToplami = 0;
        for (var item in kdvDetay) {
          kdvDetayToplami +=
              double.tryParse(item.tutar.replaceAll(',', '.')) ?? 0;
        }

        if (kdvDetayToplami > 0 && kdvDetayToplami < tVal) {
          finalToplamKdv =
              kdvDetayToplami.toStringAsFixed(2).replaceAll('.', ',');
          uyari = (uyari == null ? '' : uyari + '\n') +
              'KDV tutarı yanlış okundu, fiş detaylarından otomatik düzeltildi.';
        } else {
          finalToplamTutar = "";
          if (!isIptal) {
            uyari = (uyari == null ? '' : uyari + '\n') +
                'Tutar ve KDV fiziksel olarak imkansız (KDV >= Toplam). Lütfen elle giriniz.';
          }
        }
      }
    }

    // ── YENİ: MATEMATİKSEL ÇIKARSAMA (BURUŞUK FALLBACK) ──
    // Eğer toplam okunamadıysa AMA matrah ve KDV detayları varsa,
    // toplam = matrah + KDV detay toplamı olarak hesaplanabilir
    if (finalToplamTutar.isEmpty && matrah.found && kdvDetay.isNotEmpty) {
      double matrahVal =
          double.tryParse(matrah.value.replaceAll(',', '.')) ?? 0;
      double kdvDetayToplami = 0;
      for (var item in kdvDetay) {
        kdvDetayToplami +=
            double.tryParse(item.tutar.replaceAll(',', '.')) ?? 0;
      }
      if (matrahVal > 0 && kdvDetayToplami > 0) {
        final hesaplananToplam = matrahVal + kdvDetayToplami;
        finalToplamTutar =
            hesaplananToplam.toStringAsFixed(2).replaceAll('.', ',');
        uyari = (uyari == null ? '' : uyari + '\n') +
            'Toplam tutar matematiksel olarak hesaplandı (Matrah + KDV). '
                'Kontrol önerilir.';
        scores['toplam'] = 0.55;
      }
    }

    return ReceiptData(
      firmaAdi: firma.value,
      firmaAdresi: adres.value,
      vergiDairesi: vd.value,
      vergiTcNo: vkn.value,
      belgeTuru: belge.value,
      fisNo: fisNo.value,
      seriNo: seri.value,
      zNo: zNo.value,
      ekuNo: ekuNo.value,
      ettn: ettn.value,
      mersisNo: mersis.value,
      iban: iban.value,
      tarih: tarih.value,
      saat: saat.value,
      kdvDetay: kdvDetay,
      toplamKdv: finalToplamKdv,
      kdvHaricToplam: matrah.value,
      araToplam: araToplam.value,
      toplamTutar: finalToplamTutar,
      odemeYontemi: odeme.value,
      paraUstu: paraUstu.value,
      paraBirimi: paraBirimi.value.isEmpty ? 'TL' : paraBirimi.value,
      yakitTuru: yakitDetay['turu'],
      yakitLitre: yakitDetay['litre'],
      pompaNo: yakitDetay['pompa'],
      aracPlakasi: yakitDetay['plaka'],
      telefon: telefon.value.isEmpty ? null : telefon.value,
      kategori: _kategori(firma.value, odeme.value, rows),
      confidenceScores: scores,
      uyari: uyari,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // YENİ: BURUŞUK FİŞ ALGILAMA
  // ═══════════════════════════════════════════════════════════════════
  static bool _isCrumpled(List<_Row> rows) {
    int bozukKarakterSayisi = 0;
    int tekKarakterliSatir = 0;
    int toplamKarakter = 0;

    // OCR'da bozulma işareti olabilecek karakterler
    final bozukReg = RegExp(r'[Н^~`{}\\<>¬§|]');

    for (final row in rows) {
      final t = row.text;
      toplamKarakter += t.length;

      // Garip karakterler say
      bozukKarakterSayisi += bozukReg.allMatches(t).length;

      // Tek karakterli satırlar parçalanma işareti
      if (t.trim().length <= 1) tekKarakterliSatir++;
    }

    if (toplamKarakter == 0) return false;

    final bozukOran = bozukKarakterSayisi / toplamKarakter;
    final tekOran = tekKarakterliSatir / rows.length;

    // Buruşukluk göstergeleri:
    // - %3+ bozuk karakter, VEYA
    // - 5'ten az satır VE yine de fiş gibi görünüyor (toplam karakter > 50), VEYA
    // - %20+ satır tek karakterli (parçalanma)
    if (bozukOran > 0.03) return true;
    if (rows.length < 5 && toplamKarakter > 50) return true;
    if (tekOran > 0.2) return true;

    return false;
  }

  // ═══════════════════════════════════════════════════════════════════
  // BANKA DEKONTU TESPİTİ
  // ═══════════════════════════════════════════════════════════════════
  static bool _isBankaDekontu(List<_Row> rows) {
    int bankaIndicators = 0;
    for (final row in rows) {
      final u = row.upper;
      if (u.contains('İŞLEM TUTARI') || u.contains('ISLEM TUTARI'))
        bankaIndicators++;
      if (u.contains('ONAY KODU')) bankaIndicators++;
      if (u.contains('BANKA REFERANS')) bankaIndicators++;
      if (u.contains('ACQUIRER')) bankaIndicators++;
      if (u.contains('AID:A0')) bankaIndicators++;
      if (bankaIndicators >= 3) return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════
  // SATIR İNŞA MOTORU — Buruşuk için tolerans artırıldı
  // ═══════════════════════════════════════════════════════════════════
  static List<_Row> _buildRows(RecognizedText ocr) {
    final rows = <_Row>[];

    for (final block in ocr.blocks) {
      for (final line in block.lines) {
        for (final el in line.elements) {
          final t = el.text.trim();
          if (t.isEmpty) continue;

          final yc = el.boundingBox.top + el.boundingBox.height / 2;
          // ── YENİ: Buruşuk fişlerde satırlar eğri olur, tolerans biraz artırıldı ──
          // Eski: 0.55, 8.0-24.0
          // Yeni: 0.65, 8.0-28.0 (daha geniş tolerans)
          final tol = (el.boundingBox.height * 0.65).clamp(8.0, 28.0);

          bool added = false;
          for (final row in rows) {
            if ((row.yCenter - yc).abs() < tol) {
              row.elements.add(el);
              row.yCenter = (row.yCenter * (row.elements.length - 1) + yc) /
                  row.elements.length;
              added = true;
              break;
            }
          }
          if (!added) rows.add(_Row(yc, [el]));
        }
      }
    }

    rows.sort((a, b) => a.yCenter.compareTo(b.yCenter));
    for (final r in rows) {
      r.elements.sort(
        (a, b) => a.boundingBox.left.compareTo(b.boundingBox.left),
      );
    }
    return rows;
  }

  // ═══════════════════════════════════════════════════════════════════
  // FİRMA ADI
  // ═══════════════════════════════════════════════════════════════════
  static _Field _firma(List<_Row> rows) {
    _Field bestField = _Field.empty;
    double maxScore = 0.0;

    for (int i = 0; i < rows.length && i < 6; i++) {
      final t = rows[i].text.trim();
      final u = t.toUpperCase();
      double score = 0.0;

      if (t.length < 3 || _anyOf(u, _skipKw) || RegExp(r'^\d+$').hasMatch(t))
        continue;

      if (u.contains('A.S') ||
          u.contains('A.Ş') ||
          u.contains('LTD') ||
          u.contains('STI') ||
          u.contains('ŞTİ') ||
          u.contains('TIC') ||
          u.contains('TİC') ||
          u.contains('SAN')) {
        score += 0.40;
      }

      for (String brand in _kategoriMap.keys) {
        if (u.contains(brand)) {
          score += 0.50;
          break;
        }
      }

      score += (0.20 - (i * 0.03));

      if (RegExp(r'\d{5,}').hasMatch(t)) score -= 0.30;
      if (u.contains('VKN') || u.contains('V.D')) score -= 0.50;

      if (score > maxScore) {
        maxScore = score;
        bestField = _Field(t, maxScore.clamp(0.0, 0.99));
      }
    }

    if (bestField.value.isEmpty || maxScore < 0.20) {
      for (int i = 0; i < rows.length && i < 5; i++) {
        for (String brand in _kategoriMap.keys) {
          if (rows[i].upper.contains(brand)) return _Field(rows[i].text, 0.85);
        }
      }
    }

    // ── YENİ: BURUŞUK FALLBACK — markaları AGRESİF temizlenmiş metinde ara ──
    if (bestField.value.isEmpty || maxScore < 0.20) {
      for (int i = 0; i < rows.length && i < 6; i++) {
        final uAgg = rows[i].upperAggressive;
        for (String brand in _kategoriMap.keys) {
          // Bulanık eşleştirme: marka adında 1 harf hata kabul
          if (_fuzzy(uAgg, brand)) {
            return _Field(rows[i].text, 0.65);
          }
        }
      }
    }

    return bestField;
  }

  // ═══════════════════════════════════════════════════════════════════
  // ADRES
  // ═══════════════════════════════════════════════════════════════════
  static _Field _adres(List<_Row> rows) {
    final adresKw = RegExp(
      r'\b(CAD\.?|CADDE|SOK\.?|SOKAK|MAH\.?|MAHALLE|BULVAR|BLV\.?|NO:?|APT\.?|MH\.?)\b',
      caseSensitive: false,
    );
    for (int i = 1; i < rows.length && i < 12; i++) {
      if (adresKw.hasMatch(rows[i].text)) {
        return _Field(rows[i].text.trim(), 0.82);
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // VERGİ DAİRESİ
  // ═══════════════════════════════════════════════════════════════════
  static _Field _vergiDairesi(List<_Row> rows) {
    for (int i = 0; i < rows.length && i < 12; i++) {
      final u = rows[i].upper;
      if (u.endsWith(' VD') ||
          u.endsWith(' VD.') ||
          u.contains('V.D') ||
          u.contains('VERGI DAIRESI') ||
          u.contains('VERGİ DAİRESİ')) {
        String cleaned = rows[i]
            .text
            .replaceAll(
              RegExp(r'\bVERG[Iİ]\sDA[Iİ]RES[Iİ]\b', caseSensitive: false),
              '',
            )
            .replaceAll(RegExp(r'\bV\.?D\.?\b', caseSensitive: false), '')
            .replaceAll(RegExp(r'\b\d{10,11}\b'), '')
            .replaceAll(RegExp(r'VKN|TCKN|NO|:', caseSensitive: false), '')
            .trim();

        if (cleaned.length < 3 && i > 0) {
          cleaned = rows[i - 1].text.trim();
        }

        if (cleaned.length > 2) return _Field(cleaned, 0.92);
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // VKN / TC KİMLİK NO
  // ═══════════════════════════════════════════════════════════════════
  static _Field _vergiNo(List<_Row> rows) {
    final reg = RegExp(r'\b([1-9]\d{9,10})\b');

    for (int i = 0; i < rows.length; i++) {
      final rowText = _ocrClean(rows[i].text);
      final u = rows[i].upper;

      if (RegExp(r'\b\d{16}\b').hasMatch(rowText)) continue;
      if (RegExp(r'\b\d{2}[./-]\d{2}[./-]\d{4}\b').hasMatch(rowText)) continue;
      if (u.contains('FIS') || u.contains('Z NO')) continue;

      final m = reg.firstMatch(rowText);
      if (m != null) {
        final num = m.group(1)!;
        final labeled = u.contains('VKN') ||
            u.contains('VD') ||
            u.contains('TC') ||
            u.contains('NO');
        return _Field(num, labeled ? 0.98 : 0.85);
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // BELGE TÜRÜ
  // ═══════════════════════════════════════════════════════════════════
  static _Field _belgeTuru(
    List<_Row> rows,
    bool maliDegeriYok,
    bool isBankaDekontu,
  ) {
    if (isBankaDekontu) return const _Field('Banka Pos Dekontu', 1.0);
    if (maliDegeriYok) return const _Field('Taksi/POS Fişi', 0.95);

    for (int i = 0; i < rows.length && i < 10; i++) {
      final u = rows[i].upper;
      for (final entry in _belgeKw.entries) {
        if (u.contains(entry.key)) return _Field(entry.value, 0.95);
      }
    }
    return const _Field('ÖKC Fişi', 0.50);
  }

  // ═══════════════════════════════════════════════════════════════════
  // FİŞ NO
  // ═══════════════════════════════════════════════════════════════════
  static _Field _fisNo(List<_Row> rows) {
    final fisReg = RegExp(
      r'\b(?:F[Iİıi]S|F[Iİıi][SŞşs]|BELGE|ORD|F)\s*(?:NO)?\s*[:.\-]?\s*(\d{2,8})\b',
      caseSensitive: false,
    );

    final eArsivReg = RegExp(r'\b([A-Z]{3}20\d{11})\b', caseSensitive: false);

    for (int i = 0; i < rows.length; i++) {
      final cleaned = _ocrClean(rows[i].text);

      final eMatch = eArsivReg.firstMatch(cleaned);
      if (eMatch != null) return _Field(eMatch.group(1)!.toUpperCase(), 0.99);

      final m = fisReg.firstMatch(cleaned);
      if (m != null) {
        final val = m.group(1)!.replaceAll(RegExp(r'^0+'), '');
        if (val.isNotEmpty) return _Field(val, 0.95);
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // SERİ NO
  // ═══════════════════════════════════════════════════════════════════
  static _Field _seriNo(List<_Row> rows) {
    final seriReg = RegExp(
      r'\bSER[Iİıi]\s*(?:\/\s*SIRA\s*)?(?:NO\s*)?[:.\-]?\s*([A-Za-z]{1,3})\b',
    );
    for (int i = 0; i < rows.length && i < 15; i++) {
      final m = seriReg.firstMatch(rows[i].text);
      if (m != null) return _Field(m.group(1)!.trim().toUpperCase(), 0.90);
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Z NO
  // ═══════════════════════════════════════════════════════════════════
  static _Field _zNo(List<_Row> rows) {
    final zReg = RegExp(
      r'\bZ\s*(?:NO\s*)?[:\-]?\s*(\d{3,6})\b',
      caseSensitive: false,
    );
    for (int i = 0; i < rows.length; i++) {
      final m = zReg.firstMatch(rows[i].text);
      if (m != null) return _Field(m.group(1)!, 0.88);
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // TARİH — GÜÇLENDİRİLMİŞ + BURUŞUK FALLBACK
  // ═══════════════════════════════════════════════════════════════════
  static _Field _tarih(List<_Row> rows) {
    // Format 1: DD.MM.YYYY / DD/MM/YYYY / DD-MM-YYYY (Türk standardı)
    final dateReg = RegExp(
      r'(0?[1-9]|[12][0-9]|3[01])[\s.\-\/,:;]+(0?[1-9]|1[012])[\s.\-\/,:;]+(20[1-3][0-9]|[1-2][0-9])',
    );

    // Format 2: YYYY-MM-DD (ISO 8601 — e-Arşiv fişlerinde)
    final isoDateReg = RegExp(
      r'(20[1-3][0-9])[-/](0[1-9]|1[012])[-/](0[1-9]|[12][0-9]|3[01])',
    );

    // Format 3: "15 Mayıs 2026" gibi yazılı aylar
    final monthMap = {
      'OCAK': '01',
      'OCA': '01',
      'ŞUBAT': '02',
      'SUBAT': '02',
      'ŞUB': '02',
      'SUB': '02',
      'MART': '03',
      'MAR': '03',
      'NİSAN': '04',
      'NISAN': '04',
      'NIS': '04',
      'MAYIS': '05',
      'MAY': '05',
      'HAZİRAN': '06',
      'HAZIRAN': '06',
      'HAZ': '06',
      'TEMMUZ': '07',
      'TEM': '07',
      'AĞUSTOS': '08',
      'AGUSTOS': '08',
      'AGU': '08',
      'EYLÜL': '09',
      'EYLUL': '09',
      'EYL': '09',
      'EKİM': '10',
      'EKIM': '10',
      'EKI': '10',
      'KASIM': '11',
      'KAS': '11',
      'ARALIK': '12',
      'ARA': '12',
    };
    final writtenDateReg = RegExp(
      r'(\d{1,2})\s+(OCAK|OCA|ŞUBAT|SUBAT|ŞUB|SUB|MART|MAR|NİSAN|NISAN|NIS|MAYIS|MAY|HAZİRAN|HAZIRAN|HAZ|TEMMUZ|TEM|AĞUSTOS|AGUSTOS|AGU|EYLÜL|EYLUL|EYL|EKİM|EKIM|EKI|KASIM|KAS|ARALIK|ARA)\s+(20\d{2})',
      caseSensitive: false,
    );

    // ── YENİ: BURUŞUK İÇİN AYRAÇSIZ TARİH ──
    // 8 hane birleşik: 15052026 → 15.05.2026
    final dateNoSepReg = RegExp(
      r'\b(0[1-9]|[12][0-9]|3[01])(0[1-9]|1[012])(20[1-3][0-9])\b',
    );

    // ── YENİ: 6 hane formatı: 150526 → 15.05.26 → 15.05.2026 ──
    final dateShortReg = RegExp(
      r'\b(0[1-9]|[12][0-9]|3[01])(0[1-9]|1[012])(2[0-9])\b',
    );

    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      String cleaned = _ocrClean(rows[i].text);

      // ISO format kontrolü
      final isoMatch = isoDateReg.firstMatch(cleaned);
      if (isoMatch != null) {
        String raw =
            '${isoMatch.group(3)!}.${isoMatch.group(2)!}.${isoMatch.group(1)!}';
        if (_validDate(raw)) {
          return _Field(raw, 0.98);
        }
      }

      // Yazılı ay kontrolü
      final writtenMatch = writtenDateReg.firstMatch(u);
      if (writtenMatch != null) {
        String gun = writtenMatch.group(1)!.padLeft(2, '0');
        String ay = monthMap[writtenMatch.group(2)!.toUpperCase()] ?? '00';
        String yil = writtenMatch.group(3)!;
        String raw = '$gun.$ay.$yil';
        if (_validDate(raw)) {
          return _Field(raw, 0.95);
        }
      }

      // Standart Türk formatı
      String noSpaces = cleaned.replaceAll(' ', '');

      Match? m = dateReg.firstMatch(noSpaces);

      if (m == null) {
        m = dateReg.firstMatch(cleaned);
      }

      if (m != null) {
        String gun = m.group(1)!.padLeft(2, '0');
        String ay = m.group(2)!.padLeft(2, '0');
        String yil = m.group(3)!;

        if (yil.length == 2) yil = '20$yil';

        String raw = '$gun.$ay.$yil';

        if (_validDate(raw)) {
          final isExplicit = u.contains('TAR') || u.contains('TRH');
          return _Field(raw, isExplicit ? 0.99 : 0.90);
        }
      }
    }

    // ── YENİ: BURUŞUK FALLBACK — ayraçsız tarih ──
    for (int i = 0; i < rows.length; i++) {
      String cleaned = _ocrClean(rows[i].text);

      // 8 haneli: 15052026
      final mLong = dateNoSepReg.firstMatch(cleaned);
      if (mLong != null) {
        String raw = '${mLong.group(1)}.${mLong.group(2)}.${mLong.group(3)}';
        if (_validDate(raw)) return _Field(raw, 0.70);
      }

      // 6 haneli: 150526 → 15.05.2026
      final mShort = dateShortReg.firstMatch(cleaned);
      if (mShort != null) {
        String raw =
            '${mShort.group(1)}.${mShort.group(2)}.20${mShort.group(3)}';
        if (_validDate(raw)) return _Field(raw, 0.65);
      }
    }

    // ── YENİ: AGRESİF METİN İÇİNDE TARİH ARAMA ──
    for (int i = 0; i < rows.length; i++) {
      final aggCleaned = _ocrClean(rows[i].textAggressive).replaceAll(' ', '');

      Match? m = dateReg.firstMatch(aggCleaned);
      if (m != null) {
        String gun = m.group(1)!.padLeft(2, '0');
        String ay = m.group(2)!.padLeft(2, '0');
        String yil = m.group(3)!;
        if (yil.length == 2) yil = '20$yil';
        String raw = '$gun.$ay.$yil';
        if (_validDate(raw)) return _Field(raw, 0.60);
      }
    }

    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // SAAT
  // ═══════════════════════════════════════════════════════════════════
  static _Field _saat(List<_Row> rows) {
    final timeReg = RegExp(
      r'\b([01]?\d|2[0-3])[:;]([0-5]\d)(?:[:;][0-5]\d)?\b',
    );
    for (int i = 0; i < rows.length; i++) {
      final cleaned = _ocrClean(rows[i].text);
      final m = timeReg.firstMatch(cleaned);
      if (m == null) continue;
      final h = int.tryParse(m.group(1)!) ?? -1;
      final min = int.tryParse(m.group(2)!) ?? -1;
      if (h >= 0 && h <= 23 && min >= 0 && min <= 59) {
        final norm =
            '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
        return _Field(norm, 0.96);
      }
    }

    // ── YENİ: BURUŞUK FALLBACK — ayraçsız saat (1432 → 14:32) ──
    final timeNoSepReg = RegExp(r'\b([01]\d|2[0-3])([0-5]\d)\b');
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      // Sadece SAAT etiketi yakınındaysa veya tarih yakınındaysa kabul et
      // (rastgele 4 haneli sayıları saat sanma)
      if (!u.contains('SAAT') && !u.contains('TAR')) continue;

      final cleaned = _ocrClean(rows[i].text);
      final m = timeNoSepReg.firstMatch(cleaned);
      if (m != null) {
        final h = int.tryParse(m.group(1)!) ?? -1;
        final min = int.tryParse(m.group(2)!) ?? -1;
        if (h >= 0 && h <= 23 && min >= 0 && min <= 59) {
          final norm =
              '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
          return _Field(norm, 0.65);
        }
      }
    }

    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // KDV ORAN DETAYLARI — GÜÇLENDİRİLMİŞ + BURUŞUK FALLBACK
  // Türkiye'de geçerli KDV oranları: %1, %8, %10, %18, %20
  // ═══════════════════════════════════════════════════════════════════
  static List<KdvItem> _kdvDetay(List<_Row> rows) {
    final items = <KdvItem>[];
    final foundOranlar = <String>{};

    // GÜÇLENDİRİLDİ: Türkiye'de geçerli KDV oranlarını sınırla
    final oranFiyatReg = RegExp(r'%\s*(1|8|10|18|20)\b');

    // ── YENİ: BURUŞUK İÇİN — "%" işareti kaybolmuş olabilir ──
    // "KDV 18 119.40" gibi % işareti olmadan da yakala
    final oranFiyatLooseReg = RegExp(
      r'(?:KDV|VAT)\s+(1|8|10|18|20)\b',
      caseSensitive: false,
    );

    final tableSatirReg = RegExp(
      r'%\s*(1|8|10|18|20)\s+([\d.,]+)\s+\*?([\d.,]+)(?:\s+\*?([\d.,]+))?',
    );

    for (int idx = 0; idx < rows.length; idx++) {
      final row = rows[idx];
      final u = row.upper;
      final cleaned = _ocrClean(row.text);

      if (u.contains('TOPKDV') ||
          u.contains('TOP KDV') ||
          u.contains('TOPLAM KDV')) continue;
      if (!u.contains('KDV') &&
          !oranFiyatReg.hasMatch(cleaned) &&
          !oranFiyatLooseReg.hasMatch(cleaned)) continue;

      final m2 = tableSatirReg.firstMatch(cleaned);
      if (m2 != null) {
        final oran = m2.group(1)!;
        if (!foundOranlar.contains(oran)) {
          foundOranlar.add(oran);
          items.add(
            KdvItem(
              oran: '%$oran',
              matrah: _normPrice(m2.group(2)!),
              tutar: _normPrice(m2.group(3)!),
            ),
          );
        }
        continue;
      }

      // Önce normal oranFiyatReg, sonra loose
      Iterable<RegExpMatch> oranMatches = oranFiyatReg.allMatches(cleaned);
      if (oranMatches.isEmpty) {
        oranMatches = oranFiyatLooseReg.allMatches(cleaned);
      }

      for (final om in oranMatches) {
        final oran = om.group(1)!;
        if (foundOranlar.contains(oran)) continue;

        final prices = row.allPrices(_priceReg);
        final kdvFiyat = prices
            .where((p) => p.startsWith('*'))
            .map((p) => p.substring(1))
            .firstOrNull;
        final matrahFiyat = prices.where((p) => !p.startsWith('*')).firstOrNull;

        if (kdvFiyat != null || matrahFiyat != null) {
          foundOranlar.add(oran);
          items.add(
            KdvItem(
              oran: '%$oran',
              matrah: matrahFiyat != null ? _normPrice(matrahFiyat) : '',
              tutar: kdvFiyat != null
                  ? _normPrice(kdvFiyat)
                  : _normPrice(matrahFiyat ?? ''),
            ),
          );
        } else if (idx + 1 < rows.length) {
          // Bir sonraki satırda fiyat varsa bağla
          final nextPrices = rows[idx + 1].allPrices(_priceReg);
          if (nextPrices.isNotEmpty) {
            foundOranlar.add(oran);
            items.add(
              KdvItem(
                oran: '%$oran',
                matrah: '',
                tutar: _normPrice(nextPrices.last),
              ),
            );
          }
        }
      }
    }

    return items;
  }

  // ═══════════════════════════════════════════════════════════════════
  // TOPLAM KDV — Buruşuk fallback eklendi
  // ═══════════════════════════════════════════════════════════════════
  static _Field _toplamKdv(List<_Row> rows, List<KdvItem> detay) {
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (!_anyOf(u, _kdvKw)) continue;

      final cleaned = _ocrClean(rows[i].text);
      final p = _findRightmostPrice(cleaned, _priceReg);
      if (p != null) return _Field(_normPrice(p), 0.95);
    }

    if (detay.isNotEmpty) {
      double total = 0;
      bool valid = true;
      for (final item in detay) {
        final v = double.tryParse(item.tutar);
        if (v == null) {
          valid = false;
          break;
        }
        total += v;
      }
      if (valid && total > 0) {
        return _Field(total.toStringAsFixed(2), 0.80);
      }
    }

    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (!u.contains('KDV')) continue;
      if (_anyOf(u, _totalKw)) continue;
      if (u.contains('TOPKDV')) continue;

      final cleaned = _ocrClean(rows[i].text);
      final p = _findRightmostPrice(cleaned, _priceReg);
      if (p != null) return _Field(_normPrice(p), 0.78);
    }

    // ── YENİ: BURUŞUK FALLBACK — agresif metinde KDV ara ──
    for (int i = 0; i < rows.length; i++) {
      final uAgg = rows[i].upperAggressive;

      // KDV fuzzy aramak (buruşukta KDV → K0V, KБV, KDМ olabilir)
      if (!_fuzzy(uAgg, 'KDV') && !_fuzzy(uAgg, 'TOPKDV')) continue;
      if (_anyOf(uAgg, _totalKw)) continue;

      final cleaned = _ocrClean(rows[i].textAggressive);
      final p = _findRightmostPrice(cleaned, _priceReg);
      if (p != null) return _Field(_normPrice(p), 0.55);

      // Toleranslı fiyat regex de dene
      final pLoose = _findRightmostPrice(cleaned, _priceRegLoose);
      if (pLoose != null) return _Field(_normPriceLoose(pLoose), 0.45);
    }

    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // MATRAH
  // ═══════════════════════════════════════════════════════════════════
  static _Field _matrah(List<_Row> rows) {
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (u.contains('MATRAH') ||
          u.contains('KDV HARİÇ') ||
          u.contains('KDV HARIC') ||
          u.contains('VERGİSİZ') ||
          u.contains('VERGISIZ')) {
        final cleaned = _ocrClean(rows[i].text);
        final p = _findRightmostPrice(cleaned, _priceReg);
        if (p != null) return _Field(_normPrice(p), 0.90);
      }
    }

    // ── YENİ: BURUŞUK FALLBACK — agresif metinde matrah ara ──
    for (int i = 0; i < rows.length; i++) {
      final uAgg = rows[i].upperAggressive;
      if (_fuzzy(uAgg, 'MATRAH') ||
          _fuzzy(uAgg, 'KDV HARIC') ||
          uAgg.contains('VERGISIZ')) {
        final cleaned = _ocrClean(rows[i].textAggressive);
        final p = _findRightmostPrice(cleaned, _priceReg);
        if (p != null) return _Field(_normPrice(p), 0.65);
      }
    }

    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // GENEL TOPLAM — BURUŞUK GÜÇLENDİRİLDİ
  // YENİ İmza: _toplam(rows, kdv, isBankaDekontu, kdvDetay, muhtemelenBurusuk)
  // ═══════════════════════════════════════════════════════════════════
  static _Field _toplam(
    List<_Row> rows,
    _Field kdv,
    bool isBankaDekontu,
    List<KdvItem> kdvDetay,
    bool muhtemelenBurusuk,
  ) {
    if (isBankaDekontu) {
      for (int i = 0; i < rows.length; i++) {
        final u = rows[i].upper;
        if (u.contains('İŞLEM TUTARI') ||
            u.contains('ISLEM TUTARI') ||
            u.contains('TUTAR')) {
          final cleaned = _ocrClean(rows[i].text);
          final p = _findRightmostPrice(cleaned, _priceReg);
          if (p != null) return _Field(_normPrice(p), 0.85);
        }
      }
    }

    _Field best = _Field.empty;

    // ─── KATMAN 1: Standart toplam araması ───
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;

      // ARA TOPLAM KORUMASI
      if (u.contains('ARA TOP') ||
          u.contains('ARATOP') ||
          u.contains('ARA TOPLAM')) continue;

      if (u.contains('TOPKDV') || u.contains('TOP KDV')) continue;
      if (_anyOf(u, _kdvKw) &&
          !_anyOf(u, ['ODENEN', 'ÖDENECEK', 'ODENECEK KDV DAHIL'])) continue;

      bool matched = false;
      for (final kw in _totalKw) {
        if (_fuzzy(u, kw)) {
          matched = true;
          break;
        }
      }
      if (!matched) continue;

      final cleaned = _ocrClean(rows[i].text);
      final p = _findRightmostPrice(cleaned, _priceReg);
      if (p == null) continue;

      final norm = _normPrice(p);

      if (kdv.found && norm == kdv.value) continue;
      final kdvVal = double.tryParse(kdv.value) ?? 0;
      final toplamVal = double.tryParse(norm) ?? 0;
      if (kdv.found && toplamVal < kdvVal && toplamVal > 0) continue;

      final exactMatch = _anyOf(u, _totalKw);
      final isShortMatch = u.trim() == 'TOP' ||
          u.trim().startsWith('TOP ') ||
          u.trim().endsWith(' TOP');
      final posBonus = (i / rows.length) >= 0.5 ? 0.05 : 0.0;
      final conf =
          ((exactMatch ? (isShortMatch ? 0.80 : 0.95) : 0.74) + posBonus).clamp(
        0.0,
        1.0,
      );

      if (conf > best.confidence) best = _Field(norm, conf);
    }

    if (best.confidence >= 0.70) return best;

    // ─── KATMAN 2: KDV satırından SONRAKİ toplam ───
    for (int i = 0; i < rows.length - 1; i++) {
      final u = rows[i].upper;
      if (u.contains('TOPKDV') || _anyOf(u, _kdvKw)) {
        for (int j = i + 1; j <= i + 3 && j < rows.length; j++) {
          final jU = rows[j].upper;
          if (_anyOf(jU, _totalKw) || _priceReg.hasMatch(rows[j].text)) {
            final cleaned = _ocrClean(rows[j].text);
            final p = _findRightmostPrice(cleaned, _priceReg);
            if (p != null) {
              final norm = _normPrice(p);
              if (kdv.found && norm != kdv.value) {
                if (0.75 > best.confidence) best = _Field(norm, 0.75);
                break;
              }
            }
          }
        }
      }
    }

    if (best.confidence >= 0.60) return best;

    // ─── KATMAN 3: Ödeme satırından geriye doğru ───
    for (int i = rows.length - 1; i >= 0; i--) {
      final u = rows[i].upper;
      if (u.contains('KDV DAHİL') ||
          u.contains('KDV DAHIL') ||
          _anyOf(u, _paymentKw)) {
        final cleaned = _ocrClean(rows[i].text);
        final p = _findRightmostPrice(cleaned, _priceReg);
        if (p != null) {
          final norm = _normPrice(p);
          if (0.68 > best.confidence) best = _Field(norm, 0.68);
          break;
        }
      }
    }

    if (best.confidence >= 0.55) return best;

    // ─── KATMAN 4: SATIŞ satırından sonra TUTAR ───
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (u.trim() == 'SATIŞ' || u.trim() == 'SATIS') {
        for (int j = i + 1; j <= i + 5 && j < rows.length; j++) {
          final jU = rows[j].upper;
          if (jU.contains('TUTAR') || jU.contains('TL')) {
            final cleaned = _ocrClean(rows[j].text);
            final p = _findRightmostPrice(cleaned, _priceReg);
            if (p != null) {
              final norm = _normPrice(p);
              if (0.60 > best.confidence) best = _Field(norm, 0.60);
              break;
            }
          }
        }
      }
    }

    if (best.confidence >= 0.50) return best;

    // ═══════════════════════════════════════════════════════════════
    // ─── YENİ KATMAN 5: BURUŞUK FALLBACK — AGRESİF METİNDE ARAMA ───
    // Standart aramalar yetmedi, buruşuk olduğu için agresif arama yap
    // ═══════════════════════════════════════════════════════════════
    if (best.confidence < 0.55 || muhtemelenBurusuk) {
      for (int i = 0; i < rows.length; i++) {
        final uAgg = rows[i].upperAggressive;

        // ARA TOPLAM koruması (agresif metinde de)
        if (uAgg.contains('ARA TOP') ||
            uAgg.contains('ARATOP') ||
            uAgg.contains('ARA TOPLAM')) continue;
        if (uAgg.contains('TOPKDV') || uAgg.contains('TOP KDV')) continue;

        // _totalKw VE _totalKwLoose ikisini de dene (buruşuk varyantları)
        bool matched = false;
        for (final kw in _totalKw) {
          if (_fuzzy(uAgg, kw)) {
            matched = true;
            break;
          }
        }
        if (!matched) {
          for (final kw in _totalKwLoose) {
            if (uAgg.contains(kw)) {
              matched = true;
              break;
            }
          }
        }
        if (!matched) continue;

        final cleaned = _ocrClean(rows[i].textAggressive);
        final p = _findRightmostPrice(cleaned, _priceReg);
        if (p == null) {
          // Toleranslı fiyat regex de dene
          final pLoose = _findRightmostPrice(cleaned, _priceRegLoose);
          if (pLoose != null) {
            final norm = _normPriceLoose(pLoose);
            final amt = double.tryParse(norm) ?? 0;
            if (amt >= 0.10 && amt <= 100000) {
              if (kdv.found && norm == kdv.value) continue;
              if (0.42 > best.confidence) {
                best = _Field(norm, 0.42);
              }
            }
          }
          continue;
        }

        final norm = _normPrice(p);
        if (kdv.found && norm == kdv.value) continue;

        final amt = double.tryParse(norm) ?? 0;
        if (amt < 0.10 || amt > 100000) continue;

        if (0.50 > best.confidence) {
          best = _Field(norm, 0.50);
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // ─── YENİ KATMAN 6: MATEMATİKSEL ÇIKARSAMA ───
    // KDV detayları varsa, en büyük matrah + en büyük KDV toplamı
    // toplam olabilir
    // ═══════════════════════════════════════════════════════════════
    if (best.confidence < 0.45 && kdvDetay.isNotEmpty) {
      double toplamMatrah = 0;
      double toplamKdvHesap = 0;
      bool valid = true;

      for (final item in kdvDetay) {
        final m = double.tryParse(item.matrah.replaceAll(',', '.'));
        final t = double.tryParse(item.tutar.replaceAll(',', '.'));
        if (m == null && t == null) {
          valid = false;
          break;
        }
        toplamMatrah += m ?? 0;
        toplamKdvHesap += t ?? 0;
      }

      if (valid && toplamMatrah > 0 && toplamKdvHesap > 0) {
        final hesaplananToplam = toplamMatrah + toplamKdvHesap;
        if (hesaplananToplam >= 0.10 && hesaplananToplam <= 100000) {
          final norm = hesaplananToplam.toStringAsFixed(2);
          if (0.48 > best.confidence) {
            best = _Field(norm, 0.48);
          }
        }
      }
    }

    if (best.confidence >= 0.42) return best;

    // ─── KATMAN 7: Son çare — alt yarıdaki en büyük tutar ───
    final startIdx = (rows.length * 0.65).round();
    double maxAmt = 0;
    String maxP = '';
    for (int i = startIdx; i < rows.length; i++) {
      final cleaned = _ocrClean(rows[i].text);
      final p = _findRightmostPrice(cleaned, _priceReg);
      if (p == null) continue;
      final norm = _normPrice(p);
      final amt = double.tryParse(norm) ?? 0;

      // KDV ile karıştırma
      if (kdv.found && norm == kdv.value) continue;
      // Çok büyük rakamları atla (vergi no, telefon vb. olabilir)
      if (amt > 100000) continue;

      if (amt > maxAmt) {
        maxAmt = amt;
        maxP = norm;
      }
    }
    if (maxP.isNotEmpty && 0.42 > best.confidence) {
      best = _Field(maxP, 0.42);
    }

    return best;
  }

  // ═══════════════════════════════════════════════════════════════════
  // ÖDEME YÖNTEMİ
  // ═══════════════════════════════════════════════════════════════════
  static _Field _odemeYontemi(List<_Row> rows) {
    for (int i = rows.length - 1; i >= 0; i--) {
      final u = rows[i].upper;
      for (final kw in _paymentKw) {
        if (u.contains(kw)) return _Field(_normOdeme(kw), 0.92);
      }
    }

    // ── YENİ: BURUŞUK FALLBACK ──
    for (int i = rows.length - 1; i >= 0; i--) {
      final uAgg = rows[i].upperAggressive;
      for (final kw in _paymentKw) {
        if (kw.length >= 4 && _fuzzy(uAgg, kw)) {
          return _Field(_normOdeme(kw), 0.65);
        }
      }
    }

    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // PARA ÜSTÜ
  // ═══════════════════════════════════════════════════════════════════
  static _Field _paraUstu(List<_Row> rows) {
    for (int i = rows.length - 1; i >= 0; i--) {
      final u = rows[i].upper;
      if (u.contains('PARA ÜSTÜ') ||
          u.contains('PARA USTU') ||
          u.contains('ÜSTÜ') ||
          u.contains('USTU')) {
        final cleaned = _ocrClean(rows[i].text);
        final p = _findRightmostPrice(cleaned, _priceReg);
        if (p != null) return _Field(_normPrice(p), 0.88);
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // ETTN (e-Arşiv UUID)
  // ═══════════════════════════════════════════════════════════════════
  static _Field _ettn(List<_Row> rows) {
    for (final row in rows) {
      final u = row.upper;
      final cleaned = row.text;
      if (u.contains('ETTN')) {
        final m = _ettnReg.firstMatch(cleaned);
        if (m != null) return _Field(m.group(1)!.toLowerCase(), 0.99);
      }
    }
    for (final row in rows) {
      final m = _ettnReg.firstMatch(row.text);
      if (m != null) return _Field(m.group(1)!.toLowerCase(), 0.92);
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // MERSIS No (16 haneli)
  // ═══════════════════════════════════════════════════════════════════
  static _Field _mersis(List<_Row> rows) {
    for (final row in rows) {
      final cleaned = _ocrClean(row.text);
      final m = _mersisReg.firstMatch(cleaned);
      if (m != null) return _Field(m.group(1)!, 0.96);
    }
    final mersisAltReg = RegExp(r'\b(0\d{15})\b');
    for (final row in rows) {
      final m = mersisAltReg.firstMatch(_ocrClean(row.text));
      if (m != null) return _Field(m.group(1)!, 0.70);
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // IBAN (TR ile başlayan)
  // ═══════════════════════════════════════════════════════════════════
  static _Field _iban(List<_Row> rows) {
    for (final row in rows) {
      final m = _ibanReg.firstMatch(row.text.toUpperCase());
      if (m != null) {
        final clean = m.group(1)!.replaceAll(' ', '');
        if (clean.length == 26) {
          return _Field(clean, 0.95);
        }
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // EKÜ No
  // ═══════════════════════════════════════════════════════════════════
  static _Field _ekuNo(List<_Row> rows) {
    for (final row in rows) {
      final cleaned = _ocrClean(row.text);
      final m = _ekuReg.firstMatch(cleaned);
      if (m != null) {
        final val = m.group(1)!.trim();
        if (val.isNotEmpty) return _Field(val.toUpperCase(), 0.88);
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // ARA TOPLAM
  // ═══════════════════════════════════════════════════════════════════
  static _Field _araToplam(List<_Row> rows) {
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (_araToplamReg.hasMatch(u)) {
        final cleaned = _ocrClean(rows[i].text);
        final p = _findRightmostPrice(cleaned, _priceReg);
        if (p != null) return _Field(_normPrice(p), 0.90);

        if (i + 1 < rows.length) {
          final nextCleaned = _ocrClean(rows[i + 1].text);
          final pn = _findRightmostPrice(nextCleaned, _priceReg);
          if (pn != null) return _Field(_normPrice(pn), 0.75);
        }
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // PARA BİRİMİ
  // ═══════════════════════════════════════════════════════════════════
  static _Field _paraBirimi(List<_Row> rows) {
    for (int i = rows.length - 1; i >= 0; i--) {
      final m = _paraBirimiReg.firstMatch(rows[i].upper);
      if (m != null) {
        String birim = m.group(1)!.toUpperCase();
        if (birim == '₺' || birim.contains('TURK') || birim == 'TRY') {
          birim = 'TL';
        } else if (birim == 'EURO') {
          birim = 'EUR';
        }
        return _Field(birim, 0.92);
      }
    }
    return const _Field('TL', 0.50);
  }

  // ═══════════════════════════════════════════════════════════════════
  // YAKIT FİŞİ DETAYLARI (Pompa, Litre, Tür, Plaka)
  // ═══════════════════════════════════════════════════════════════════
  static Map<String, String?> _yakitDetay(List<_Row> rows) {
    String? turu;
    String? litre;
    String? pompa;
    String? plaka;

    for (final row in rows) {
      final u = row.upper;
      final cleaned = _ocrClean(row.text);

      if (turu == null) {
        final m = _yakitTuruReg.firstMatch(u);
        if (m != null) {
          turu = m
              .group(1)!
              .toUpperCase()
              .replaceAll('MOTORIN', 'Motorin')
              .replaceAll('MOTORİN', 'Motorin')
              .replaceAll('BENZIN', 'Benzin')
              .replaceAll('BENZİN', 'Benzin')
              .replaceAll('DIESEL', 'Dizel')
              .replaceAll('DİZEL', 'Dizel');
        }
      }

      if (litre == null) {
        final m = _litreReg.firstMatch(cleaned);
        if (m != null) {
          litre = '${m.group(1)!.replaceAll('.', ',')} L';
        }
      }

      if (pompa == null) {
        final m = _pompaReg.firstMatch(cleaned);
        if (m != null) pompa = m.group(1)!;
      }

      if (plaka == null) {
        final m = _plakaReg.firstMatch(u);
        if (m != null) {
          plaka = '${m.group(1)!} ${m.group(2)!} ${m.group(3)!}';
        }
      }
    }

    return {'turu': turu, 'litre': litre, 'pompa': pompa, 'plaka': plaka};
  }

  // ═══════════════════════════════════════════════════════════════════
  // TELEFON
  // ═══════════════════════════════════════════════════════════════════
  static _Field _telefon(List<_Row> rows) {
    for (int i = 0; i < rows.length && i < 10; i++) {
      final m = _telefonReg.firstMatch(rows[i].text);
      if (m != null) {
        return _Field(
          m.group(1)!.replaceAll(' ', '').replaceAll('-', ''),
          0.85,
        );
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // KATEGORİ
  // ═══════════════════════════════════════════════════════════════════
  static String _kategori(
    String firmaAdi,
    String odemeYontemi,
    List<_Row> rows,
  ) {
    final plakaReg = RegExp(
      r'\b(0[1-9]|[1-7][0-9]|8[01])\s*[A-ZŞĞÇİÖÜ]{1,3}\s*\d{2,4}\b',
    );
    for (final r in rows) {
      if (plakaReg.hasMatch(r.upper)) {
        return 'Yakıt';
      }
    }

    final oU = odemeYontemi.toUpperCase();
    if (oU.contains('YEMEK') ||
        oU.contains('MULTINET') ||
        oU.contains('SODEXO') ||
        oU.contains('PLUXEE') ||
        oU.contains('TICKET') ||
        oU.contains('SETCARD') ||
        oU.contains('METROPOL') ||
        oU.contains('PAYE')) {
      return 'Yeme-İçme';
    }

    for (final r in rows) {
      if (r.upper.contains('E-REÇETE') ||
          r.upper.contains('İLAÇ') ||
          r.upper.contains('SGK')) {
        return 'Sağlık';
      }
    }

    final u = firmaAdi.toUpperCase();
    for (final entry in _kategoriMap.entries) {
      if (u.contains(entry.key)) return entry.value;
    }

    // ── YENİ: BURUŞUK FALLBACK — fuzzy marka eşleştirme ──
    for (final entry in _kategoriMap.entries) {
      if (entry.key.length >= 5 && _fuzzy(u, entry.key)) {
        return entry.value;
      }
    }

    return 'Diğer';
  }

  // ═══════════════════════════════════════════════════════════════════
  // YARDIMCI: En sağdaki fiyatı bul (string'de)
  // ═══════════════════════════════════════════════════════════════════
  static String? _findRightmostPrice(String text, RegExp reg) {
    final all = reg.allMatches(text).map((m) => m.group(0)!).toList();
    return all.isNotEmpty ? all.last : null;
  }

  // ═══════════════════════════════════════════════════════════════════
  // YARDIMCI: Fiyat normalize
  // ═══════════════════════════════════════════════════════════════════
  static String _normPrice(String raw) {
    return raw
        .replaceAll('*', '')
        .replaceAll(RegExp(r'[^0-9.,]'), '')
        .replaceAll(',', '.');
  }

  // ═══════════════════════════════════════════════════════════════════
  // YENİ: TOLERANSLI FİYAT NORMALİZE (boşluk yerine virgül kabul eder)
  // "119 40" → "119.40"
  // ═══════════════════════════════════════════════════════════════════
  static String _normPriceLoose(String raw) {
    // Önce normal temizlik
    String s = raw.replaceAll('*', '').replaceAll('₺', '').trim();
    // Boşlukları virgülle değiştir (sondan 2 hanenin önündeyse)
    s = s.replaceAllMapped(
      RegExp(r'(\d{1,4})\s+(\d{2})$'),
      (m) => '${m[1]}.${m[2]}',
    );
    // Sonra normal normalize
    return s.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.');
  }

  // ═══════════════════════════════════════════════════════════════════
  // YARDIMCI: Ödeme Normalize
  // ═══════════════════════════════════════════════════════════════════
  static String _normOdeme(String kw) {
    final u = kw.toUpperCase();
    if (u.contains('NAKIT') || u.contains('NAKİT')) return 'Nakit';
    if (u.contains('KREDİ') || u.contains('KREDI')) return 'Kredi Kartı';
    if (u.contains('BANKA')) return 'Banka Kartı';
    if (u.contains('TEMASSIZ')) return 'Temassız';
    if (u.contains('SODEXO') || u.contains('PLUXEE')) return 'Sodexo / Pluxee';
    if (u.contains('MULTINET') || u.contains('MULTİNET')) return 'Multinet';
    if (u.contains('TICKET') || u.contains('TİCKET') || u.contains('EDENRED'))
      return 'Ticket Restaurant';
    if (u.contains('SETCARD')) return 'Setcard';
    if (u.contains('METROPOL')) return 'Metropol Kart';
    if (u.contains('PAYE')) return 'Paye Kart';
    if (u.contains('TOKENFLEX')) return 'TokenFlex';
    if (u.contains('YEMEK KARTI') ||
        u.contains('YEMEK CEKI') ||
        u.contains('YEMEK ÇEKİ')) return 'Yemek Kartı';
    if (u.contains('KART')) return 'Kart';
    if (u.contains('HEDİYE') || u.contains('HEDIYE')) return 'Hediye Çeki';
    if (u.contains('EFT') || u.contains('HAVALE') || u.contains('FAST'))
      return 'EFT/Havale';
    return kw;
  }

  static bool _validDate(String d) {
    try {
      final p = d.split('.');
      if (p.length != 3) return false;
      return int.parse(p[0]) >= 1 &&
          int.parse(p[0]) <= 31 &&
          int.parse(p[1]) >= 1 &&
          int.parse(p[1]) <= 12 &&
          int.parse(p[2]) >= 2000 &&
          int.parse(p[2]) <= 2099;
    } catch (_) {
      return false;
    }
  }

  static bool _anyOf(String src, List<String> kws) =>
      kws.any((kw) => src.contains(kw));

  // ═══════════════════════════════════════════════════════════════════
  // BULANIK EŞLEŞTİRME — GÜÇLENDİRİLDİ (Buruşuk fişler için)
  // Daha esnek, daha toleranslı, daha akıllı
  // ═══════════════════════════════════════════════════════════════════
  static bool _fuzzy(String src, String target) {
    // 1. Direkt içeriyor mu?
    if (src.contains(target)) return true;

    // 2. YENİ: Boşluksuz versiyon kontrol
    // "TOP LAM" → "TOPLAM" eşleşmeli
    final srcNoSpace = src.replaceAll(RegExp(r'\s+'), '');
    final targetNoSpace = target.replaceAll(RegExp(r'\s+'), '');
    if (srcNoSpace.contains(targetNoSpace)) return true;

    // 3. Kelime-kelime Levenshtein
    for (final word in src.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;

      // Uzunluk filtresi (çok farklı uzunluk = farklı kelime)
      if (word.length >= target.length - 2 &&
          word.length <= target.length + 2) {
        // YENİ TOLERANS: Daha akıllı
        // 4 harf veya altı: 1 hata
        // 5-7 harf: 2 hata
        // 8+ harf: 3 hata
        int maxLev;
        if (target.length <= 4) {
          maxLev = 1;
        } else if (target.length <= 7) {
          maxLev = 2;
        } else {
          maxLev = 3;
        }

        if (_lev(word, target) <= maxLev) return true;
      }
    }

    // 4. YENİ: Substring fuzzy
    // Uzun hedeflerde, başı VE sonu eşleşiyorsa muhtemelen aynı kelime
    if (target.length >= 6) {
      // Hedefin yarısı (en az 3 harf) + son 2-3 karakter
      final prefixLen = target.length ~/ 2;
      final prefix = target.substring(0, prefixLen.clamp(3, target.length));
      final suffix = target.substring(target.length - 2);

      if (srcNoSpace.contains(prefix.replaceAll(' ', '')) &&
          srcNoSpace.contains(suffix)) {
        return true;
      }
    }

    // 5. YENİ: KARAKTER SET KARŞILAŞTIRMA
    // Eğer hedef ve kaynak çok benzer karakterler içeriyorsa (sıra önemli değil)
    if (target.length >= 5 && srcNoSpace.length >= target.length) {
      // Hedefin en az %75'i kaynakta var mı?
      final targetChars = target.split('').toSet();
      final srcChars = srcNoSpace.split('').toSet();
      final intersection = targetChars.intersection(srcChars);
      if (intersection.length / targetChars.length >= 0.75) {
        // Ek kontrol: ilk harf de eşleşmeli (yanlış pozitifleri azalt)
        if (srcNoSpace.startsWith(target[0]) ||
            srcNoSpace.contains(' ${target[0]}') ||
            srcNoSpace.contains(target.substring(0, 2))) {
          // Bu çok agresif — sadece çok uzun hedefler için (8+)
          if (target.length >= 8) return true;
        }
      }
    }

    return false;
  }

  // ═══════════════════════════════════════════════════════════════════
  // LEVENSHTEIN MESAFESİ
  // ═══════════════════════════════════════════════════════════════════
  static int _lev(String a, String b) {
    var v0 = List<int>.generate(b.length + 1, (i) => i);
    var v1 = List<int>.filled(b.length + 1, 0);
    for (int i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      v0 = List.from(v1);
    }
    return v0[b.length];
  }
}
