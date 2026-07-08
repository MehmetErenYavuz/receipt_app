import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_app/models/receipt_data.dart';
import 'package:receipt_app/models/kdv_item.dart';
import 'package:receipt_app/extensions/string_extensions.dart';
import 'package:receipt_app/utils/smart_word_corrector.dart';

// ═══════════════════════════════════════════════════════════════════════
// YARDIMCI: OCR elemanı soyutlaması (ML Kit TextElement VEYA sentetik kayıt)
// ═══════════════════════════════════════════════════════════════════════
// `_buildRows` mantığı bu soyutlama üzerinden çalışır; böylece hem canlı ML
// Kit çıktısı hem de test/golden harness kayıtları AYNI satır-sıralamasını
// üretir. `order` = akış (json nested) sırası → kararlı tie-break için.
class _El {
  final String text;
  final double left;
  final double top;
  final double height;
  final int order; // akış sırası (json_index) — tie-break ikincil anahtarı

  const _El(this.text, this.left, this.top, this.height, this.order);

  double get yCenter => top + height / 2;
}

// ═══════════════════════════════════════════════════════════════════════
// YARDIMCI: Koordinat Tabanlı Satır
// ═══════════════════════════════════════════════════════════════════════
class _Row {
  double yCenter;
  final List<_El> elements;

  _Row(this.yCenter, this.elements);

  String get text {
    final raw = elements.map((e) => e.text).join(' ');
    String cleaned = raw.fixOcrConfusion;

    if (RegExp(r'\d').hasMatch(cleaned)) {
      cleaned = cleaned.fixPriceContext;
    }

    return cleaned;
  }

  String get upper => text.toUpperCase();

  String get textAggressive {
    final raw = elements.map((e) => e.text).join(' ');
    return raw.crumpledOcrClean;
  }

  String get upperAggressive => textAggressive.toUpperCase();

  List<String> allPrices(RegExp reg) =>
      reg.allMatches(text).map((m) => m.group(0)!).toList();

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
// GLOBAL OCR DÜZELTME FONKSİYONU — GÜÇLENDİRİLMİŞ
// ═══════════════════════════════════════════════════════════════════════
String _ocrClean(String raw) {
  String s = raw;

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

  for (int i = 0; i < 2; i++) {
    s = s.replaceAllMapped(
      RegExp(r'(\d)([OoIlBSGZqQ])(\d)'),
      (m) {
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
      },
    );
  }

  s = s.replaceAllMapped(
    RegExp(r'(\d{1,4})\s+(\d{2})(?=\s*(?:TL|₺|$|\n))', caseSensitive: false),
    (m) => '${m[1]},${m[2]}',
  );

  s = s.replaceAllMapped(
    RegExp(r'(\d{1,4})\.(\d{2})(?!\d)'),
    (m) => '${m[1]},${m[2]}',
  );

  return s;
}

// ═══════════════════════════════════════════════════════════════════════
// ANA PARSER (TÜRKİYE FİŞ YAPILARINA %100 UYUMLU)
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

  static const List<String> _totalKwLoose = [
    'TOPLA',
    'OPLAM',
    'TPLAM',
    'TOLAM',
    'TOPM',
    'TOPL',
    'OPLA',
    'ENEL TOP',
    'G TOP',
    'GTOP',
    'GNL TOP',
    'EDENEK',
    'DENECEK',
    'ODENEN',
    'ODENECEK',
    'TAHS',
  ];

  // GENEL TOPLAM belirteçleri (en yüksek öncelik): bunlar belgenin NİHAİ
  // (KDV dahil) toplamıdır → "MAL HİZMET TOPLAM"/"ARA TOPLAM" gibi alt-toplamları
  // ve genel "TUTAR"ı yener. "KDV DAHİL/VERGİLER DAHİL" = toplam (KDV değil).
  static const List<String> _grandTotalKw = [
    'GENEL TOPLAM',
    'G.TOPLAM',
    'GENEL TOP',
    'GNL TOPLAM',
    'VERGILER DAHIL',
    'VERGİLER DAHİL',
    'KDV DAHIL TOPLAM',
    'KDV DAHİL TOPLAM',
    'KDV DAHIL',
    'KDV DAHİL',
    'ODENECEK TUTAR',
    'ÖDENECEK TUTAR',
    'ODENECEK',
    'ÖDENECEK',
    'TAHSIL',
    'TAHSİL',
    'TOPLAM TUTAR',
  ];

  // KDV ararken kullanılacak kesin belirteçler
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
    'TURKUVAZ': 'Yakıt',
    'AYTEMİZ': 'Yakıt',
    'AYTEMIZ': 'Yakıt',
    'TP AKARYAKIT': 'Yakıt',
    'PETROL OFISI': 'Yakıt',
    'PETROL OFİSİ': 'Yakıt',
    'POAS': 'Yakıt',
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
    'ECZ.': 'Sağlık',
    'MEDİKAL': 'Sağlık',
    'MEDIKAL': 'Sağlık',
    'POLİKLİNİK': 'Sağlık',
    'POLIKLINIK': 'Sağlık',
    'LABORATUVAR': 'Sağlık',
    'BIM TEKNO': 'Elektronik',
    'GOLD BILGISAYAR': 'Elektronik',
    'GOLD BİLGİSAYAR': 'Elektronik',
    'TURKCELL ILETISIM': 'Elektronik',
    'TÜRKCELL İLETİŞİM': 'Elektronik',
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
  // GÜÇLENDİRİLMİŞ REGEX'LER (Yıldız (*) işaretlerini akıllıca yönetir)
  // ═══════════════════════════════════════════════════════════════════

  // FİYAT REGEX: BİM ve A101 gibi marketlerdeki "1.250,50 *" veya "* 15,00" formatını yakalar.
  // Tamsayı kısmı: YA gruplu binlik (1.234, 12.345) YA DA düz hane dizisi (1234) — böylece
  // binlik-ayraçsız 1000+ tutarlar (1234,56) "234,56" diye kesilmez. Gruplu alt ÖNCE denenir.
  static final RegExp _priceReg = RegExp(
    r'\*?\s*(?:\d{1,3}(?:[.\s]\d{3})+|\d+)[.,]\d{2}\s*\*?(?!\d)',
  );

  static final RegExp _numOnlyReg = RegExp(
    r'(?:\d{1,3}(?:[.\s]\d{3})+|\d+)[.,]\d{2}(?!\d)',
  );

  static final RegExp _priceRegLoose = RegExp(
    r'\*?\s*\d{1,4}[\s.,]\d{2}\s*\*?(?!\d)',
  );

  static final RegExp _ettnReg = RegExp(
      r'\b([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\b');
  static final RegExp _mersisReg =
      RegExp(r'MERS[İI]S\s*(?:NO)?[\s:.-]*(\d{16})', caseSensitive: false);
  static final RegExp _ibanReg =
      RegExp(r'\b(TR\d{2}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{2})\b');
  static final RegExp _ekuReg = RegExp(
      r'\bEK[ÜU]\s*(?:NO|N0)?[\s:.-]*([A-Z]{0,3}\s?\d{6,12})',
      caseSensitive: false);
  static final RegExp _pompaReg =
      RegExp(r'POMPA\s*(?:NO)?[\s:.-]*(\d+)', caseSensitive: false);
  static final RegExp _litreReg =
      RegExp(r'(\d+[.,]\d{1,3})\s*(?:LT|LİT|LITRE|L)\b', caseSensitive: false);
  static final RegExp _yakitTuruReg = RegExp(
      r'\b(MOTORIN|MOTORİN|BENZIN|BENZİN|LPG|95\s*OKTAN|97\s*OKTAN|DIESEL|DİZEL|EUROD[İI]ESEL|V/MAX|VMAX|ULTRAFORCE)\b',
      caseSensitive: false);
  static final RegExp _plakaReg =
      RegExp(r'\b(0[1-9]|[1-7][0-9]|8[01])\s?([A-ZŞĞÇİÖÜ]{1,3})\s?(\d{2,4})\b');
  static final RegExp _okcSeriReg = RegExp(r'\b([A-Z]{2}\s?\d{8})\b');
  static final RegExp _eArsivReg = RegExp(r'\b([A-Z]{3}20\d{11})\b');
  static final RegExp _paraBirimiReg = RegExp(
      r'\b(TL|TRY|₺|TURK\s*LIRASI|TÜRK\s*LİRASI|USD|EUR|EURO|GBP)\b',
      caseSensitive: false);
  static final RegExp _araToplamReg =
      RegExp(r'\bARA\s*TOP(?:LAM)?\b', caseSensitive: false);
  // Fatura toplamı: "FAT.TOP", "FAT . TOP.", "FAT TOP", "FATURA TOP(LAM)" → NİHAİ toplam.
  static final RegExp _faturaTopReg =
      RegExp(r'\bFAT(?:URA)?\s*\.?\s*TOP', caseSensitive: false);
  static final RegExp _telefonReg =
      RegExp(r'\b(0\d{3}[\s-]?\d{3}[\s-]?\d{2}[\s-]?\d{2})\b');

  // ═══════════════════════════════════════════════════════════════════
  // ANA GİRİŞ NOKTASI
  // ═══════════════════════════════════════════════════════════════════
  static ReceiptData parse(RecognizedText ocr) {
    final rows = _buildRows(ocr);
    if (rows.isEmpty) return ReceiptData(uyari: 'Metin okunamadı.');
    return _parseRows(rows);
  }

  // ── ML Kit'siz giriş: sentetik OCR elemanlarından tam parse (test/golden) ──
  static ReceiptData parseFromElements(
      List<({String text, double x, double y, double w, double h})> els) {
    final rows = _rowsFromElements(els);
    if (rows.isEmpty) return ReceiptData(uyari: 'Metin okunamadı.');
    return _parseRows(rows);
  }

  static ReceiptData _parseRows(List<_Row> rows) {
    final bool muhtemelenBurusuk = _isCrumpled(rows);
    final bool isIptal = rows.any((r) =>
        r.upper.contains('İPTAL') ||
        r.upper.contains('IPTAL') ||
        r.upper.contains('İADE FİŞİ') ||
        r.upper.contains('IADE FISI'));
    final bool maliDegeriYok = rows.any((r) =>
        r.upper.contains('MALİ DEĞERİ YOKTUR') ||
        r.upper.contains('MALI DEGERI YOKTUR'));
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

    // İşlem Sırası Çok Önemli: Önce KDV bulunur, sonra Matrah bulunur, en son Toplam bulunur.
    final topKdv = _toplamKdv(rows, kdvDetay);
    final matrah = _matrah(rows);
    final toplam = _toplam(rows, topKdv, isBankaDekontu, muhtemelenBurusuk);

    final odeme = _odemeYontemi(rows);
    final paraUstu = _paraUstu(rows);
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

    if (muhtemelenBurusuk && uyari == null) {
      uyari =
          'Bu fiş buruşuk veya zor okunan bir görüntüden tarandı. Lütfen tüm alanları kontrol edin.';
    } else if (muhtemelenBurusuk &&
        uyari != null &&
        !uyari.contains('buruşuk')) {
      uyari =
          uyari + '\nNot: Fiş buruşuk olarak algılandı, alanları kontrol edin.';
    }

    // ── TUTAR UZLAŞTIRMA (matrah ↔ KDV ↔ toplam çapraz doğrulama) ──
    // para üstü / swap / KDV türetme / %30 sanity / 820 koruması / ₺ OCR düzeltmesi.
    final odemeTutar = _paymentAmounts(rows);
    final bool isEarsivBelge =
        belge.value.toLowerCase().contains('arşiv') || ettn.found;

    final recon = _reconcileAmounts(
      matrah: double.tryParse(matrah.value) ?? 0,
      kdv: double.tryParse(topKdv.value) ?? 0,
      toplam: double.tryParse(toplam.value) ?? 0,
      cashTendered: odemeTutar['nakit']!,
      cardPaid: odemeTutar['kart']!,
      change: double.tryParse(paraUstu.value) ?? 0,
      singleRate: _detectSingleVatRate(rows),
      totalReliable: toplam.found && toplam.confidence >= 0.85,
      isEarsiv: isEarsivBelge,
      detay: kdvDetay,
      isIptal: isIptal,
    );

    String finalToplamKdv = recon.kdv;
    String finalToplamTutar = toplam.found ? recon.toplam : toplam.value;
    for (final w in recon.warnings) {
      uyari = (uyari == null || uyari.isEmpty) ? w : '$uyari\n$w';
    }

    // KDV kırılımı sanity: bir oranın KDV tutarı genel toplama yakın/üstündeyse
    // bu Genel Toplam sızıntısıdır (gerçek KDV her zaman toplamdan küçüktür) → at.
    final double finalTotalVal = double.tryParse(finalToplamTutar) ?? 0;
    if (finalTotalVal > 0) {
      kdvDetay.removeWhere(
          (i) => (double.tryParse(i.tutar) ?? 0) >= finalTotalVal * 0.95);
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
      kdvHaricToplam: recon.matrah.isNotEmpty ? recon.matrah : matrah.value,
      araToplam: araToplam.value,
      toplamTutar: finalToplamTutar,
      odemeYontemi: odeme.value,
      paraUstu: paraUstu.value,
      paraBirimi: paraBirimi.value.isEmpty ? 'TL' : paraBirimi.value,
      nakitTutar: odemeTutar['nakit']! > 0
          ? odemeTutar['nakit']!.toStringAsFixed(2)
          : '',
      kartTutar:
          odemeTutar['kart']! > 0 ? odemeTutar['kart']!.toStringAsFixed(2) : '',
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

  static bool _isCrumpled(List<_Row> rows) {
    int bozukKarakterSayisi = 0;
    int tekKarakterliSatir = 0;
    int toplamKarakter = 0;
    final bozukReg = RegExp(r'[Н^~`{}\\<>¬§|]');
    for (final row in rows) {
      final t = row.text;
      toplamKarakter += t.length;
      bozukKarakterSayisi += bozukReg.allMatches(t).length;
      if (t.trim().length <= 1) tekKarakterliSatir++;
    }
    if (toplamKarakter == 0) return false;
    final bozukOran = bozukKarakterSayisi / toplamKarakter;
    final tekOran = tekKarakterliSatir / rows.length;
    if (bozukOran > 0.03) return true;
    if (rows.length < 5 && toplamKarakter > 50) return true;
    if (tekOran > 0.2) return true;
    return false;
  }

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

  // ── ML Kit / kayıt → _El listesi (akış sırası, boş elemanlar atlanır) ──
  static List<_El> _elsFromOcr(RecognizedText ocr) {
    final els = <_El>[];
    int order = 0;
    for (final block in ocr.blocks) {
      for (final line in block.lines) {
        for (final el in line.elements) {
          if (el.text.trim().isEmpty) continue;
          final bb = el.boundingBox;
          els.add(_El(el.text, bb.left.toDouble(), bb.top.toDouble(),
              bb.height.toDouble(), order++));
        }
      }
    }
    return els;
  }

  static List<_El> _elsFromRecords(
      List<({String text, double x, double y, double w, double h})> recs) {
    final els = <_El>[];
    int order = 0;
    for (final r in recs) {
      if (r.text.trim().isEmpty) continue;
      els.add(_El(r.text, r.x, r.y, r.h, order++));
    }
    return els;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SATIR GRUPLAMA — greedy birleştirme (her iki yolda da AYNI gruplama)
  // ═══════════════════════════════════════════════════════════════════════
  static List<_Row> _greedyGroup(List<_El> els) {
    final rows = <_Row>[];
    for (final el in els) {
      final yc = el.yCenter;
      final tol = (el.height * 0.65).clamp(8.0, 28.0);
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
    return rows;
  }

  // CANLI regex parser yolu — ORİJİNAL davranış (Dart List.sort, kararsız).
  // DEĞİŞTİRİLMEDİ: regex katmanı bu sıraya göre ayarlandı.
  static List<_Row> _buildRows(RecognizedText ocr) {
    final rows = _greedyGroup(_elsFromOcr(ocr));
    rows.sort((a, b) => a.yCenter.compareTo(b.yCenter));
    for (final r in rows) {
      r.elements.sort((a, b) => a.left.compareTo(b.left));
    }
    return rows;
  }

  // MODEL + golden harness yolu — KARARLI tie-break (input_contract §1.8).
  // Satır sırası (yCenter, satır_oluşturma_index); satır-içi (left, json_index).
  // Parite testinde (diff=0) kanıtlanan sıralama BUDUR.
  static List<_Row> _groupRowsDeterministic(List<_El> els) {
    final rows = _greedyGroup(els);
    final indexed = [
      for (int i = 0; i < rows.length; i++) (row: rows[i], created: i)
    ];
    indexed.sort((a, b) {
      final c = a.row.yCenter.compareTo(b.row.yCenter);
      return c != 0 ? c : a.created.compareTo(b.created);
    });
    final ordered = [for (final p in indexed) p.row];
    for (final r in ordered) {
      r.elements.sort((a, b) {
        final c = a.left.compareTo(b.left);
        return c != 0 ? c : a.order.compareTo(b.order);
      });
    }
    return ordered;
  }

  static List<_Row> _rowsFromElements(
          List<({String text, double x, double y, double w, double h})> recs) =>
      _groupRowsDeterministic(_elsFromRecords(recs));

  // ── MODEL GİRDİSİ: HAM token sırası (OCR düzeltmesi YOK) — input_contract ──
  // Modele giden "kelime" listesi = bu fonksiyonun çıktısı (prefix hariç).
  // Kararlı tie-break kullanır (eğitim girdisiyle parite).
  static List<String> rawTokenOrder(RecognizedText ocr) {
    final rows = _groupRowsDeterministic(_elsFromOcr(ocr));
    return [
      for (final r in rows)
        for (final e in r.elements) e.text
    ];
  }

  // ── GOLDEN HARNESS: okuma sırası dökümü (dart_order.json) ──
  static List<Map<String, dynamic>> orderFromElements(
      List<({String text, double x, double y, double w, double h})> recs) {
    final rows = _rowsFromElements(recs);
    return [
      for (int i = 0; i < rows.length; i++)
        {
          'index': i,
          'y_center': (rows[i].yCenter * 100).round() / 100,
          'tokens': [for (final e in rows[i].elements) e.text],
          'text': rows[i].elements.map((e) => e.text).join(' '),
        }
    ];
  }

  static _Field _firma(List<_Row> rows) {
    _Field bestField = _Field.empty;
    double maxScore = 0.0;
    for (int i = 0; i < rows.length && i < 6; i++) {
      final rawText = rows[i].text.trim();
      final t = SmartWordCorrector.correctSentence(rawText);
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
      if (rawText != t) score += 0.15;
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
        final smartText = SmartWordCorrector.correctSentence(rows[i].text);
        final smartUpper = smartText.toUpperCase();
        for (String brand in _kategoriMap.keys) {
          if (rows[i].upper.contains(brand) || smartUpper.contains(brand))
            return _Field(smartText, 0.85);
        }
      }
    }
    if (bestField.value.isEmpty || maxScore < 0.20) {
      for (int i = 0; i < rows.length && i < 6; i++) {
        final uAgg = rows[i].upperAggressive;
        for (String brand in _kategoriMap.keys) {
          if (_fuzzy(uAgg, brand)) {
            final corrected = SmartWordCorrector.correctSentence(rows[i].text);
            return _Field(corrected, 0.65);
          }
        }
      }
    }
    return bestField;
  }

  static _Field _adres(List<_Row> rows) {
    final adresKw = RegExp(
        r'\b(CAD\.?|CADDE|SOK\.?|SOKAK|MAH\.?|MAHALLE|BULVAR|BLV\.?|NO:?|APT\.?|MH\.?)\b',
        caseSensitive: false);
    for (int i = 1; i < rows.length && i < 12; i++) {
      if (adresKw.hasMatch(rows[i].text))
        return _Field(rows[i].text.trim(), 0.82);
    }
    return _Field.empty;
  }

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
                '')
            .replaceAll(RegExp(r'\bV\.?D\.?\b', caseSensitive: false), '')
            .replaceAll(RegExp(r'\b\d{10,11}\b'), '')
            .replaceAll(RegExp(r'VKN|TCKN|NO|:', caseSensitive: false), '')
            .trim();
        if (cleaned.length < 3 && i > 0) cleaned = rows[i - 1].text.trim();
        if (cleaned.length > 2) return _Field(cleaned, 0.92);
      }
    }
    return _Field.empty;
  }

  // ── VKN/TCKN checksum (GİB/MERNIS algoritmaları; NerPostprocess ile aynı) ──
  static bool _vknValid(String n) {
    if (!RegExp(r'^\d{10}$').hasMatch(n)) return false;
    final d = n.split('').map(int.parse).toList();
    int total = 0;
    for (int i = 0; i < 9; i++) {
      final tmp = (d[i] + (9 - i)) % 10;
      if (tmp != 0) {
        var v = (tmp * pow(2, 9 - i).toInt()) % 9;
        if (v == 0) v = 9;
        total += v;
      }
    }
    return (10 - (total % 10)) % 10 == d[9];
  }

  static bool _tcknValid(String n) {
    if (!RegExp(r'^\d{11}$').hasMatch(n) || n[0] == '0') return false;
    final d = n.split('').map(int.parse).toList();
    final d10 = ((((d[0] + d[2] + d[4] + d[6] + d[8]) * 7 -
                    (d[1] + d[3] + d[5] + d[7])) %
                10) +
            10) %
        10;
    final d11 = d.sublist(0, 10).reduce((a, b) => a + b) % 10;
    return d[9] == d10 && d[10] == d11;
  }

  static bool _taxIdValid(String n) =>
      (n.length == 10 && _vknValid(n)) || (n.length == 11 && _tcknValid(n));

  // OCR'da sık karışan haneler (baskı/7-segment). VKN/TCKN checksum-onarımında
  // YALNIZ tek hane değiştirilir; sonuç checksum'dan geçmek zorunda (güvenli).
  static const Map<String, List<String>> _ocrDigitConfusions = {
    '0': ['8', '6', '9'],
    '1': ['7'],
    '2': ['7'],
    '3': ['8', '9'],
    '5': ['6', '8'],
    '6': ['5', '8', '0'],
    '7': ['1', '2'],
    '8': ['6', '0', '3', '9'],
    '9': ['4', '0', '8'],
  };

  /// Tek-haneli OCR karışmasını düzeltip checksum-geçen BENZERSİZ varyantı döner;
  /// belirsizse (0 veya >1 geçerli varyant) null.
  static String? _repairTaxId(String n) {
    if (n.length != 10 && n.length != 11) return null;
    final valid = <String>{};
    for (int i = 0; i < n.length; i++) {
      for (final alt in _ocrDigitConfusions[n[i]] ?? const <String>[]) {
        final v = n.substring(0, i) + alt + n.substring(i + 1);
        if (_taxIdValid(v)) valid.add(v);
      }
    }
    return valid.length == 1 ? valid.first : null;
  }

  static _Field _vergiNo(List<_Row> rows) {
    final reg = RegExp(r'\b([1-9]\d{9,10})\b');

    // ── ÖNCELİK: checksum geçen aday (sahte 10-11 haneyi eler). Etiketli
    //    (VD/VKN/TCKN) satırdaki geçerli aday, etiketsiz geçerliye tercih edilir.
    String? validLabeled, validAny;
    final labeledCands = <String>[]; // checksum-onarımı için (geçersizler dahil)
    for (int i = 0; i < rows.length; i++) {
      final rowText = _ocrClean(rows[i].text);
      final u = rows[i].upper;
      if (RegExp(r'\b\d{16}\b').hasMatch(rowText)) continue;
      if (RegExp(r'\b\d{2}[./-]\d{2}[./-]\d{4}\b').hasMatch(rowText)) continue;
      if (u.contains('ETTN') || u.contains('IBAN')) continue;
      final labeled = u.contains('VKN') ||
          u.contains('VD') ||
          u.contains('V.D') ||
          u.contains('TC ') ||
          u.contains('TCKN') ||
          u.contains('VERGI NO') ||
          u.contains('VERGİ NO');
      for (final m in reg.allMatches(rowText)) {
        final num = m.group(1)!;
        if (num.length != 10 && num.length != 11) continue;
        if (_taxIdValid(num)) {
          validAny ??= num;
          if (labeled) validLabeled ??= num;
        } else if (labeled) {
          labeledCands.add(num);
        }
      }
    }
    if (validLabeled != null) return _Field(validLabeled, 0.99);
    // checksum geçen yok ama etiketli aday OCR ile bozulmuş olabilir → onar.
    if (validAny == null) {
      for (final cand in labeledCands) {
        final fixed = _repairTaxId(cand);
        if (fixed != null) return _Field(fixed, 0.90);
      }
    }
    if (validAny != null) return _Field(validAny, 0.97);

    // ── checksum geçen yoksa: best-effort tier mantığı (geri uyumlu) ──
    for (int i = 0; i < rows.length; i++) {
      final rowText = _ocrClean(rows[i].text);
      final u = rows[i].upper;
      if (RegExp(r'\b\d{16}\b').hasMatch(rowText)) continue;
      if (RegExp(r'\b\d{2}[./-]\d{2}[./-]\d{4}\b').hasMatch(rowText)) continue;
      if (u.contains('FIS') ||
          u.contains('Z NO') ||
          u.contains('ETTN') ||
          u.contains('IBAN') ||
          u.contains('TR')) continue;

      final labeled = u.contains('VKN') ||
          u.contains('VD') ||
          u.contains('V.D') ||
          u.contains('TC ') ||
          u.contains('TCKN') ||
          u.contains('VERGI NO') ||
          u.contains('VERGİ NO');
      if (labeled) {
        final m = reg.firstMatch(rowText);
        if (m != null) {
          final num = m.group(1)!;
          if (num.length == 10 || num.length == 11) return _Field(num, 0.99);
        }
      }
    }
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (u.contains('V.D') || u.endsWith(' VD') || u.endsWith(' VD.')) {
        final cleanedSame = _ocrClean(rows[i].text);
        final mSame = reg.firstMatch(cleanedSame);
        if (mSame != null &&
            (mSame.group(1)!.length == 10 || mSame.group(1)!.length == 11))
          return _Field(mSame.group(1)!, 0.96);
        for (int j = i + 1; j <= i + 2 && j < rows.length; j++) {
          final cleaned = _ocrClean(rows[j].text);
          final m = reg.firstMatch(cleaned);
          if (m != null &&
              (m.group(1)!.length == 10 || m.group(1)!.length == 11))
            return _Field(m.group(1)!, 0.92);
        }
      }
    }
    for (int i = 0; i < rows.length; i++) {
      final rowText = _ocrClean(rows[i].text);
      final u = rows[i].upper;
      if (RegExp(r'\b\d{16}\b').hasMatch(rowText) ||
          RegExp(r'\b\d{2}[./-]\d{2}[./-]\d{4}\b').hasMatch(rowText) ||
          u.contains('FIS') ||
          u.contains('Z NO') ||
          u.contains('IBAN') ||
          u.contains('ETTN') ||
          u.contains('TELEFON') ||
          u.contains('TEL')) continue;
      final m = reg.firstMatch(rowText);
      if (m != null && (m.group(1)!.length == 10 || m.group(1)!.length == 11))
        return _Field(m.group(1)!, 0.80);
    }
    for (int i = 0; i < rows.length; i++) {
      final rowText = _ocrClean(rows[i].textAggressive);
      final m = reg.firstMatch(rowText);
      if (m != null && (m.group(1)!.length == 10 || m.group(1)!.length == 11))
        return _Field(m.group(1)!, 0.55);
    }
    return _Field.empty;
  }

  static _Field _belgeTuru(
      List<_Row> rows, bool maliDegeriYok, bool isBankaDekontu) {
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

  static _Field _fisNo(List<_Row> rows) {
    final fisReg = RegExp(
        r'\b(?:F[Iİıi]S|F[Iİıi][SŞşs]|BELGE|ORD|F)\s*(?:NO)?\s*[:.\-]?\s*(\d{2,8})\b',
        caseSensitive: false);
    final eArsivReg = RegExp(r'\b([A-Z]{3}20\d{11})\b', caseSensitive: false);
    final faturaNoReg = RegExp(
        r'\b(?:FATURA\s*NO|FAT\s*NO)\s*[:.\-]?\s*([A-Z0-9]{3,20})\b',
        caseSensitive: false);

    for (int i = 0; i < rows.length; i++) {
      final cleaned = _ocrClean(rows[i].text);
      final eMatch = eArsivReg.firstMatch(cleaned);
      if (eMatch != null) return _Field(eMatch.group(1)!.toUpperCase(), 0.99);
      final fMatch = faturaNoReg.firstMatch(cleaned);
      if (fMatch != null && fMatch.group(1)!.trim().length >= 3)
        return _Field(fMatch.group(1)!.toUpperCase(), 0.96);
      final m = fisReg.firstMatch(cleaned);
      if (m != null) {
        final val = m.group(1)!.replaceAll(RegExp(r'^0+'), '');
        if (val.isNotEmpty) return _Field(val, 0.95);
      }
    }
    for (int i = 0; i < rows.length; i++) {
      final aggCleaned = _ocrClean(rows[i].textAggressive);
      final m = fisReg.firstMatch(aggCleaned);
      if (m != null) {
        final val = m.group(1)!.replaceAll(RegExp(r'^0+'), '');
        if (val.isNotEmpty) return _Field(val, 0.70);
      }
    }
    return _Field.empty;
  }

  static _Field _seriNo(List<_Row> rows) {
    final seriReg = RegExp(
        r'\bSER[Iİıi]\s*(?:\/\s*SIRA\s*)?(?:NO\s*)?[:.\-]?\s*([A-Za-z]{1,3})\b');
    for (int i = 0; i < rows.length && i < 15; i++) {
      final m = seriReg.firstMatch(rows[i].text);
      if (m != null) return _Field(m.group(1)!.trim().toUpperCase(), 0.90);
    }
    return _Field.empty;
  }

  static _Field _zNo(List<_Row> rows) {
    final zReg =
        RegExp(r'\bZ\s*(?:NO\s*)?[:\-]?\s*(\d{3,6})\b', caseSensitive: false);
    for (int i = 0; i < rows.length; i++) {
      final m = zReg.firstMatch(rows[i].text);
      if (m != null) return _Field(m.group(1)!, 0.88);
    }
    return _Field.empty;
  }

  static _Field _tarih(List<_Row> rows) {
    final dateReg = RegExp(
        r'(0?[1-9]|[12][0-9]|3[01])[\s.\-\/,:;]+(0?[1-9]|1[012])[\s.\-\/,:;]+(20[1-3][0-9]|[1-2][0-9])');
    final isoDateReg = RegExp(
        r'(20[1-3][0-9])[-/](0[1-9]|1[012])[-/](0[1-9]|[12][0-9]|3[01])');
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
      'ARA': '12'
    };
    final writtenDateReg = RegExp(
        r'(\d{1,2})\s+(OCAK|OCA|ŞUBAT|SUBAT|ŞUB|SUB|MART|MAR|NİSAN|NISAN|NIS|MAYIS|MAY|HAZİRAN|HAZIRAN|HAZ|TEMMUZ|TEM|AĞUSTOS|AGUSTOS|AGU|EYLÜL|EYLUL|EYL|EKİM|EKIM|EKI|KASIM|KAS|ARALIK|ARA)\s+(20\d{2})',
        caseSensitive: false);
    final dateNoSepReg =
        RegExp(r'\b(0[1-9]|[12][0-9]|3[01])(0[1-9]|1[012])(20[1-3][0-9])\b');
    final dateShortReg =
        RegExp(r'\b(0[1-9]|[12][0-9]|3[01])(0[1-9]|1[012])(2[0-9])\b');

    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      String cleaned = _ocrClean(rows[i].text);
      final isoMatch = isoDateReg.firstMatch(cleaned);
      if (isoMatch != null) {
        String raw =
            '${isoMatch.group(3)!}.${isoMatch.group(2)!}.${isoMatch.group(1)!}';
        if (_validDate(raw)) return _Field(raw, 0.98);
      }
      final writtenMatch = writtenDateReg.firstMatch(u);
      if (writtenMatch != null) {
        String gun = writtenMatch.group(1)!.padLeft(2, '0');
        String ay = monthMap[writtenMatch.group(2)!.toUpperCase()] ?? '00';
        String yil = writtenMatch.group(3)!;
        String raw = '$gun.$ay.$yil';
        if (_validDate(raw)) return _Field(raw, 0.95);
      }
      String noSpaces = cleaned.replaceAll(' ', '');
      Match? m = dateReg.firstMatch(noSpaces);
      if (m == null) m = dateReg.firstMatch(cleaned);
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
    for (int i = 0; i < rows.length; i++) {
      String cleaned = _ocrClean(rows[i].text);
      final mLong = dateNoSepReg.firstMatch(cleaned);
      if (mLong != null) {
        String raw = '${mLong.group(1)}.${mLong.group(2)}.${mLong.group(3)}';
        if (_validDate(raw)) return _Field(raw, 0.70);
      }
      final mShort = dateShortReg.firstMatch(cleaned);
      if (mShort != null) {
        String raw =
            '${mShort.group(1)}.${mShort.group(2)}.20${mShort.group(3)}';
        if (_validDate(raw)) return _Field(raw, 0.65);
      }
    }
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

  static _Field _saat(List<_Row> rows) {
    final timeReg =
        RegExp(r'\b([01]?\d|2[0-3])[:;]([0-5]\d)(?:[:;][0-5]\d)?\b');
    for (int i = 0; i < rows.length; i++) {
      final cleaned = _ocrClean(rows[i].text);
      final m = timeReg.firstMatch(cleaned);
      if (m == null) continue;
      final h = int.tryParse(m.group(1)!) ?? -1;
      final min = int.tryParse(m.group(2)!) ?? -1;
      if (h >= 0 && h <= 23 && min >= 0 && min <= 59) {
        return _Field(
            '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}',
            0.96);
      }
    }
    final timeNoSepReg = RegExp(r'\b([01]\d|2[0-3])([0-5]\d)\b');
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (!u.contains('SAAT') && !u.contains('TAR')) continue;
      final cleaned = _ocrClean(rows[i].text);
      final m = timeNoSepReg.firstMatch(cleaned);
      if (m != null) {
        final h = int.tryParse(m.group(1)!) ?? -1;
        final min = int.tryParse(m.group(2)!) ?? -1;
        if (h >= 0 && h <= 23 && min >= 0 && min <= 59) {
          return _Field(
              '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}',
              0.65);
        }
      }
    }
    return _Field.empty;
  }

  static List<KdvItem> _kdvDetay(List<_Row> rows) {
    final items = <KdvItem>[];
    final foundOranlar = <String>{};
    final oranFiyatReg = RegExp(r'%\s*(1|8|10|18|20)\b');
    final oranFiyatLooseReg =
        RegExp(r'(?:KDV|VAT)\s+(1|8|10|18|20)\b', caseSensitive: false);
    final tableSatirReg = RegExp(
        r'%\s*(1|8|10|18|20)\s+([\d.,]+)\s+\*?([\d.,]+)(?:\s+\*?([\d.,]+))?');

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
          items.add(KdvItem(
              oran: '%$oran',
              matrah: _normPrice(m2.group(2)!),
              tutar: _normPrice(m2.group(3)!)));
        }
        continue;
      }

      Iterable<RegExpMatch> oranMatches = oranFiyatReg.allMatches(cleaned);
      if (oranMatches.isEmpty)
        oranMatches = oranFiyatLooseReg.allMatches(cleaned);

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
          items.add(KdvItem(
              oran: '%$oran',
              matrah: matrahFiyat != null ? _normPrice(matrahFiyat) : '',
              tutar: kdvFiyat != null
                  ? _normPrice(kdvFiyat)
                  : _normPrice(matrahFiyat ?? '')));
        } else if (idx + 1 < rows.length) {
          // Alt satır bir TOPLAM/ödeme satırıysa fiyatını KDV sanma (sızıntı önleme).
          final nu = rows[idx + 1].upper;
          final nextIsTotalish = nu.contains('TOPLAM') ||
              nu.contains('ÖDE') ||
              nu.contains('ODE') ||
              _anyOf(nu, _paymentKw);
          if (!nextIsTotalish) {
            final nextPrices = rows[idx + 1].allPrices(_priceReg);
            if (nextPrices.isNotEmpty) {
              foundOranlar.add(oran);
              items.add(KdvItem(
                  oran: '%$oran',
                  matrah: '',
                  tutar: _normPrice(nextPrices.last)));
            }
          }
        }
      }
    }
    return items;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TOPLAM KDV — (TOPLAM ve KDV'yi birbirine karıştırmayan MÜKEMMEL filtre)
  // ═══════════════════════════════════════════════════════════════════════
  static _Field _toplamKdv(List<_Row> rows, List<KdvItem> detay) {
    // 1. Önce doğrudan "TOPKDV", "TOPLAM KDV", "HESAPLANAN KDV" gibi belirteçleri ara.
    //    "KDV DAHİL TOPLAM" = toplam (KDV değil) → DAHİL içeren satır KDV olarak alınmaz.
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (u.contains('DAHİL') || u.contains('DAHIL')) continue;
      if (u.contains('TOPKDV') ||
          u.contains('TOP KDV') ||
          u.contains('TOPLAM KDV') ||
          u.contains('KDV TOPLAM') ||
          u.contains('KDV TUTARI') ||
          u.contains('HESAPLANAN KDV')) {
        final cleaned = _ocrClean(rows[i].text);
        final p = _findRightmostPrice(cleaned, _priceReg);
        if (p != null) return _Field(_normPrice(p), 0.95);
      }
    }
    // 2. Yukarıdaki yoksa KDV detaylarının toplamına bak
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
      if (valid && total > 0) return _Field(total.toStringAsFixed(2), 0.80);
    }
    // 3. Fallback: Diğer KDV etiketlerini ara
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      // DİKKAT: Toplamı yakalamamak için sıkı denetim! "DAHİL" = toplam, KDV değil.
      if (!u.contains('KDV') ||
          u.contains('ARA TOP') ||
          u.contains('MATRAH') ||
          u.contains('DAHİL') ||
          u.contains('DAHIL')) continue;
      final cleaned = _ocrClean(rows[i].text);
      final p = _findRightmostPrice(cleaned, _priceReg);
      if (p != null) return _Field(_normPrice(p), 0.78);
    }
    // 4. Buruşuk fişler için agresif
    for (int i = 0; i < rows.length; i++) {
      final uAgg = rows[i].upperAggressive;
      if (uAgg.contains('DAHİL') || uAgg.contains('DAHIL')) continue;
      if (!_fuzzy(uAgg, 'KDV') && !_fuzzy(uAgg, 'TOPKDV')) continue;
      final cleaned = _ocrClean(rows[i].textAggressive);
      final p = _findRightmostPrice(cleaned, _priceReg);
      if (p != null) return _Field(_normPrice(p), 0.55);
      final pLoose = _findRightmostPrice(cleaned, _priceRegLoose);
      if (pLoose != null) return _Field(_normPriceLoose(pLoose), 0.45);
    }
    return _Field.empty;
  }

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

  // ═══════════════════════════════════════════════════════════════════════
  // GENEL TOPLAM — (Sıfır hata ile "TOPLAM" ve "KDV" izolasyonu)
  // ═══════════════════════════════════════════════════════════════════════
  static _Field _toplam(List<_Row> rows, _Field kdv, bool isBankaDekontu,
      bool muhtemelenBurusuk) {
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

    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;

      // ── KESİN DIŞLAMA ──
      // KDV/Ara Toplam/Matrah/Mal-Hizmet (alt-toplam) satırları ASLA Genel Toplam olamaz!
      // İSTİSNA: "KDV DAHİL/VERGİLER DAHİL" satırı KDV değil, NİHAİ toplamdır.
      final isDahil = u.contains('DAHİL') || u.contains('DAHIL');
      if (!isDahil &&
          (u.contains('KDV') ||
              u.contains('K.D.V') ||
              u.contains('KATMA DEGER'))) continue;
      if (u.contains('ARA TOP') ||
          u.contains('ARATOP') ||
          u.contains('ARA TOPLAM') ||
          RegExp(r'\bARA\b').hasMatch(u)) continue;
      if (u.contains('MATRAH') ||
          u.contains('VERGISIZ') ||
          u.contains('VERGİSİZ') ||
          u.contains('MAL HIZMET') ||
          u.contains('MAL HİZMET') ||
          u.contains('MAL/HIZMET') ||
          u.contains('MAL/HİZMET')) continue;

      bool matched = false;
      for (final kw in _totalKw) {
        if (_fuzzy(u, kw)) {
          matched = true;
          break;
        }
      }
      // Toplam loose kontrol
      if (!matched) {
        for (final kw in _totalKwLoose) {
          if (u.contains(kw)) {
            matched = true;
            break;
          }
        }
      }

      if (!matched) continue;

      final cleaned = _ocrClean(rows[i].text);
      final p = _findRightmostPrice(cleaned, _priceReg);
      if (p == null) continue;

      final norm = _normPrice(p);

      // Bulunan tutar daha önce KDV olarak bulunduysa atla
      if (kdv.found && norm == kdv.value) continue;

      // Özgüllük katmanı: GENEL/VERGİLER DAHİL/ÖDENECEK/FAT.TOP > genel TOPLAM/TUTAR > kısa.
      final isGrand = _anyOf(u, _grandTotalKw) || _faturaTopReg.hasMatch(u);
      final exactMatch = _anyOf(u, _totalKw);
      final isShortMatch = u.trim() == 'TOP' ||
          u.trim().startsWith('TOP ') ||
          u.trim().endsWith(' TOP');
      final posBonus = (i / rows.length) >= 0.5 ? 0.05 : 0.0;
      final base = isGrand
          ? 0.97
          : (exactMatch ? (isShortMatch ? 0.80 : 0.90) : 0.74);
      final conf = (base + posBonus).clamp(0.0, 1.0);

      if (conf > best.confidence) best = _Field(norm, conf);
    }

    if (best.confidence >= 0.70) return best;

    // Fallback 1: Ödeme tipinden (Nakit, Kredi Kartı) geriye doğru fiyat bul
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

    // Fallback 2: "SATIŞ" kelimesinden sonrasına bak
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (u.trim() == 'SATIŞ' || u.trim() == 'SATIS') {
        for (int j = i + 1; j <= i + 5 && j < rows.length; j++) {
          if (rows[j].upper.contains('TUTAR') || rows[j].upper.contains('TL')) {
            final cleaned = _ocrClean(rows[j].text);
            final p = _findRightmostPrice(cleaned, _priceReg);
            if (p != null && 0.60 > best.confidence) {
              best = _Field(_normPrice(p), 0.60);
              break;
            }
          }
        }
      }
    }

    if (best.confidence >= 0.50) return best;

    // Fallback 3: Agresif (Buruşuk) metinde arama
    if (best.confidence < 0.55 || muhtemelenBurusuk) {
      for (int i = 0; i < rows.length; i++) {
        final uAgg = rows[i].upperAggressive;
        // Agresifte de dışla
        if (uAgg.contains('KDV') || uAgg.contains('K.D.V')) continue;
        if (uAgg.contains('ARA TOP') ||
            uAgg.contains('ARATOP') ||
            uAgg.contains('ARA TOPLAM')) continue;

        bool matched = false;
        for (final kw in _totalKw)
          if (_fuzzy(uAgg, kw)) {
            matched = true;
            break;
          }
        if (!matched)
          for (final kw in _totalKwLoose)
            if (uAgg.contains(kw)) {
              matched = true;
              break;
            }
        if (!matched) continue;

        final cleaned = _ocrClean(rows[i].textAggressive);
        final p = _findRightmostPrice(cleaned, _priceReg);
        if (p == null) {
          final pLoose = _findRightmostPrice(cleaned, _priceRegLoose);
          if (pLoose != null) {
            final norm = _normPriceLoose(pLoose);
            final amt = double.tryParse(norm) ?? 0;
            if (amt >= 0.10 &&
                amt <= 100000 &&
                (!kdv.found || norm != kdv.value) &&
                0.42 > best.confidence) {
              best = _Field(norm, 0.42);
            }
          }
          continue;
        }

        final norm = _normPrice(p);
        if (kdv.found && norm == kdv.value) continue;
        final amt = double.tryParse(norm) ?? 0;
        if (amt >= 0.10 && amt <= 100000 && 0.50 > best.confidence)
          best = _Field(norm, 0.50);
      }
    }

    if (best.confidence >= 0.42) return best;

    // Son çare: Fişin en alt kısmındaki KDV dışı en büyük fiyatı al.
    final startIdx = (rows.length * 0.65).round();
    double maxAmt = 0;
    String maxP = '';
    for (int i = startIdx; i < rows.length; i++) {
      final cleaned = _ocrClean(rows[i].text);
      final p = _findRightmostPrice(cleaned, _priceReg);
      if (p == null) continue;
      final norm = _normPrice(p);
      final amt = double.tryParse(norm) ?? 0;
      if (kdv.found && norm == kdv.value)
        continue; // KDV'yi Genel Toplam Sanma!
      if (amt > 100000) continue;
      if (amt > maxAmt) {
        maxAmt = amt;
        maxP = norm;
      }
    }
    if (maxP.isNotEmpty && 0.42 > best.confidence) best = _Field(maxP, 0.42);

    return best;
  }

  // ── Ödeme tutarları: NAKİT / KART(+benzeri) / ÖDENEN; "para üstü" hariç ──
  // Parçalı ödeme için nakit ve kart ayrı toplanır. T5 (₺→6) teyidi ve
  // CARD_PAID/CASH_PAID rescue havuzu (NerRegexPool) bunu kullanır.
  static Map<String, double> _paymentAmounts(List<_Row> rows) {
    double nakit = 0, kart = 0, odenen = 0;
    for (final row in rows) {
      final u = row.upper;
      final isUstu = u.contains('ÜSTÜ') || u.contains('USTU');
      if (isUstu) continue;
      final isNakit = u.contains('NAKİT') || u.contains('NAKIT');
      final isKart = u.contains('KART') ||
          u.contains('KREDİ') ||
          u.contains('KREDI') ||
          u.contains('BANKA') ||
          u.contains('TEMASSIZ') ||
          u.contains('MULTINET') ||
          u.contains('MULTİNET') ||
          u.contains('SODEXO') ||
          u.contains('PLUXEE') ||
          u.contains('TICKET') ||
          u.contains('SETCARD') ||
          u.contains('METROPOL') ||
          u.contains('YEMEK');
      final isOdenen = u.contains('ÖDENEN') ||
          u.contains('ODENEN') ||
          u.contains('ÖDENECEK') ||
          u.contains('ODENECEK') ||
          u.contains('TAHSİL') ||
          u.contains('TAHSIL');
      if (!isNakit && !isKart && !isOdenen) continue;
      final p = _findRightmostPrice(_ocrClean(row.text), _priceReg);
      if (p == null) continue;
      final v = double.tryParse(_normPrice(p)) ?? 0;
      if (v <= 0) continue;
      if (isNakit) {
        nakit += v;
      } else if (isKart) {
        kart += v;
      }
      if (isOdenen) odenen = v;
    }
    return {'nakit': nakit, 'kart': kart, 'odenen': odenen};
  }

  // ── Fişteki TEK KDV oranını {1,10,20} kümesinden TAM eşleşmeyle tespit eder ──
  // "%" işaretli oranları okur; OCR harf-karışmasını (O→0, l/I→1, S→5, B→8) temizler.
  // İndirim/iskonto/puan satırları HARİÇ (oran sanılmasın). Tam BİR oran varsa onu
  // döner; yoksa veya >1 ise null → tek-oran ters hesabı UYGULANMAZ (güvenli).
  // Not (TR): geçerli KDV oranları yalnız {1,10,20}; %8/%18 (eski) bilerek elenir →
  // o fişler mevcut KDV okuma yoluna düşer (kör yuvarlama yapılmaz).
  static int? _detectSingleVatRate(List<_Row> rows) {
    final rates = <int>{};
    final reg = RegExp(r'%\s*([0-9OoIlSB]{1,2})(?![0-9])');
    for (final row in rows) {
      final u = row.upper;
      if (u.contains('İNDİRİM') ||
          u.contains('INDIRIM') ||
          u.contains('İSKONTO') ||
          u.contains('ISKONTO') ||
          u.contains('KAMPANYA') ||
          u.contains('PUAN')) continue;
      for (final m in reg.allMatches(row.text)) {
        final raw = m
            .group(1)!
            .replaceAll(RegExp('[Oo]'), '0')
            .replaceAll(RegExp('[Il]'), '1')
            .replaceAll('S', '5')
            .replaceAll('B', '8');
        final n = int.tryParse(raw);
        if (n != null && (n == 1 || n == 10 || n == 20)) rates.add(n);
      }
    }
    return rates.length == 1 ? rates.first : null;
  }

  // ── Tutar uzlaştırma: matrah(M) ↔ KDV(K) ↔ toplam(T) çapraz doğrulama ──
  // Sıra önemli. NER-öncelik değil; bu saf-regex tarafının iç tutarlılığıdır.
  static ({String kdv, String toplam, String matrah, List<String> warnings})
      _reconcileAmounts({
    required double matrah,
    required double kdv,
    required double toplam,
    required double cashTendered,
    required double cardPaid,
    required double change,
    required int? singleRate, // fişte TEK KDV oranı (∈{1,10,20}) varsa
    required bool totalReliable, // toplam yüksek güvenle okundu mu
    required bool isEarsiv,
    required List<KdvItem> detay,
    required bool isIptal,
  }) {
    final warnings = <String>[];
    double m = matrah, k = kdv, t = toplam;
    double round2(double x) => (x * 100).round() / 100;
    double tol(double base) => max(0.05, base * (isEarsiv ? 0.05 : 0.02));
    // Mal bedeli = verilen para − para üstü (+ kart). ₺ teyidi bunu kullanır.
    final double payment = max(0.0, round2(cashTendered + cardPaid - change));

    // 0) PARA ÜSTÜ: toplam, VERİLEN para kadarsa (para üstü düşülmemiş) → düzelt.
    //    Örn. mal 11,50; nakit 12,00; para üstü 0,50 ama toplam 12,00 okunmuş.
    if (change > 0 && t > 0 && (cashTendered + cardPaid) > 0 &&
        (t - (cashTendered + cardPaid)).abs() <= tol(t)) {
      final net = round2(cashTendered + cardPaid - change);
      if (net > 0 && (t - net).abs() > 0.01) {
        t = net;
        warnings.add(
            'Para üstü düşülmemişti; toplam, verilen para − para üstü ile düzeltildi.');
      }
    }

    // 1) ₺/TL OCR karışması (iki yönlü): matrah+KDV bağımsız ödeme ile teyitli
    //    VE toplam aşırı sapkınsa düzelt. matrah+KDV ≈ toplam ise GERÇEK kabul, dokunma.
    //    - ŞİŞME: ₺→6 toplamı büyütüyor (t > mk*1.5).
    //    - EKSİLME: ₺ yanındaki rakam okunmuyor → toplam küçük (t < mk*0.67).
    //    Toplam = matrah + KDV her zaman; t<mk fiziksel olarak imkânsızdır (kontrolle güvenli).
    if (m > 0 && k > 0 && payment > 0 && t > 0) {
      final mk = round2(m + k);
      if ((mk - payment).abs() <= tol(payment) &&
          (t > mk * 1.5 || t < mk * 0.67)) {
        final yon = t > mk ? 'şişmiş' : 'eksik okunmuş';
        t = mk;
        warnings.add(
            'Toplam tutar OCR\'de $yon görünüyor (₺/rakam karışması); matrah+KDV ve ödeme tutarından düzeltildi.');
      }
    }

    // 2) Etiket yer değiştirme (KDV>Toplam, matrah var): matrah+küçük ≈ büyük.
    if (k > 0 && t > 0 && k > t && m > 0) {
      final hi = max(k, t), lo = min(k, t);
      if ((m + lo - hi).abs() <= tol(hi)) {
        t = hi;
        k = lo;
      }
    }

    bool kdvHandled = false;

    // 3) TEK-ORAN KDV-DAHİL TERS HESAP — YALNIZ KDV OKUNAMADIYSA türet.
    //    TR fişte TOPLAM = KDV dahil → KDV = T×r/(100+r), matrah = T−KDV.
    //    DİKKAT: Okunan (mevcut) KDV'yi EZMEYİZ. Tek görünen oran, fişin TAMAMININ
    //    o oranda olduğunu garantilemez (çok-oranlı fişte tek marker okunmuş olabilir;
    //    okunan KDV bir oran-karışımı olabilir). Ezmek doğru KDV'yi bozardı → yalnız
    //    boşluğu doldururuz. Mantıksız (örn. >%30) okunan KDV mevcut sanity/matrah
    //    adımlarınca (4-6) ele alınır.
    if (singleRate != null && totalReliable && t > 0 && k <= 0) {
      final int rate = singleRate;
      k = round2(t * rate / (100 + rate));
      m = round2(t - k);
      kdvHandled = true;
    }

    if (!kdvHandled) {
      // 4) KDV ≥ Toplam (820 hatası): toplam ASLA silinmez; KDV kurtarılır/sıfırlanır.
      if (k > 0 && t > 0 && k >= t) {
        double detayTop = 0;
        for (final it in detay) {
          detayTop += double.tryParse(it.tutar) ?? 0;
        }
        if (detayTop > 0 && detayTop < t) {
          k = round2(detayTop);
          warnings.add('KDV tutarı hatalı okundu, fiş detayından düzeltildi.');
        } else if (m > 0 && (t - m) > 0.01 && (t - m) <= t * 0.30) {
          k = round2(t - m);
          warnings
              .add('KDV tutarı mantıksız; matrah ve toplamdan yeniden hesaplandı.');
        } else {
          k = 0;
          if (!isIptal) {
            warnings.add(
                'KDV tutarı mantıksız (Toplamdan büyük/eşit). KDV sıfırlandı, elle giriniz.');
          }
        }
      }
      // 5) KDV sanity: toplamın %30'unu aşamaz (azami TR oranı ~%20 + yuvarlama).
      else if (k > 0 && t > 0 && k > t * 0.30) {
        if (m > 0 && (t - m) > 0.01 && (t - m) <= t * 0.30) {
          k = round2(t - m);
          warnings
              .add('KDV tutarı oransal olarak yüksekti; matrah ve toplamdan düzeltildi.');
        } else {
          k = 0;
          warnings.add(
              'KDV tutarı mantıksız (toplamın %30\'unu aşıyor). KDV sıfırlandı, elle giriniz.');
        }
      }

      // 6) KDV yok ama matrah+toplam var → KDV = toplam − matrah (makulse).
      if (k <= 0 && m > 0 && t > m && (t - m) <= t * 0.30) {
        k = round2(t - m);
      }
    }

    return (
      kdv: k > 0 ? k.toStringAsFixed(2) : '',
      toplam: t > 0 ? t.toStringAsFixed(2) : toplam.toStringAsFixed(2),
      matrah: m > 0 ? m.toStringAsFixed(2) : '',
      warnings: warnings,
    );
  }

  static _Field _odemeYontemi(List<_Row> rows) {
    for (int i = rows.length - 1; i >= 0; i--) {
      for (final kw in _paymentKw)
        if (rows[i].upper.contains(kw)) return _Field(_normOdeme(kw), 0.92);
    }
    for (int i = rows.length - 1; i >= 0; i--) {
      final uAgg = rows[i].upperAggressive;
      for (final kw in _paymentKw)
        if (kw.length >= 4 && _fuzzy(uAgg, kw))
          return _Field(_normOdeme(kw), 0.65);
    }
    return _Field.empty;
  }

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

  static _Field _ettn(List<_Row> rows) {
    for (final row in rows) {
      if (row.upper.contains('ETTN')) {
        final m = _ettnReg.firstMatch(row.text);
        if (m != null) return _Field(m.group(1)!.toLowerCase(), 0.99);
      }
    }
    for (final row in rows) {
      final m = _ettnReg.firstMatch(row.text);
      if (m != null) return _Field(m.group(1)!.toLowerCase(), 0.92);
    }
    return _Field.empty;
  }

  static _Field _mersis(List<_Row> rows) {
    for (final row in rows) {
      final m = _mersisReg.firstMatch(_ocrClean(row.text));
      if (m != null) return _Field(m.group(1)!, 0.96);
    }
    final mersisAltReg = RegExp(r'\b(0\d{15})\b');
    for (final row in rows) {
      final m = mersisAltReg.firstMatch(_ocrClean(row.text));
      if (m != null) return _Field(m.group(1)!, 0.70);
    }
    return _Field.empty;
  }

  static _Field _iban(List<_Row> rows) {
    for (final row in rows) {
      final m = _ibanReg.firstMatch(row.text.toUpperCase());
      if (m != null) {
        final clean = m.group(1)!.replaceAll(' ', '');
        if (clean.length == 26) return _Field(clean, 0.95);
      }
    }
    return _Field.empty;
  }

  static _Field _ekuNo(List<_Row> rows) {
    for (final row in rows) {
      final m = _ekuReg.firstMatch(_ocrClean(row.text));
      if (m != null) {
        final val = m.group(1)!.trim();
        if (val.isNotEmpty) return _Field(val.toUpperCase(), 0.88);
      }
    }
    return _Field.empty;
  }

  static _Field _araToplam(List<_Row> rows) {
    for (int i = 0; i < rows.length; i++) {
      if (_araToplamReg.hasMatch(rows[i].upper)) {
        final p = _findRightmostPrice(_ocrClean(rows[i].text), _priceReg);
        if (p != null) return _Field(_normPrice(p), 0.90);
        if (i + 1 < rows.length) {
          final pn =
              _findRightmostPrice(_ocrClean(rows[i + 1].text), _priceReg);
          if (pn != null) return _Field(_normPrice(pn), 0.75);
        }
      }
    }
    return _Field.empty;
  }

  static _Field _paraBirimi(List<_Row> rows) {
    for (int i = rows.length - 1; i >= 0; i--) {
      final m = _paraBirimiReg.firstMatch(rows[i].upper);
      if (m != null) {
        String birim = m.group(1)!.toUpperCase();
        if (birim == '₺' || birim.contains('TURK') || birim == 'TRY')
          birim = 'TL';
        else if (birim == 'EURO') birim = 'EUR';
        return _Field(birim, 0.92);
      }
    }
    return const _Field('TL', 0.50);
  }

  static Map<String, String?> _yakitDetay(List<_Row> rows) {
    String? turu, litre, pompa, plaka;
    for (final row in rows) {
      final u = row.upper;
      final cleaned = _ocrClean(row.text);
      if (turu == null) {
        final m = _yakitTuruReg.firstMatch(u);
        if (m != null)
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
      if (litre == null) {
        final m = _litreReg.firstMatch(cleaned);
        if (m != null) litre = '${m.group(1)!.replaceAll('.', ',')} L';
      }
      if (pompa == null) {
        final m = _pompaReg.firstMatch(cleaned);
        if (m != null) pompa = m.group(1)!;
      }
      if (plaka == null) {
        final m = _plakaReg.firstMatch(u);
        if (m != null) plaka = '${m.group(1)!} ${m.group(2)!} ${m.group(3)!}';
      }
    }
    return {'turu': turu, 'litre': litre, 'pompa': pompa, 'plaka': plaka};
  }

  static _Field _telefon(List<_Row> rows) {
    for (int i = 0; i < rows.length && i < 10; i++) {
      final m = _telefonReg.firstMatch(rows[i].text);
      if (m != null)
        return _Field(
            m.group(1)!.replaceAll(' ', '').replaceAll('-', ''), 0.85);
    }
    return _Field.empty;
  }

  static String _kategori(
      String firmaAdi, String odemeYontemi, List<_Row> rows) {
    final plakaReg =
        RegExp(r'\b(0[1-9]|[1-7][0-9]|8[01])\s*[A-ZŞĞÇİÖÜ]{1,3}\s*\d{2,4}\b');
    for (final r in rows) if (plakaReg.hasMatch(r.upper)) return 'Yakıt';
    for (final r in rows) {
      final u = r.upper;
      if (u.contains('POMPA') ||
          u.contains('MOTORIN') ||
          u.contains('MOTORİN') ||
          u.contains('BENZIN') ||
          u.contains('BENZİN') ||
          u.contains('AKARYAKIT') ||
          u.contains('DIZEL') ||
          u.contains('DİZEL') ||
          (u.contains('LITRE') && r.text.contains(RegExp(r'\d'))))
        return 'Yakıt';
    }
    final oU = odemeYontemi.toUpperCase();
    if (oU.contains('YEMEK') ||
        oU.contains('MULTINET') ||
        oU.contains('SODEXO') ||
        oU.contains('PLUXEE') ||
        oU.contains('TICKET') ||
        oU.contains('SETCARD') ||
        oU.contains('METROPOL') ||
        oU.contains('PAYE')) return 'Yeme-İçme';
    for (final r in rows)
      if (r.upper.contains('E-REÇETE') ||
          r.upper.contains('İLAÇ') ||
          r.upper.contains('SGK') ||
          r.upper.contains('ECZANE') ||
          r.upper.contains('HASTANE')) return 'Sağlık';
    for (final r in rows) {
      final u = r.upper;
      if (u.contains('ELEKTRİK FATURASI') ||
          u.contains('SU FATURASI') ||
          u.contains('DOĞALGAZ') ||
          u.contains('DOGALGAZ') ||
          u.contains('İNTERNET FATURASI') ||
          u.contains('TELEFON FATURASI') ||
          u.contains('ABONE NO')) return 'Faturalar';
    }
    final u = firmaAdi.toUpperCase();
    for (final entry in _kategoriMap.entries)
      if (u.contains(entry.key)) return entry.value;
    final smartU = SmartWordCorrector.correctSentence(firmaAdi).toUpperCase();
    if (smartU != u)
      for (final entry in _kategoriMap.entries)
        if (smartU.contains(entry.key)) return entry.value;
    for (final r in rows) {
      final smartRow = SmartWordCorrector.correctSentence(r.text).toUpperCase();
      for (final entry in _kategoriMap.entries)
        if (entry.key.length >= 4 && smartRow.contains(entry.key))
          return entry.value;
    }
    for (final entry in _kategoriMap.entries)
      if (entry.key.length >= 5 && _fuzzy(u, entry.key)) return entry.value;
    return 'Diğer';
  }

  static String? _findRightmostPrice(String text, RegExp reg) {
    final all = reg.allMatches(text).map((m) => m.group(0)!).toList();
    return all.isNotEmpty ? all.last : null;
  }

  // ── MÜKEMMEL FORMATLAYICI (1.250,50 -> 1250.50) ──
  static String _normPrice(String raw) {
    String clean = raw.replaceAll('*', '').replaceAll(RegExp(r'[^0-9.,]'), '');
    if (clean.isEmpty) return '0.00';

    int lastDot = clean.lastIndexOf('.');
    int lastComma = clean.lastIndexOf(',');

    if (lastDot > -1 && lastComma > -1) {
      if (lastComma > lastDot)
        clean = clean.replaceAll('.', '').replaceAll(',', '.');
      else
        clean = clean.replaceAll(',', '');
    } else if (lastComma > -1) {
      clean = clean.replaceAll(',', '.');
    }

    double? val = double.tryParse(clean);
    return val != null ? val.toStringAsFixed(2) : '0.00';
  }

  static String _normPriceLoose(String raw) {
    String s = raw.replaceAll('*', '').replaceAll('₺', '').trim();
    s = s.replaceAllMapped(
        RegExp(r'(\d{1,4})\s+(\d{2})$'), (m) => '${m[1]}.${m[2]}');
    return _normPrice(s);
  }

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

  static bool _fuzzy(String src, String target) {
    if (src.contains(target)) return true;
    final srcNoSpace = src.replaceAll(RegExp(r'\s+'), '');
    final targetNoSpace = target.replaceAll(RegExp(r'\s+'), '');
    if (srcNoSpace.contains(targetNoSpace)) return true;

    for (final word in src.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      if (word.length >= target.length - 2 &&
          word.length <= target.length + 2) {
        int maxLev = target.length <= 4
            ? 1
            : target.length <= 7
                ? 2
                : 3;
        if (_lev(word, target) <= maxLev) return true;
      }
    }
    if (target.length >= 6) {
      final prefix =
          target.substring(0, (target.length ~/ 2).clamp(3, target.length));
      final suffix = target.substring(target.length - 2);
      if (srcNoSpace.contains(prefix.replaceAll(' ', '')) &&
          srcNoSpace.contains(suffix)) return true;
    }
    if (target.length >= 5 && srcNoSpace.length >= target.length) {
      final targetChars = target.split('').toSet();
      final srcChars = srcNoSpace.split('').toSet();
      if (targetChars.intersection(srcChars).length / targetChars.length >=
          0.75) {
        if (srcNoSpace.startsWith(target[0]) ||
            srcNoSpace.contains(' ${target[0]}') ||
            srcNoSpace.contains(target.substring(0, 2))) {
          if (target.length >= 8) return true;
        }
      }
    }
    return false;
  }

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
