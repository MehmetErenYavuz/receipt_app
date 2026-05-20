// lib/extensions/string_extensions.dart
//
// ═══════════════════════════════════════════════════════════════════════
// TÜRK FİŞLERİ İÇİN OCR HATA DÜZELTME KÜTÜPHANESİ
// ═══════════════════════════════════════════════════════════════════════
// Bu kütüphane, ML Kit'in Türkçe fişlerde yaptığı yaygın OCR hatalarını
// düzeltir. Mevcut fonksiyonlar (fixOcrConfusion) korunmuş, yeni katmanlar
// eklenmiştir.

extension OcrStringExtension on String {
  // ═════════════════════════════════════════════════════════════════════
  // ANA GETTER — Tüm düzeltmeleri sırayla uygular (geriye dönük uyumlu)
  // ═════════════════════════════════════════════════════════════════════
  String get fixOcrConfusion {
    String result = this; // 'this' burada o anki metni temsil eder

    // ──── KATMAN 1: SAYI/HARF KARIŞIKLIĞI (orijinal) ────
    // Küçük harf 0 düzeltmesi
    result = result.replaceAllMapped(
      RegExp(r'([a-zğüşıöç])0([a-zğüşıöç])'),
      (Match m) => '${m[1]}o${m[2]}',
    );

    // Büyük harf 0 düzeltmesi
    result = result.replaceAllMapped(
      RegExp(r'([A-ZĞÜŞİÖÇ])0([A-ZĞÜŞİÖÇ])'),
      (Match m) => '${m[1]}O${m[2]}',
    );

    // ──── KATMAN 2: BİLİNEN ANAHTAR KELİME DÜZELTMELERİ ────
    // TOPLAM varyasyonları
    result = result.replaceAll('T0PLAM', 'TOPLAM');
    result = result.replaceAll('T9PLAM', 'TOPLAM');
    result = result.replaceAll('TQPLAM', 'TOPLAM');
    result = result.replaceAll('T0PLAН', 'TOPLAM');
    result = result.replaceAll('TOPLAН', 'TOPLAM');

    // KDV varyasyonları
    result = result.replaceAll('K0V', 'KDV');
    result = result.replaceAll('KOV', 'KDV');
    result = result.replaceAll('KБV', 'KDV');

    // TUTAR varyasyonları
    result = result.replaceAll('TUTAк', 'TUTAR');
    result = result.replaceAll('TUTAЯ', 'TUTAR');

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

    // TARİH varyasyonları
    result = result.replaceAll('TAR1H', 'TARIH');
    result = result.replaceAll('TARlH', 'TARIH');

    // ──── KATMAN 3: TÜRKÇE KARAKTER OCR HATALARI ────
    // ML Kit'in Türkçe karakterleri Latin karakterlere dönüştürme hataları
    // Bunlar SADECE belirli bağlamlarda uygulanmalı (Türkçe kelime içinde)

    // Ş ↔ S, ş ↔ s (özellikle "İ" sonrası)
    result = result.replaceAllMapped(
      RegExp(r'\b(F[Iİ])S(\s|$)'),
      (m) => '${m[1]}Ş${m[2]}',
    );

    // ──── KATMAN 4: PARA BİRİMİ DÜZELTMELERİ ────
    // TL/₺ karışıklığı
    result = result.replaceAll(RegExp(r'\bTI\b'), 'TL');
    result = result.replaceAll(RegExp(r'\bTl\b'), 'TL');
    result = result.replaceAll(RegExp(r'\bT\.L\.?\b'), 'TL');

    return result;
  }

  // ═════════════════════════════════════════════════════════════════════
  // YENİ: FİYAT BAĞLAMI OCR DÜZELTMESİ
  // Sadece sayı parçalarındaki harf karışıklıklarını düzeltir
  // Genel metin için kullanılmamalı (firma adlarını bozar)
  // ═════════════════════════════════════════════════════════════════════
  String get fixPriceContext {
    String s = this;

    // Sayı bloklarını bul ve içlerindeki yaygın yanlış karakterleri düzelt
    s = s.replaceAllMapped(RegExp(r'[\d\sOoIlBSGZqQ.,]{4,}(?:TL|₺|TI|Tl)?'), (
      m,
    ) {
      String block = m.group(0)!;
      // Sadece içinde rakam VAR ise düzelt
      if (!RegExp(r'\d').hasMatch(block)) return block;
      return block
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
    });

    return s;
  }

  // ═════════════════════════════════════════════════════════════════════
  // YENİ: TARİH BAĞLAMI DÜZELTMESİ
  // OCR'da tarihte "/" yerine "1" veya "I" görmesi sık görülen bir hata
  // ═════════════════════════════════════════════════════════════════════
  String get fixDateContext {
    String s = this;
    // 15I05I2026 → 15/05/2026 düzeltmesi
    s = s.replaceAllMapped(
      RegExp(r'(\d{2})[Il](\d{2})[Il](\d{4})'),
      (m) => '${m[1]}/${m[2]}/${m[3]}',
    );
    // 15.05/2026 gibi karma ayraç düzeltmesi
    s = s.replaceAllMapped(
      RegExp(r'(\d{2})[.\-/](\d{2})[.\-/](\d{4})'),
      (m) => '${m[1]}/${m[2]}/${m[3]}',
    );
    return s;
  }

  // ═════════════════════════════════════════════════════════════════════
  // YENİ: ONDALIK AYRAÇI NORMALİZE
  // Türk fişlerinde virgül kullanılır ama OCR bazen nokta verir.
  // Tutarlı sonuç için her ikisini de yönetir.
  // ═════════════════════════════════════════════════════════════════════
  String get normalizeDecimal {
    // Sondaki iki haneli ondalık kısımdan önce noktayı virgüle çevir
    // 119.40 → 119,40 (Türk standardı)
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
}
