// lib/extensions/string_extensions.dart
//
// ═══════════════════════════════════════════════════════════════════════
// TÜRK FİŞLERİ İÇİN OCR HATA DÜZELTME KÜTÜPHANESİ
// ═══════════════════════════════════════════════════════════════════════
// Mevcut fixOcrConfusion getter'ı KORUNDU.
// YENİ: Buruşuk fişler için ekstra düzeltme katmanları eklendi.

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
  // YENİ: AGRESİF TEMİZLEME — Buruşuk fişler için
  // Standart fixOcrConfusion'dan SONRA çağrılır.
  // Daha fazla karakter düzeltir ama bazı yanlış pozitiflere yol açabilir,
  // bu yüzden sadece güven düşük olduğunda kullanılır.
  // ═════════════════════════════════════════════════════════════════════
  String get aggressiveOcrClean {
    String s = this;

    // 1. Parçalanmış kelime yeniden birleştirme (buruşuk fişlerde sık)
    // "TOP LAM" → "TOPLAM" (1-2 karakter parçalanma)
    s = _rejoinFragmentedWords(s);

    // 2. Yaygın kelime fuzzy düzeltmeleri (Levenshtein 1 mesafe)
    final fragmentMap = {
      // TOPLAM varyantları
      'TOPL AM': 'TOPLAM', 'TOP LAM': 'TOPLAM', 'TOPL M': 'TOPLAM',
      'OPLAM': 'TOPLAM', 'TPLAM': 'TOPLAM', 'TOLAM': 'TOPLAM',
      'TOPLA': 'TOPLAM', 'TOPLAH': 'TOPLAM', 'TOPLAN': 'TOPLAM',
      // GENEL TOPLAM
      'GENEL TOPLA': 'GENEL TOPLAM', 'G TOPLAM': 'GENEL TOPLAM',
      'GNL TOPLAM': 'GENEL TOPLAM', 'GENE TOPLAM': 'GENEL TOPLAM',
      // KDV
      'K D V': 'KDV', 'K.D.V': 'KDV', 'KD V': 'KDV', 'K DV': 'KDV',
      'KDV ': 'KDV ', 'KDU': 'KDV', 'KDМ': 'KDV',
      // TUTAR
      'TUTA': 'TUTAR', 'UTAR': 'TUTAR', 'TUAR': 'TUTAR',
      // FİŞ NO
      'F NO': 'FİŞ NO', 'FS NO': 'FİŞ NO', 'IŞ NO': 'FİŞ NO',
      // TARİH
      'TARH': 'TARİH', 'TARIH': 'TARİH', 'TRH': 'TARİH',
      'TAIH': 'TARİH', 'TRIH': 'TARİH',
      // SAAT
      'SAA': 'SAAT', 'SAT': 'SAAT', 'SAA T': 'SAAT',
      // VERGI/VKN
      'VRG NO': 'VKN', 'VERGI NO': 'VKN', 'V K N': 'VKN',
      'V D': 'V.D.', 'V.D': 'V.D.', 'VD ': 'V.D. ',
      // ARA TOPLAM
      'ARA TOPLA': 'ARA TOPLAM', 'A TOPLAM': 'ARA TOPLAM',
      'AR TOPLAM': 'ARA TOPLAM', 'ARATOPLA': 'ARATOPLAM',
      // MATRAH
      'MATRA': 'MATRAH', 'MTRAH': 'MATRAH', 'MATR': 'MATRAH',
      // NAKIT
      'NAK T': 'NAKIT', 'NAIT': 'NAKIT', 'NKIT': 'NAKIT',
      // BANKA / KART
      'BNK': 'BANKA', 'KRT': 'KART', 'KART ': 'KART ',
      // MIGROS
      'MGROS': 'MIGROS', 'MIROS': 'MIGROS', 'MIGRS': 'MIGROS',
    };

    fragmentMap.forEach((key, val) {
      s = s.replaceAll(key, val);
    });

    // 3. Türkçe karakter OCR hataları (buruşukta sık)
    // İ ↔ I, Ş ↔ S, Ğ ↔ G karışıklıkları
    // Sadece kelime içinde, başında değil
    final tcMap = {
      'IS\b': 'İŞ', 'IG\b': 'İĞ',
      // "MUSTERİ" → "MÜŞTERİ" gibi
      'MUSTERI': 'MÜŞTERİ',
      'MUSTERİ': 'MÜŞTERİ',
      'TESEKKUR': 'TEŞEKKÜR',
      'TESEKKÜR': 'TEŞEKKÜR',
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
  // YENİ: FİYAT BAĞLAMI TEMİZLEMESİ
  // Sayı bloklarındaki yaygın karışıklıkları düzeltir.
  // Buruşuk fişlerde "1l9,40" gibi 1↔l, O↔0 karışıklığı çok yaygındır.
  // ═════════════════════════════════════════════════════════════════════
  String get fixPriceContext {
    String s = this;

    // Sayı blokları içindeki harf karakterlerini rakama dönüştür
    // Örnek: "11l,40" → "111,40", "12O,5O" → "120,50"
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

    // Birden çok kez tekrarla (örn. "1l9,4O" → 2 geçişe ihtiyaç var)
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

    // YENİ: Ondalık ayraç düzeltme
    // "11940" → "119,40" (eğer 3 rakamdan fazlaysa ve para birimi geliyorsa)
    // "119 40" → "119,40" (boşluk virgül yerine geçmiş)
    s = s.replaceAllMapped(
      RegExp(r'(\d{1,4})\s+(\d{2})(?=\s*(TL|₺|$|\n))'),
      (m) => '${m[1]},${m[2]}',
    );

    // Bir nokta-virgül karışıklığı: "11.940" → "11,940" değil
    // Ama "119.40" muhtemelen "119,40" olmalı (Türkçe)
    s = s.replaceAllMapped(
      RegExp(r'(\d{1,3})\.(\d{2})(?!\d)'),
      (m) => '${m[1]},${m[2]}',
    );

    return s;
  }

  // ═════════════════════════════════════════════════════════════════════
  // YENİ: TARİH BAĞLAMI DÜZELTMESİ
  // ═════════════════════════════════════════════════════════════════════
  String get fixDateContext {
    String s = this;

    // OCR'da "/" yerine "1", "I", "l" görmesi yaygın
    // 15I05I2026 → 15/05/2026
    s = s.replaceAllMapped(
      RegExp(r'(\d{2})[Il](\d{2})[Il](\d{4})'),
      (m) => '${m[1]}.${m[2]}.${m[3]}',
    );

    // Karma ayraçları normalleştir
    s = s.replaceAllMapped(
      RegExp(r'(\d{2})[.\-/](\d{2})[.\-/](\d{4})'),
      (m) => '${m[1]}.${m[2]}.${m[3]}',
    );

    // 15052026 (8 hane) → 15.05.2026
    s = s.replaceAllMapped(
      RegExp(r'\b(\d{2})(\d{2})(20\d{2})\b'),
      (m) => '${m[1]}.${m[2]}.${m[3]}',
    );

    return s;
  }

  // ═════════════════════════════════════════════════════════════════════
  // YENİ: ONDALIK AYRAÇI NORMALİZE
  // ═════════════════════════════════════════════════════════════════════
  String get normalizeDecimal {
    return replaceAllMapped(
      RegExp(r'(\d)\.(\d{2})(?!\d)'),
      (m) => '${m[1]},${m[2]}',
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // YENİ: TÜM SAFHALARI TEK SEFERDE UYGULA
  // Parser dışından çağrılmak için pratik tek-seferlik temizleme
  // ═════════════════════════════════════════════════════════════════════
  String get fullOcrClean {
    return fixOcrConfusion.fixDateContext;
  }

  // ═════════════════════════════════════════════════════════════════════
  // YENİ: TAM TEMİZLEME (buruşuk fişler için)
  // ═════════════════════════════════════════════════════════════════════
  String get crumpledOcrClean {
    return fixOcrConfusion.aggressiveOcrClean.fixDateContext.fixPriceContext;
  }

  // ═════════════════════════════════════════════════════════════════════
  // PRIVATE: Parçalanmış kelimeleri yeniden birleştir
  // "TOP LAM" → "TOPLAM" gibi (boşluk eklenmiş kelimeler)
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

      // 2 karakterden sonra boşluk varsa birleştir
      // Örn: "TOP LAM" → "TOPLAM"
      // Pattern: kelimenin ilk N harfi + boşluk + kelimenin kalanı
      for (int split = 2; split < word.length - 1; split++) {
        final first = word.substring(0, split);
        final rest = word.substring(split);
        // Word boundary ile birlikte ara (yanlış pozitifleri önle)
        final pattern = RegExp('\\b$first $rest\\b');
        result = result.replaceAll(pattern, word);
      }
    }

    return result;
  }
}
