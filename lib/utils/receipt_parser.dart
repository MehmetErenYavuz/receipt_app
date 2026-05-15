import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/receipt_data.dart';
import '../models/kdv_item.dart';

// ═══════════════════════════════════════════════════════════════════════
// YARDIMCI: Koordinat Tabanlı Satır
// ═══════════════════════════════════════════════════════════════════════
class _Row {
  double yCenter;
  final List<TextElement> elements;

  _Row(this.yCenter, this.elements);

  String get text => elements.map((e) => e.text).join(' ');
  String get upper => text.toUpperCase();

  // Satırdaki tüm fiyat eşleşmeleri
  List<String> allPrices(RegExp reg) =>
      reg.allMatches(text).map((m) => m.group(0)!).toList();

  // En sağdaki fiyat — hem element bazlı hem full-text tarama
  String? rightmostPrice(RegExp reg) {
    for (int i = elements.length - 1; i >= 0; i--) {
      // OCR düzeltmesi uygulanmış metni tara
      final cleaned = _ocrClean(elements[i].text);
      if (reg.hasMatch(cleaned)) return cleaned;
    }
    // Eleman bazlı bulamazsa full text'te ara (OCR birleştirme hataları için)
    final cleaned = _ocrClean(text);
    final all = reg.allMatches(cleaned).map((m) => m.group(0)!).toList();
    return all.isNotEmpty ? all.last : null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// YARDIMCI: Güven Skorlu Alan
// ═══════════════════════════════════════════════════════════════════════
class _Field {
  final String value;
  final double confidence;

  const _Field(this.value, this.confidence);
  static const _Field empty = _Field('', 0.0);
  bool get found => value.isNotEmpty;
}

// ═══════════════════════════════════════════════════════════════════════
// GLOBAL OCR DÜZELTME FONKSİYONU
// Türk termal yazıcılarının en sık yaptığı karışıklıkları düzeltir
// ═══════════════════════════════════════════════════════════════════════
String _ocrClean(String raw) {
  // 1. Asterisk (*) → boşluk (Türk fişlerinde tutar öneki: *170,00)
  //    Asterisk'i koruyoruz sadece fiyat regex'i için soyutluyoruz
  String s = raw;

  // 2. Fiyat bağlamında harf-rakam karışıklıkları
  //    Örn: "17O,00" → "170,00" (O harfi sıfır)
  //    Örn: "1B5,00" → "185,00" (B → 8, sadece rakam bağlamında)
  //    Sadece sayı-virgül-nokta bloklarında uygula
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

  // 3. Noktalı virgül → iki nokta (saat formatında: 14;35 → 14:35)
  //    Zaten varolan mantık korunuyor

  return s;
}

// Tam satır OCR temizleme
String _cleanRow(String raw) {
  return _ocrClean(raw);
}

// ═══════════════════════════════════════════════════════════════════════
// ANA PARSER
// Türkiye ÖKC / e-Fatura / e-Arşiv / Serbest Meslek / Banka Dekontu
// GİB VUK 435 + YN ÖKC Kılavuzu + 12 fiş örneği analizi
// ═══════════════════════════════════════════════════════════════════════
class ReceiptParser {
  // ─── TOPLAM keyword sözlüğü ─────────────────────────────────────────
  // Image 12 (Akköprü): sadece "TOP" yazıyor → eklendi
  // Image 3, 9, 12: "TOPLAM" standart
  // Image 2 sağ (BİM): "Odenecek KDV Dahil Tutar" → eklendi
  // Image 11 sağ (İnci Çiçek): "TOPLAM" standart
  static const List<String> _totalKw = [
    'TOPLAM', 'GENEL TOPLAM', 'G.TOPLAM', 'GENEL TOP',
    'TOP', // Image 12: Akköprü kısa format
    'TOPTUTAR', // bazı yazılımlar
    'SATIS TOP', 'SATISTOPLAM',
    'ODENEN', 'ÖDENECEK', 'ÖDENENTOP',
    'TAHSIL', 'TAHSİL',
    'ODENECEK KDV DAHIL TUTAR', // BİM e-arşiv format (Image 2)
    'TUTAR',
    'TOPLAM TUTAR',
    'Toplam Tutar', // bazı küçük işletme yazılımları
  ];

  // ─── KDV keyword sözlüğü ────────────────────────────────────────────
  // Image 3, 9, 12: "KDV" tek başına
  // Image 4, 8: "TOPKDV"
  // Image 2 sağ (BİM): "TOPLAM KDV"
  // Image 11 sağ (İnci Çiçek): "TOPLAM KDV"
  static const List<String> _kdvKw = [
    'TOPKDV',
    'TOP KDV',
    'TOPLAM KDV',
    'KDV TOPLAM',
    'K.D.V',
    'K.D.V.',
    'KDV', // Doğrudan KDV yazımını ekledik
    'KATMA DEGER',
    'KATMA DEĞER',
    'TOPLAM KDV TUTARI',
    'Toplam KDV',
  ];

  // ─── Ödeme yöntemi ──────────────────────────────────────────────────
  // Image 2 sol (Hacizade): "KREDI" + banka logosu
  // Image 3 (SUAL GIDA): "Banka/Kredi Kartı"
  // Image 6 üst: "TEMASSIZ İŞLEM"
  // Image 9 sol: "KREDI" + TEB
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
    'HEDİYE ÇEKİ',
    'HEDIYE CEKI',
    'EFT',
    'EFT-POS',
    'HAVALE',
    'KART',
  ];

  // ─── Atlanacak satırlar ──────────────────────────────────────────────
  static const List<String> _skipKw = [
    'T.C.', 'www.', 'http', 'MALİ DEĞER', 'MALI DEGER',
    'MALİ SEMBOL', 'EKÜ', 'EKU', 'TESEKKUR', 'TEŞEKKÜR',
    'SADECE TEMASSIZ', 'BU BELGEYİ', 'BU BELGEYI',
    'TUTAR KARSILIGI', 'TUTAR KARŞILIĞI',
    'MUSTERI NUSHASI', 'MÜŞTERİ NÜSHASI',
    'KART HAMİLİ', 'KART HAMILI',
    // Banka POS dekontu satırları — bunlar fiş değil
    'İŞLEMİNİZ ONAYLANDI', 'ISLEMINIZ ONAYLANDI',
    'BANKA REFERANS', 'ONAY KODU',
    'ACQUIRER ID',
  ];

  // ─── Belge türü ──────────────────────────────────────────────────────
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

  // ─── Kategori haritası ──────────────────────────────────────────────
  static const Map<String, String> _kategoriMap = {
    // Market
    'MİGROS': 'Market', 'MIGROS': 'Market',
    'BİM': 'Market', 'BIM': 'Market',
    'A101': 'Market', 'A 101': 'Market',
    'ŞOK': 'Market', 'SOK': 'Market',
    'CARREFOUR': 'Market', 'FILE': 'Market',
    'METRO MARKET': 'Market', 'MAKRO': 'Market',
    'HAKMAR': 'Market', 'ÖZDILEK': 'Market',
    'GRATIS': 'Market', // Image 5: Gratis kozmetik market
    // Yakıt
    'SHELL': 'Yakıt', 'OPET': 'Yakıt', 'BP': 'Yakıt',
    'TOTAL': 'Yakıt', 'LUKOIL': 'Yakıt', 'PETROL': 'Yakıt',
    'AKARYAKIT': 'Yakıt', 'MOİL': 'Yakıt', 'MOIL': 'Yakıt',
    'AUTOPAS': 'Yakıt', 'ALTINPA': 'Yakıt', // Image 10: Altınpa Petrol
    // Yeme-İçme
    'MCDONALDS': 'Yeme-İçme', 'MCDONALD': 'Yeme-İçme',
    'BURGER': 'Yeme-İçme', 'PIZZA': 'Yeme-İçme',
    'RESTORAN': 'Yeme-İçme', 'RESTAURANT': 'Yeme-İçme',
    'CAFE': 'Yeme-İçme', 'KAFETERYA': 'Yeme-İçme',
    'KAHVE': 'Yeme-İçme', 'COFFEE': 'Yeme-İçme',
    'KUNEFE': 'Yeme-İçme', 'DÖNER': 'Yeme-İçme',
    'PIDE': 'Yeme-İçme', 'KEBAP': 'Yeme-İçme',
    'LOKANTA': 'Yeme-İçme', 'STARBUCKS': 'Yeme-İçme',
    'KONAK CAFE': 'Yeme-İçme', // Image 2 orta
    'FERROVIA': 'Yeme-İçme', // Image 9 sol — restoran
    'EKREM COSKUN': 'Yeme-İçme', // Image 9, 11
    'MACKBEAR': 'Yeme-İçme', // Image 9, 10: Mackbear Coffee
    'PEK DÖNER': 'Yeme-İçme', // Image 9, 12
    'CAFFE DI': 'Yeme-İçme', // Image 11, 12: Caffe Di Fiore
    'MIDYECI': 'Yeme-İçme', // Image 6
    'ANADOLU REST': 'Yeme-İçme', // Image 4
    'HACIZADE': 'Yeme-İçme', // Image 2 sol
    // Sağlık
    'ECZANE': 'Sağlık', 'PHARMACY': 'Sağlık',
    'HASTANE': 'Sağlık', 'KLİNİK': 'Sağlık',
    // Elektronik
    'TEKNOSA': 'Elektronik', 'MEDIAMARKT': 'Elektronik',
    'VATAN': 'Elektronik', 'TURKCELL': 'Elektronik',
    // Giyim
    'LC WAIKIKI': 'Giyim', 'LCWAIKIKI': 'Giyim',
    'ZARA': 'Giyim', 'H&M': 'Giyim', 'MANGO': 'Giyim',
    'KOTON': 'Giyim', 'DEFACTO': 'Giyim',
    'NINE WEST': 'Giyim', // Image 1
    // Ulaşım
    'TAXI': 'Ulaşım', 'TAKSİ': 'Ulaşım',
    'OTOPARK': 'Ulaşım', 'SIPAY': 'Ulaşım', // Image 6 üst: Sipay taksi
    // Çiçek
    'ÇİÇEK': 'Diğer', 'CICEK': 'Diğer',
    'İNCİ ÇİÇEK': 'Diğer', // Image 11 sağ
  };

  // Fiyat regex — ASTERISK (*) ÖNEKİNE DİKKAT
  // Türk fişlerinde tutar formatı: *170,00 veya *1.170,00 veya 170,00
  // Asterisk'li ve asterisksiz her iki formatı da yakala
  static final RegExp _priceReg = RegExp(
    r'\*?\d{1,3}(?:\.\d{3})*[.,]\d{2}(?!\d)',
  );

  // Sadece rakam-virgül/nokta formatı (asterisk olmadan, normalize için)
  static final RegExp _numOnlyReg = RegExp(
    r'\d{1,3}(?:\.\d{3})*[.,]\d{2}(?!\d)',
  );

  // ═══════════════════════════════════════════════════════════════════
  // ANA GİRİŞ NOKTASI
  // ═══════════════════════════════════════════════════════════════════
  static ReceiptData parse(RecognizedText ocr) {
    final rows = _buildRows(ocr);
    if (rows.isEmpty) return ReceiptData(uyari: 'Metin okunamadı.');

    // Mali değeri olmayan belgeler (taksi POS fişi vb.)
    final bool maliDegeriYok = rows.any(
      (r) =>
          r.upper.contains('MALİ DEĞERİ YOKTUR') ||
          r.upper.contains('MALI DEGERI YOKTUR'),
    );

    // Banka dekontu mu? (Kart işlemi bilgi fişi — fiş değil)
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
    final toplam = _toplam(rows, topKdv, isBankaDekontu);
    final odeme = _odemeYontemi(rows);
    final paraUstu = _paraUstu(rows);
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
    if (maliDegeriYok) {
      uyari = 'Bu fiş Mali Değeri Yoktur — vergi belgesi değildir.';
    } else if (isBankaDekontu) {
      uyari =
          'Bu bir banka pos dekontu — ödeme belgesidir, vergi fişi değildir.';
    } else if (!toplam.found) {
      uyari = 'Toplam tutar tespit edilemedi. Lütfen kontrol edin.';
    } else if (toplam.confidence < 0.60) {
      uyari = 'Toplam tutar düşük güvenle okundu. Kontrol önerilir.';
    }

    // ── KDV / TOPLAM MATEMATİKSEL SAĞLAMA (ZORUNLU FİLTRE) ──
    String finalToplamKdv = topKdv.value;
    String finalToplamTutar = toplam.value;

    if (toplam.found) {
      double tVal = double.tryParse(toplam.value.replaceAll(',', '.')) ?? 0;
      double kVal = double.tryParse(topKdv.value.replaceAll(',', '.')) ?? 0;

      // Eğer KDV toplamdan büyükse veya eşitse, OCR yanlış sayıları seçmiştir!
      if (kVal > 0 && tVal > 0 && kVal >= tVal) {
        // Genel toplamı tekrar hesapla: KDV detaylarındaki tutarları topla
        double kdvDetayToplami = 0;
        for (var item in kdvDetay) {
          kdvDetayToplami +=
              double.tryParse(item.tutar.replaceAll(',', '.')) ?? 0;
        }

        if (kdvDetayToplami > 0 && kdvDetayToplami < tVal) {
          // Detaylardan KDV'yi kurtardık
          finalToplamKdv = kdvDetayToplami
              .toStringAsFixed(2)
              .replaceAll('.', ',');
          uyari =
              (uyari == null ? '' : uyari + '\n') +
              'KDV tutarı yanlış okundu, fiş detaylarından otomatik düzeltildi.';
        } else {
          // İkisi de kurtarılamadıysa, sistemi hataya zorlama, tutarı temizle ki kullanıcı eliyle girsin
          finalToplamTutar = "";
          uyari =
              (uyari == null ? '' : uyari + '\n') +
              'Tutar ve KDV fiziksel olarak imkansız (KDV >= Toplam). Lütfen elle giriniz.';
        }
      }
    }

    // Mey Studios Standartlarında Temiz Obje İadesi
    return ReceiptData(
      firmaAdi: firma.value,
      firmaAdresi: adres.value,
      vergiDairesi: vd.value,
      vergiTcNo: vkn.value,
      belgeTuru: belge.value,
      fisNo: fisNo.value,
      seriNo: seri.value,
      zNo: zNo.value,
      tarih: tarih.value,
      saat: saat.value,
      kdvDetay: kdvDetay,
      toplamKdv: finalToplamKdv, // Filtreden geçen temiz KDV
      kdvHaricToplam: matrah.value,
      toplamTutar: finalToplamTutar, // Filtreden geçen temiz Toplam
      odemeYontemi: odeme.value,
      paraUstu: paraUstu.value,
      kategori: _kategori(firma.value), // Akıllı kategori burada çalışıyor
      confidenceScores: scores,
      uyari: uyari,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // BANKA DEKONTU TESPİTİ
  // "İŞLEM TUTARI", "ONAY KODU", "BANKA REFERANS" gibi kelimeler varsa
  // bu fiş değil banka pos dekontu
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
      // 3+ banka göstergesi → büyük ihtimalle banka dekontu
      if (bankaIndicators >= 3) return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════
  // SATIR İNŞA MOTORU
  // Dinamik tolerance + OCR temizleme
  // ═══════════════════════════════════════════════════════════════════
  static List<_Row> _buildRows(RecognizedText ocr) {
    final rows = <_Row>[];

    for (final block in ocr.blocks) {
      for (final line in block.lines) {
        for (final el in line.elements) {
          final t = el.text.trim();
          if (t.isEmpty) continue;

          final yc = el.boundingBox.top + el.boundingBox.height / 2;
          final tol = (el.boundingBox.height * 0.55).clamp(8.0, 24.0);

          bool added = false;
          for (final row in rows) {
            if ((row.yCenter - yc).abs() < tol) {
              row.elements.add(el);
              row.yCenter =
                  (row.yCenter * (row.elements.length - 1) + yc) /
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

      // 1. Kurumsal İbare Puanı (+40)
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

      // 2. Bilinen Marka Puanı (+50) - Doğrudan Kategori Map'inden kontrol
      for (String brand in _kategoriMap.keys) {
        if (u.contains(brand)) {
          score += 0.50;
          break;
        }
      }

      // 3. Konum Puanı (En üstteki satırlar daha değerlidir)
      score += (0.20 - (i * 0.03));

      // 4. İstenmeyen Karakter Cezası (Telefon no, VKN falan varsa puan kır)
      if (RegExp(r'\d{5,}').hasMatch(t)) score -= 0.30;
      if (u.contains('VKN') || u.contains('V.D')) score -= 0.50;

      if (score > maxScore) {
        maxScore = score;
        bestField = _Field(t, maxScore.clamp(0.0, 0.99));
      }
    }

    // Eğer hiçbir yüksek puanlı satır bulamazsa ama markalardan biri direkt eşleşirse onu dön
    if (bestField.value.isEmpty || maxScore < 0.20) {
      for (int i = 0; i < rows.length && i < 5; i++) {
        for (String brand in _kategoriMap.keys) {
          if (rows[i].upper.contains(brand)) return _Field(rows[i].text, 0.85);
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
      // Güçlü VD Tespiti
      if (u.endsWith(' VD') ||
          u.endsWith(' VD.') ||
          u.contains('V.D') ||
          u.contains('VERGI DAIRESI') ||
          u.contains('VERGİ DAİRESİ')) {
        // Satırdan VKN, VD kelimesi ve sayılar hariç her şeyi al
        String cleaned = rows[i].text
            .replaceAll(
              RegExp(r'\bVERG[Iİ]\sDA[Iİ]RES[Iİ]\b', caseSensitive: false),
              '',
            )
            .replaceAll(RegExp(r'\bV\.?D\.?\b', caseSensitive: false), '')
            .replaceAll(RegExp(r'\b\d{10,11}\b'), '') // VKN'yi sil
            .replaceAll(RegExp(r'VKN|TCKN|NO|:', caseSensitive: false), '')
            .trim();

        // Eğer satırda sadece VD kelimesi varsa, VD ismi BİR ÜST satırdadır (VUK standardı)
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
  // Image 2 orta (Konak Cafe): "FATSA V.D. T.C. NO 36413057324"
  // Image 3: "SELÇUK VD 7811078852"
  // ═══════════════════════════════════════════════════════════════════
  static _Field _vergiNo(List<_Row> rows) {
    // Kesinlikle 10 veya 11 hane olacak ve kelimenin sınırları belli olacak
    final reg = RegExp(r'\b([1-9]\d{9,10})\b');

    for (int i = 0; i < rows.length; i++) {
      final rowText = _ocrClean(rows[i].text);
      final u = rows[i].upper;

      // Tarih veya Saat satırındaki sayıları atla
      if (RegExp(r'\b\d{2}[./-]\d{2}[./-]\d{4}\b').hasMatch(rowText)) continue;
      if (u.contains('FIS') || u.contains('Z NO')) continue;

      final m = reg.firstMatch(rowText);
      if (m != null) {
        final num = m.group(1)!;
        final labeled =
            u.contains('VKN') ||
            u.contains('VD') ||
            u.contains('TC') ||
            u.contains('NO');
        // VKN bulunduğunda satır indeksini kaydedebiliriz, VD için kullanışlı olur.
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
  // Image 2 sol: "FİŞ No 007x"
  // Image 3: "Fiş No: 0085"
  // Image 9 sol: "FİŞ NO : 0133"
  // ═══════════════════════════════════════════════════════════════════
  static _Field _fisNo(List<_Row> rows) {
    // Türkçe karakter hatalarını (I, İ, S, Ş) ve boşlukları tolere eden güçlü regex
    final fisReg = RegExp(
      r'\b(?:F[Iİıi]S|F[Iİıi][SŞşs]|BELGE|ORD|F)\s*(?:NO)?\s*[:.\-]?\s*(\d{2,8})\b',
      caseSensitive: false,
    );

    for (int i = 0; i < rows.length; i++) {
      final cleaned = _ocrClean(rows[i].text);
      final m = fisReg.firstMatch(cleaned);
      if (m != null) {
        final val = m
            .group(1)!
            .replaceAll(
              RegExp(r'^0+'),
              '',
            ); // Baştaki sıfırları sil (Örn: 0045 -> 45)
        if (val.isNotEmpty) return _Field(val, 0.95);
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // SERİ NO
  // ═══════════════════════════════════════════════════════════════════
  static _Field _seriNo(List<_Row> rows) {
    // "SERI : A" veya "SERİ/SIRA : B" formatlarını yakalar
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
  // Image 2 sol: "Z No:1458"
  // Image 3: "Z No: 0173"
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
  // TARİH
  // Image 2 sol: "01/11/2025" (slash ayraçlı)
  // Image 3: "08.11.2025"
  // Image 9 sol: "07/11/2025"
  // Image 2 orta: "29-11-2025" (tire ayraçlı)
  // ═══════════════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════════════
  // TARİH (GEMİNİ SEVİYESİ TOLERANS MOTORU)
  // Gün/Ay/Yıl, Gün.Ay.Yıl, Gün-Ay-Yıl ve OCR Hatalarını (Virgül, Boşluk) Kapsar
  // ═══════════════════════════════════════════════════════════════════
  static _Field _tarih(List<_Row> rows) {
    // 1. DİKKAT: \b (kelime sınırı) kaldırıldı.
    // Ayraçlara OCR hataları olan virgül (,) ve iki nokta (:) eklendi.
    final dateReg = RegExp(
      r'(0?[1-9]|[12][0-9]|3[01])[\s.\-\/,:;]+(0?[1-9]|1[012])[\s.\-\/,:;]+(20[1-3][0-9]|[1-2][0-9])',
    );

    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      String cleaned = _ocrClean(rows[i].text);

      // GEMİNİ HİLESİ: OCR bazen sayıların arasına boşluk koyar (Örn: "1 2 . 0 4 . 2 0 2 6")
      // Bu satırın tamamen boşluksuz bir kopyasını çıkarıp orada da arama yapacağız
      String noSpaces = cleaned.replaceAll(' ', '');

      // Önce boşluksuz "saf" halinde ara
      Match? m = dateReg.firstMatch(noSpaces);

      // Bulamazsa orijinal temizlenmiş halinde ara
      if (m == null) {
        m = dateReg.firstMatch(cleaned);
      }

      if (m != null) {
        // Tarih parçalarını al ve tek haneli gün/ayları çift haneye tamamla (Örn: 5 -> 05)
        String gun = m.group(1)!.padLeft(2, '0');
        String ay = m.group(2)!.padLeft(2, '0');
        String yil = m.group(3)!;

        // Yıl 2 haneli okunmuşsa (Örn: 25) başına 20 ekle
        if (yil.length == 2) yil = '20$yil';

        String raw = '$gun.$ay.$yil';

        // Kusursuz tarih doğrulaması
        if (_validDate(raw)) {
          // Satırda TARIH, TAR veya TRH kelimesi geçiyorsa bu %100 tarihtir
          final isExplicit = u.contains('TAR') || u.contains('TRH');
          return _Field(raw, isExplicit ? 0.99 : 0.90);
        }
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // SAAT
  // Image 2 sol: "13:48:03" (saniyeli)
  // Image 3: "Saat: 16:06"
  // Image 9: "18:58:51"
  // ═══════════════════════════════════════════════════════════════════
  static _Field _saat(List<_Row> rows) {
    // Saniyeli format da yakala: HH:MM:SS
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
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // KDV ORAN DETAYLARI
  // Image 2 sağ (BİM): "KDV MATRAH KDV TUTAR KDV DAHİL" tablo satırı
  //   %1   51,49   *0,51   *52,00
  //   %10  262,73  *26,27  *289,00
  //   %20  0,42    *0,08   *0,50
  // Image 3: "YIYECEK %10 *170,00" — satır formatı
  // Image 4 sol (Migros): "KDV %20 *13,32 TOPLAM *79,90"
  // ═══════════════════════════════════════════════════════════════════
  static List<KdvItem> _kdvDetay(List<_Row> rows) {
    final items = <KdvItem>[];
    final foundOranlar = <String>{};

    // Pattern 1: Satırda oran + KDV tutarı birlikte
    // Örn: "YIYECEK %10 *170,00"  veya "%10 *12,73"
    final oranFiyatReg = RegExp(r'%\s*(\d{1,2})\b');

    // Pattern 2: BİM e-arşiv tablo satırı
    // "%1  51,49  *0,51  *52,00" — oran + matrah + kdv + kdvli
    final tableSatirReg = RegExp(
      r'%\s*(\d{1,2})\s+([\d.,]+)\s+\*?([\d.,]+)\s+\*?([\d.,]+)',
    );

    for (final row in rows) {
      final u = row.upper;
      final cleaned = _ocrClean(row.text);

      // TOPKDV satırlarını atla
      if (u.contains('TOPKDV') ||
          u.contains('TOP KDV') ||
          u.contains('TOPLAM KDV'))
        continue;
      // KDV içermeyen satırları atla
      if (!u.contains('KDV') && !oranFiyatReg.hasMatch(cleaned)) continue;

      // Pattern 2: BİM tablo satırı (3 tutar var)
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

      // Pattern 1: Oran + tek fiyat
      final oranMatches = oranFiyatReg.allMatches(cleaned);
      for (final om in oranMatches) {
        final oran = om.group(1)!;
        if (foundOranlar.contains(oran)) continue;

        // Bu satırdaki fiyatları bul
        final prices = row.allPrices(_priceReg);
        // Asteriskli fiyatlar bu satırda KDV tutarıdır
        final kdvFiyat = prices
            .where((p) => p.startsWith('*'))
            .map((p) => p.substring(1))
            .firstOrNull;
        // Asterisksiz fiyat matrah olabilir
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
        }
      }
    }

    return items;
  }

  // ═══════════════════════════════════════════════════════════════════
  // TOPLAM KDV
  // ═══════════════════════════════════════════════════════════════════
  static _Field _toplamKdv(List<_Row> rows, List<KdvItem> detay) {
    // Strateji A: "TOPKDV" veya "TOPLAM KDV" içeren satır
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (!_anyOf(u, _kdvKw)) continue;

      final cleaned = _ocrClean(rows[i].text);
      final p = _findRightmostPrice(cleaned, _priceReg);
      if (p != null) return _Field(_normPrice(p), 0.95);
    }

    // Strateji B: KDV detaylarından topla
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

    // Strateji C: Sadece "KDV" geçen satır (TOPLAM değil)
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (!u.contains('KDV')) continue;
      if (_anyOf(u, _totalKw)) continue; // TOPLAM ile birlikteşse atla
      if (u.contains('TOPKDV')) continue;

      final cleaned = _ocrClean(rows[i].text);
      final p = _findRightmostPrice(cleaned, _priceReg);
      if (p != null) return _Field(_normPrice(p), 0.78);
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
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // GENEL TOPLAM — 5 Kademeli Strateji
  //
  // TEMEL KURAL: KDV < TOPLAM olmalı. Eşitlerse veya KDV > TOPLAM ise
  // alan ataması yanlış demektir.
  //
  // Image 3 (SUAL GIDA): "KDV *15,45 / TOPLAM *170,00" — ayrı satır
  // Image 4 sol (Migros): "TOPKDV *13,32 / TOPLAM *79,90"
  // Image 12 orta: "KDV *30,00 / TOP *330,00" — kısa "TOP"
  // Image 2 sağ (BİM): "Odenecek KDV Dahil Tutar *341,50"
  // Image 6 alt (Midyeci): "TOPLAM *930,00"
  // ═══════════════════════════════════════════════════════════════════
  static _Field _toplam(List<_Row> rows, _Field kdv, bool isBankaDekontu) {
    // Banka dekontu ise toplam yerine "İŞLEM TUTARI" alanını kullan
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

    // ── Strateji 1: Açık etiketli TOPLAM satırı ──────────────────────
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;

      // TOPKDV satırlarını kesinlikle atla
      if (u.contains('TOPKDV') || u.contains('TOP KDV')) continue;
      // KDV ile biten satırlar (ör: "TOPLAM KDV") atla
      if (_anyOf(u, _kdvKw) &&
          !_anyOf(u, ['ODENEN', 'ÖDENECEK', 'ODENECEK KDV DAHIL']))
        continue;

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

      // KDV ile aynı değer → yanlış atama, atla
      if (kdv.found && norm == kdv.value) continue;
      // KDV'den küçükse → tutarsız, güveni düşür
      final kdvVal = double.tryParse(kdv.value) ?? 0;
      final toplamVal = double.tryParse(norm) ?? 0;
      if (kdv.found && toplamVal < kdvVal && toplamVal > 0) continue;

      final exactMatch = _anyOf(u, _totalKw);
      // "TOP" kısa eşleşmesi daha az güvenilir
      final isShortMatch =
          u.trim() == 'TOP' ||
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

    // ── Strateji 2: VUK 435 sırası — TOPKDV'nin hemen altı ──────────
    for (int i = 0; i < rows.length - 1; i++) {
      final u = rows[i].upper;
      if (u.contains('TOPKDV') || _anyOf(u, _kdvKw)) {
        for (int j = i + 1; j <= i + 3 && j < rows.length; j++) {
          final jU = rows[j].upper;
          // TOPLAM/TOP satırı ise veya fiyat varsa
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

    // ── Strateji 3: "KDV Dahil Tutar" veya ödeme satırı ─────────────
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

    // ── Strateji 4: "SATIŞ" bloğu altındaki tutar ───────────────────
    // Banka pos fişlerinde "SATIŞ / **** *** 1234 / TUTAR / 170,00 TL"
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

    // ── Strateji 5 (Fallback): Fişin son %35'indeki en büyük tutar ──
    final startIdx = (rows.length * 0.65).round();
    double maxAmt = 0;
    String maxP = '';
    for (int i = startIdx; i < rows.length; i++) {
      final cleaned = _ocrClean(rows[i].text);
      final p = _findRightmostPrice(cleaned, _priceReg);
      if (p == null) continue;
      final norm = _normPrice(p);
      final amt = double.tryParse(norm) ?? 0;
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
  // KATEGORİ
  // ═══════════════════════════════════════════════════════════════════
  static String _kategori(String firmaAdi) {
    final u = firmaAdi.toUpperCase();
    for (final entry in _kategoriMap.entries) {
      if (u.contains(entry.key)) return entry.value;
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
  // Asterisk kaldır, virgülü noktaya çevir
  // ═══════════════════════════════════════════════════════════════════
  static String _normPrice(String raw) {
    return raw
        .replaceAll('*', '') // asterisk kaldır
        .replaceAll(RegExp(r'[^0-9.,]'), '')
        .replaceAll(',', '.');
  }

  static String _normOdeme(String kw) {
    final u = kw.toUpperCase();
    if (u.contains('NAKIT') || u.contains('NAKİT')) return 'Nakit';
    if (u.contains('KREDİ') || u.contains('KREDI')) return 'Kredi Kartı';
    if (u.contains('BANKA')) return 'Banka Kartı';
    if (u.contains('TEMASSIZ')) return 'Temassız';
    if (u.contains('KART')) return 'Kart';
    if (u.contains('HEDİYE') || u.contains('HEDIYE')) return 'Hediye Çeki';
    if (u.contains('EFT') || u.contains('HAVALE')) return 'EFT/Havale';
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
    for (final word in src.split(RegExp(r'\s+'))) {
      if (word.length >= target.length - 1 &&
          word.length <= target.length + 1) {
        if (_lev(word, target) <= (target.length <= 4 ? 1 : 2)) return true;
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
