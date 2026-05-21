// lib/extensions/string_extensions.dart
//
// ═══════════════════════════════════════════════════════════════════════
// TÜRK FİŞLERİ İÇİN OCR HATA DÜZELTME KÜTÜPHANESİ
// ═══════════════════════════════════════════════════════════════════════
// Mevcut fixOcrConfusion getter'ı KORUNDU.
// YENİ: SmartWordCorrector entegrasyonu eklendi.

import '../utils/smart_word_corrector.dart';

extension OcrStringExtension on String {
  // ═════════════════════════════════════════════════════════════════════
  // ANA GETTER — Orijinal (geriye dönük uyumlu)
  // ═════════════════════════════════════════════════════════════════════
  String get fixOcrConfusion {
    String result = this;

    // ──── KATMAN 1: SAYI/HARF KARIŞIKLIĞI (orijinal) ────
    result = result.replaceAllMapped(
      RegExp(r'([a-zğüşıöç])0([a-zğüşıöç])'),
      (Match m) => '${m[1]}o${m[2]}',
    );

    result = result.replaceAllMapped(
      RegExp(r'([A-ZĞÜŞİÖÇ])0([A-ZĞÜŞİÖÇ])'),
      (Match m) => '${m[1]}O${m[2]}',
    );

    // ──── KATMAN 2: BİLİNEN ANAHTAR KELİME DÜZELTMELERİ (genişletildi) ────
    // TOPLAM varyasyonları
    result = result.replaceAll('T0PLAM', 'TOPLAM');
    result = result.replaceAll('T9PLAM', 'TOPLAM');
    result = result.replaceAll('TQPLAM', 'TOPLAM');
    result = result.replaceAll('TOPLAН', 'TOPLAM');
    result = result.replaceAll('T0PLAН', 'TOPLAM');
    result = result.replaceAll('T0PLA8', 'TOPLAM');

    // KDV varyasyonları
    result = result.replaceAll('K0V', 'KDV');
    result = result.replaceAll('KOV', 'KDV');
    result = result.replaceAll('KБV', 'KDV');
    result = result.replaceAll('KDУ', 'KDV');
    result = result.replaceAll('KDМ', 'KDV');

    // TUTAR varyasyonları
    result = result.replaceAll('TUTAк', 'TUTAR');
    result = result.replaceAll('TUTAЯ', 'TUTAR');
    result = result.replaceAll('TUT4R', 'TUTAR');

    // FİŞ NO varyasyonları
    result = result.replaceAll('F1S', 'FIS');
    result = result.replaceAll('FlS', 'FIS');
    result = result.replaceAll('FIŞ N0', 'FIŞ NO');
    result = result.replaceAll('FİŞ N0', 'FİŞ NO');
    result = result.replaceAll('FIS N0', 'FIS NO');

    // NAKIT/NAKİT varyasyonları
    result = result.replaceAll('NAK1T', 'NAKIT');
    result = result.replaceAll('NAKİТ', 'NAKİT');
    result = result.replaceAll('NAK!T', 'NAKIT');
    result = result.replaceAll('NAKlT', 'NAKIT');

    // TARİH varyasyonları
    result = result.replaceAll('TAR1H', 'TARIH');
    result = result.replaceAll('TARlH', 'TARIH');
    result = result.replaceAll('TARİН', 'TARİH');

    // ──── KATMAN 3: PARA BİRİMİ ────
    result = result.replaceAll(RegExp(r'\bTI\b'), 'TL');
    result = result.replaceAll(RegExp(r'\bTl\b'), 'TL');
    result = result.replaceAll(RegExp(r'\bT\.L\.?\b'), 'TL');

    return result;
  }

  // ═════════════════════════════════════════════════════════════════════
  // YENİ: AKILLI KELİME DÜZELTME — Firma adı için en güçlü katman
  // SmartWordCorrector kullanarak "0PERA" → "OPERA" düzeltmesi yapar
  // ═════════════════════════════════════════════════════════════════════
  String get smartWordCorrect {
    return SmartWordCorrector.correctSentence(this);
  }

  // ═════════════════════════════════════════════════════════════════════
  // AGRESİF TEMİZLEME — Buruşuk fişler için
  // ═════════════════════════════════════════════════════════════════════
  String get aggressiveOcrClean {
    String s = this;

    // 1. Parçalanmış kelime yeniden birleştirme
    s = _rejoinFragmentedWords(s);

    // 2. Yaygın kelime fuzzy düzeltmeleri
    final fragmentMap = {
      'TOPL AM': 'TOPLAM',
      'TOP LAM': 'TOPLAM',
      'TOPL M': 'TOPLAM',
      'OPLAM': 'TOPLAM',
      'TPLAM': 'TOPLAM',
      'TOLAM': 'TOPLAM',
      'TOPLA': 'TOPLAM',
      'TOPLAH': 'TOPLAM',
      'TOPLAN': 'TOPLAM',
      'GENEL TOPLA': 'GENEL TOPLAM',
      'G TOPLAM': 'GENEL TOPLAM',
      'GNL TOPLAM': 'GENEL TOPLAM',
      'GENE TOPLAM': 'GENEL TOPLAM',
      'K D V': 'KDV',
      'K.D.V': 'KDV',
      'KD V': 'KDV',
      'K DV': 'KDV',
      'KDU': 'KDV',
      'TUTA': 'TUTAR',
      'UTAR': 'TUTAR',
      'TUAR': 'TUTAR',
      'F NO': 'FİŞ NO',
      'FS NO': 'FİŞ NO',
      'IŞ NO': 'FİŞ NO',
      'TARH': 'TARİH',
      'TRH': 'TARİH',
      'TAIH': 'TARİH',
      'TRIH': 'TARİH',
      'SAA': 'SAAT',
      'SAT': 'SAAT',
      'SAA T': 'SAAT',
      'VRG NO': 'VKN',
      'V K N': 'VKN',
      'V D': 'V.D.',
      'VD ': 'V.D. ',
      'ARA TOPLA': 'ARA TOPLAM',
      'A TOPLAM': 'ARA TOPLAM',
      'AR TOPLAM': 'ARA TOPLAM',
      'MATRA': 'MATRAH',
      'MTRAH': 'MATRAH',
      'MATR': 'MATRAH',
      'NAK T': 'NAKIT',
      'NAIT': 'NAKIT',
      'NKIT': 'NAKIT',
      'BNK': 'BANKA',
      'KRT': 'KART',
      'MGROS': 'MIGROS',
      'MIROS': 'MIGROS',
      'MIGRS': 'MIGROS',
    };

    fragmentMap.forEach((key, val) {
      s = s.replaceAll(key, val);
    });

    final tcMap = {
      'MUSTERI': 'MÜŞTERİ',
      'TESEKKUR': 'TEŞEKKÜR',
      'BEKLERIZ': 'BEKLERİZ',
      'GUNLER': 'GÜNLER',
      'HOSGELDINIZ': 'HOŞGELDİNİZ',
      'AFIYET': 'AFİYET',
    };
    tcMap.forEach((key, val) {
      s = s.replaceAll(key, val);
    });

    return s;
  }

  // ═════════════════════════════════════════════════════════════════════
  // FİYAT BAĞLAMI TEMİZLEMESİ
  // ═════════════════════════════════════════════════════════════════════
  String get fixPriceContext {
    String s = this;

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
      RegExp(r'(\d{1,4})\s+(\d{2})(?=\s*(TL|₺|$|\n))'),
      (m) => '${m[1]},${m[2]}',
    );

    s = s.replaceAllMapped(
      RegExp(r'(\d{1,3})\.(\d{2})(?!\d)'),
      (m) => '${m[1]},${m[2]}',
    );

    return s;
  }

  // ═════════════════════════════════════════════════════════════════════
  // TARİH BAĞLAMI DÜZELTMESİ
  // ═════════════════════════════════════════════════════════════════════
  String get fixDateContext {
    String s = this;

    s = s.replaceAllMapped(
      RegExp(r'(\d{2})[Il](\d{2})[Il](\d{4})'),
      (m) => '${m[1]}/${m[2]}/${m[3]}',
    );

    s = s.replaceAllMapped(
      RegExp(r'(\d{2})[.\-/](\d{2})[.\-/](\d{4})'),
      (m) => '${m[1]}/${m[2]}/${m[3]}',
    );

    return s;
  }

  // ═════════════════════════════════════════════════════════════════════
  // ONDALIK AYRAÇI NORMALİZE
  // ═════════════════════════════════════════════════════════════════════
  String get normalizeDecimal {
    return replaceAllMapped(
      RegExp(r'(\d)\.(\d{2})(?!\d)'),
      (m) => '${m[1]},${m[2]}',
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // TÜM SAFHALARI TEK SEFERDE UYGULA
  // ═════════════════════════════════════════════════════════════════════
  String get fullOcrClean {
    return fixOcrConfusion.fixDateContext;
  }

  // ═════════════════════════════════════════════════════════════════════
  // TAM TEMİZLEME (buruşuk fişler için)
  // ═════════════════════════════════════════════════════════════════════
  String get crumpledOcrClean {
    return fixOcrConfusion.aggressiveOcrClean.fixDateContext.fixPriceContext;
  }

  // ═════════════════════════════════════════════════════════════════════
  // PRIVATE: Parçalanmış kelimeleri yeniden birleştir
  // ═════════════════════════════════════════════════════════════════════
  String _rejoinFragmentedWords(String text) {
    final knownWords = [
      'TOPLAM',
      'GENEL',
      'KDV',
      'TUTAR',
      'TARİH',
      'TARIH',
      'SAAT',
      'NAKIT',
      'NAKİT',
      'KART',
      'BANKA',
      'KREDİ',
      'MATRAH',
      'ARA',
      'PARA',
      'ÜSTÜ',
      'FIS',
      'FİŞ',
      'BELGE',
      'SERI',
      'SERİ',
      'MERSIS',
      'MERSİS',
      'IBAN',
      'ETTN',
      'EKÜ',
      'EKU',
      'POMPA',
      'LITRE',
      'MOTORIN',
      'MOTORİN',
      'BENZIN',
      'BENZİN',
      'LPG',
      'ÖDEME',
      'ÖDENECEK',
      'ÖDENEN',
      'VERGI',
      'VERGİ',
      'DAIRESI',
      'DAİRESİ',
      'MAH',
      'CAD',
      'SOK',
    ];

    String result = text;

    for (final word in knownWords) {
      if (word.length < 4) continue;

      for (int split = 2; split < word.length - 1; split++) {
        final first = word.substring(0, split);
        final rest = word.substring(split);
        final pattern = RegExp('\\b$first $rest\\b');
        result = result.replaceAll(pattern, word);
      }
    }

    return result;
  }
}
