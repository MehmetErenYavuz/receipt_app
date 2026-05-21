// lib/utils/smart_word_corrector.dart
//
// ═══════════════════════════════════════════════════════════════════════
// AKILLI KELİME DÜZELTİCİ — Türk fişlerine özel
// ═══════════════════════════════════════════════════════════════════════
// Sorun: OCR sık sık "O" harfini "0" rakamı olarak okur.
// Örnek: "OPERA" → "0PERA", "KOTON" → "K0T0N", "BOYNER" → "B0YNER"
//
// Çözüm: Bir kelime "string ifade" mi yoksa "sayı/kod" mu olduğunu
// algılayıp, kelime ise harf-rakam karışıklıklarını akıllıca düzeltir.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:math';

class SmartWordCorrector {
  // ═════════════════════════════════════════════════════════════════════
  // TÜRK FİRMA SÖZLÜĞÜ (Bilinen markalar için kesin eşleştirme)
  // OCR çıktısı bu listedeki bir markaya yakınsa, doğru hali tercih edilir
  // ═════════════════════════════════════════════════════════════════════
  static const List<String> _knownBrands = [
    // ── Marketler ──
    'MIGROS', 'MİGROS', 'BIM', 'BİM', 'A101', 'SOK', 'ŞOK',
    'CARREFOUR', 'FILE', 'FİLE', 'MAKRO', 'HAKMAR', 'ONUR',
    'TARIM KREDI', 'BIZIM', 'BİZİM', 'KILER', 'KİLER', 'SEC', 'SEÇ',
    'METRO', 'EKOMINI', 'EKOMİNİ', 'YUNUS', 'KIM', 'HAPPY',
    'ALTUNBILEKLER', 'OZDILEK', 'ÖZDİLEK', 'GRATIS', 'WATSONS',
    // ── Yakıt ──
    'SHELL', 'OPET', 'TOTAL', 'LUKOIL', 'BP', 'PETROL OFISI',
    'AYTEMIZ', 'AYTEMİZ', 'TURKUVAZ', 'MOIL', 'MOİL', 'POAS',
    // ── Yeme-İçme ──
    'OPERA', 'MCDONALDS', 'BURGER KING', 'POPEYES', 'KFC', 'SUBWAY',
    'STARBUCKS', 'SIMIT SARAYI', 'SİMİT SARAYI', 'KAHVE DUNYASI',
    'KAHVE DÜNYASI', 'NUSRET', 'NUSR-ET', 'DOMINOS', 'DOMİNOS',
    'KOMAGENE', 'PASAPORT PIZZA', 'KOFTECI RAMIZ', 'KÖFTECİ RAMİZ',
    'KOFTECI YUSUF', 'KÖFTECİ YUSUF', 'BIG CHEFS', 'GUNAYDIN',
    'GÜNAYDIN', 'MADO', 'EATALY', 'HACIZADE', 'GLORIA JEANS',
    'TATCAFE', 'MIDYECI', 'ANADOLU REST', 'EKREM COSKUN', 'MACKBEAR',
    'PEK DONER', 'PEK DÖNER', 'CAFFE DI', 'KONAK CAFE', 'FERROVIA',
    'CAJUN CORNER', 'BURGER', 'PIZZA', 'KEBAP', 'DONER', 'DÖNER',
    'LOKANTA', 'RESTORAN', 'CAFE', 'COFFEE', 'KAHVE',
    // ── Giyim ──
    'KOTON', 'BOYNER', 'LC WAIKIKI', 'LCW', 'DEFACTO', 'MAVI', 'MAVİ',
    'ZARA', 'MANGO', 'COLINS', 'COLİNS', 'NETWORK', 'POLO',
    'BERSHKA', 'STRADIVARIUS', 'PULL BEAR', 'DAMAT', 'KIGILI', 'KIĞILI',
    'TUDORS', 'NINE WEST',
    // ── Elektronik ──
    'TEKNOSA', 'MEDIA MARKT', 'MEDIAMARKT', 'VATAN', 'BIM TEKNO',
    'TURKCELL', 'VODAFONE', 'TURK TELEKOM', 'TÜRK TELEKOM', 'TTNET',
    // ── Sağlık / Eczane ──
    'ECZANE', 'PHARMACY', 'HASTANE', 'KLINIK', 'KLİNİK',
    'POLIKLINIK', 'POLİKLİNİK', 'MEDIKAL', 'MEDİKAL',
    // ── Ulaşım ──
    'TAXI', 'TAKSI', 'TAKSİ', 'OTOPARK', 'METRO', 'IDO', 'İDO',
    'BUDO', 'TCDD', 'UBER', 'BITAKSI', 'BİTAKSİ',
    // ── Faturalar ──
    'ENERJISA', 'ENERJİSA', 'BEDAS', 'BEDAŞ', 'IGDAS', 'İGDAŞ',
    'ISKI', 'İSKİ', 'KAYSERIGAZ', 'KAYSERİGAZ', 'TURKSAT', 'TÜRKSAT',
    // ── Yaygın Türk şehir/mahalle isimleri (adreste geçer) ──
    'KAYSERI', 'KAYSERİ', 'ISTANBUL', 'İSTANBUL', 'ANKARA', 'IZMIR',
    'İZMİR', 'ANTALYA', 'BURSA', 'KOCAELI', 'KOCAELİ',
    // ── Yaygın Türk firma kelimeleri ──
    'TICARET', 'TİCARET', 'SANAYI', 'SANAYİ', 'LIMITED', 'LİMİTED',
    'ANONIM', 'ANONİM', 'SIRKET', 'ŞİRKET', 'HOLDING', 'GIDA', 'GİDA',
    'MARKET', 'MAGAZA', 'MAĞAZA', 'PETROL', 'AKARYAKIT', 'OTOMOTIV',
    'OTOMOTİV', 'NAKLIYE', 'NAKLİYE', 'TAS', 'TAŞ', 'INSAAT', 'İNŞAAT',
    // ── Yaygın anahtar kelimeler ──
    'TOPLAM', 'GENEL', 'TUTAR', 'NAKIT', 'NAKİT', 'KART', 'KREDI',
    'KREDİ', 'BANKA', 'POS', 'MATRAH', 'KDV', 'TARIH', 'TARİH',
    'SAAT', 'FIS', 'FİŞ', 'NO', 'VERGI', 'VERGİ', 'DAIRESI', 'DAİRESİ',
    'MUSTERI', 'MÜŞTERİ', 'TESEKKUR', 'TEŞEKKÜR', 'BEKLERIZ', 'BEKLERİZ',
    'AFIYET', 'AFİYET', 'OLSUN', 'IYI', 'İYİ', 'GUNLER', 'GÜNLER',
  ];

  // ═════════════════════════════════════════════════════════════════════
  // OCR KARIŞIKLIK HARİTASI
  // OCR'da yaygın olarak hangi rakam hangi harfle karıştırılır
  // ═════════════════════════════════════════════════════════════════════
  static const Map<String, String> _digitToLetter = {
    '0': 'O', // En yaygın
    '1': 'I', // I, l, ı
    '5': 'S',
    '8': 'B',
    '6': 'G',
    '2': 'Z',
    '9': 'g',
    '4': 'A', // A bazen 4 olarak okunur
    '7': 'T', // Daha az yaygın
  };

  // Tersine harita (sayı bağlamı için)
  static const Map<String, String> _letterToDigit = {
    'O': '0',
    'o': '0',
    'I': '1',
    'l': '1',
    'i': '1',
    'S': '5',
    's': '5',
    'B': '8',
    'G': '6',
    'Z': '2',
    'z': '2',
    'q': '9',
    'A': '4',
  };

  // Türkçe ünlüler
  static const Set<String> _turkishVowels = {
    'A',
    'E',
    'I',
    'İ',
    'O',
    'Ö',
    'U',
    'Ü',
    'a',
    'e',
    'ı',
    'i',
    'o',
    'ö',
    'u',
    'ü',
  };

  // Türkçe ünsüzler
  static const Set<String> _turkishConsonants = {
    'B',
    'C',
    'Ç',
    'D',
    'F',
    'G',
    'Ğ',
    'H',
    'J',
    'K',
    'L',
    'M',
    'N',
    'P',
    'R',
    'S',
    'Ş',
    'T',
    'V',
    'Y',
    'Z',
  };

  // ═════════════════════════════════════════════════════════════════════
  // ANA FONKSİYON: Bir kelimeyi akıllıca düzelt
  // ═════════════════════════════════════════════════════════════════════
  /// Verilen kelimeyi akıllıca düzeltir.
  /// "0PERA" → "OPERA"
  /// "K0T0N" → "KOTON"
  /// "M1GR0S" → "MIGROS"
  ///
  /// Sayı/kod görünümlü ifadelere dokunmaz:
  /// "1234567890" → "1234567890" (VKN, korunur)
  /// "15.05.2026" → "15.05.2026" (tarih, korunur)
  /// "119,40" → "119,40" (fiyat, korunur)
  static String correctWord(String word) {
    if (word.isEmpty || word.length < 2) return word;

    // Adım 1: Bu kelime mi yoksa sayı/kod mu?
    if (!_isLikelyWord(word)) return word;

    // Adım 2: Bilinen marka kontrolü (önce sözlük)
    final brandMatch = _matchKnownBrand(word);
    if (brandMatch != null) return brandMatch;

    // Adım 3: Akıllı rakam→harf dönüşümü
    return _convertDigitsToLetters(word);
  }

  /// Cümleyi (birden çok kelime) düzelt
  /// "0PERA RESTORAN" → "OPERA RESTORAN"
  /// Her kelimeyi ayrı ayrı correctWord'e gönderir.
  static String correctSentence(String sentence) {
    if (sentence.isEmpty) return sentence;

    // Boşluklarla ayır, her parçayı düzelt, geri birleştir
    final words = sentence.split(RegExp(r'(\s+)'));
    final corrected = words.map((w) {
      // Boşluk ise olduğu gibi bırak
      if (w.trim().isEmpty) return w;
      return correctWord(w);
    }).join();

    return corrected;
  }

  // ═════════════════════════════════════════════════════════════════════
  // YARDIMCI: Bu bir kelime mi, sayı/kod mu?
  // ═════════════════════════════════════════════════════════════════════
  static bool _isLikelyWord(String s) {
    // Noktalama temizle
    final clean = s.replaceAll(RegExp(r'[^a-zA-ZğüşıöçĞÜŞİÖÇ0-9]'), '');
    if (clean.isEmpty) return false;

    // Karakter analizi
    int letterCount = 0;
    int digitCount = 0;
    for (int i = 0; i < clean.length; i++) {
      final c = clean[i];
      if (RegExp(r'[a-zA-ZğüşıöçĞÜŞİÖÇ]').hasMatch(c)) {
        letterCount++;
      } else if (RegExp(r'[0-9]').hasMatch(c)) {
        digitCount++;
      }
    }

    // KESIN SAYI: hiç harf yoksa → asla düzeltme
    if (letterCount == 0) return false;

    // KESIN KOD: 10+ haneli VKN, tarih, ETTN, IBAN
    if (clean.length >= 10 && digitCount >= clean.length * 0.7) return false;

    // KESIN FIYAT: virgül veya nokta içeriyorsa ve ondalık formatına benziyorsa
    if (RegExp(r'^\*?\d+[.,]\d{1,3}$').hasMatch(s)) return false;

    // SAAT: 12:30 gibi
    if (RegExp(r'^\d{1,2}:\d{2}').hasMatch(s)) return false;

    // TARİH: 15.05.2026 gibi
    if (RegExp(r'^\d{1,2}[./-]\d{1,2}[./-]\d{2,4}').hasMatch(s)) return false;

    // KELİME: harf oranı %40+ ise
    final letterRatio = letterCount / clean.length;
    return letterRatio >= 0.4;
  }

  // ═════════════════════════════════════════════════════════════════════
  // YARDIMCI: Bilinen markaya eşleştir (fuzzy)
  // ═════════════════════════════════════════════════════════════════════
  static String? _matchKnownBrand(String word) {
    final upper = word.toUpperCase().trim();

    // Adım 1: Direkt eşleşme
    if (_knownBrands.contains(upper)) return upper;

    // Adım 2: 0 → O dönüşümü ile direkt eşleşme dene
    final normalized = upper.replaceAll('0', 'O').replaceAll('1', 'I');
    if (_knownBrands.contains(normalized)) return normalized;

    // Adım 3: Fuzzy eşleştirme (kelime uzunluğu yakın markalarda)
    String? bestMatch;
    int bestDist = 999;

    for (final brand in _knownBrands) {
      // Çok farklı uzunluksa atla
      if ((brand.length - upper.length).abs() > 2) continue;
      // Çok kısa kelimelerde fuzzy yapma (yanlış pozitif riski)
      if (brand.length < 4) continue;

      final dist = _lev(normalized, brand);
      // Hata payı: 4-6 harf = 1, 7+ harf = 2
      final maxDist = brand.length <= 6 ? 1 : 2;

      if (dist <= maxDist && dist < bestDist) {
        bestDist = dist;
        bestMatch = brand;
      }
    }

    return bestMatch;
  }

  // ═════════════════════════════════════════════════════════════════════
  // YARDIMCI: Rakamları harflere akıllıca çevir
  // Sadece kelime bağlamında, ünsüz komşuluğu kontrol ederek
  // ═════════════════════════════════════════════════════════════════════
  static String _convertDigitsToLetters(String word) {
    if (word.length < 2) return word;

    final chars = word.split('');
    bool changed = false;

    for (int i = 0; i < chars.length; i++) {
      final c = chars[i];

      // Sadece rakamları işle
      if (!RegExp(r'[0-9]').hasMatch(c)) continue;

      // Bu rakam harf olabilir mi? (bağlama bak)
      final letter = _digitToLetter[c];
      if (letter == null) continue;

      // Komşuları kontrol et
      final prevChar = i > 0 ? chars[i - 1] : '';
      final nextChar = i < chars.length - 1 ? chars[i + 1] : '';

      // KARAR MANTIK:
      // 1. Eğer önce VE sonra rakam varsa, bu da rakamdır (sayı dizisi)
      //    Örnek: 100, 250, 1234
      if (RegExp(r'[0-9]').hasMatch(prevChar) &&
          RegExp(r'[0-9]').hasMatch(nextChar)) {
        continue; // dokunma
      }

      // 2. Eğer önce harf ya da sonra harf varsa, bu muhtemelen HARF'tir
      //    Örnek: K0TON → KOTON, OPER0 → OPERA değil ama
      //    bu durumda "0" sondaysa ve önce harf varsa harf olabilir
      final prevIsLetter =
          prevChar.isNotEmpty &&
          RegExp(r'[a-zA-ZğüşıöçĞÜŞİÖÇ]').hasMatch(prevChar);
      final nextIsLetter =
          nextChar.isNotEmpty &&
          RegExp(r'[a-zA-ZğüşıöçĞÜŞİÖÇ]').hasMatch(nextChar);

      // En az bir komşusu harf ise, bu rakam harf adayı
      if (prevIsLetter || nextIsLetter) {
        // EK GÜVENLİK: Türkçe hece kuralı kontrolü
        // Eğer "0" iki ünsüz arasında ise → kesinlikle ünlü (O olmalı)
        // Çünkü Türkçe'de iki ünsüz arasında ünlü gelir
        if (_turkishConsonants.contains(prevChar.toUpperCase()) ||
            _turkishConsonants.contains(nextChar.toUpperCase())) {
          chars[i] = letter;
          changed = true;
          continue;
        }

        // Eğer baştaysa ve sonra ünsüz varsa (ÖRN: "0PERA")
        if (i == 0 && _turkishConsonants.contains(nextChar.toUpperCase())) {
          chars[i] = letter;
          changed = true;
          continue;
        }

        // Eğer sondaysa ve önce ünsüz varsa
        if (i == chars.length - 1 &&
            _turkishConsonants.contains(prevChar.toUpperCase())) {
          chars[i] = letter;
          changed = true;
          continue;
        }

        // Genel kelime bağlamı: çevirebilir
        chars[i] = letter;
        changed = true;
      }
    }

    final result = chars.join();

    // EK DOĞRULAMA: Düzeltilmiş kelime tanıdık mı?
    // Eğer marka veritabanında varsa, kesin doğru
    if (changed && _knownBrands.contains(result.toUpperCase())) {
      return result;
    }

    return result;
  }

  // ═════════════════════════════════════════════════════════════════════
  // LEVENSHTEIN MESAFESİ
  // ═════════════════════════════════════════════════════════════════════
  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

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
