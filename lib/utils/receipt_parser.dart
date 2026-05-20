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

  // ── MÜKEMMEL DOKUNUŞ: Satır oluşur oluşmaz 0/O, 9/0 gibi OCR hatalarını temizler ──
  String get text => elements.map((e) => e.text).join(' ').fixOcrConfusion;
  String get upper => text.toUpperCase();

  List<String> allPrices(RegExp reg) =>
      reg.allMatches(text).map((m) => m.group(0)!).toList();

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
// GLOBAL OCR DÜZELTME FONKSİYONU
// ═══════════════════════════════════════════════════════════════════════
String _ocrClean(String raw) {
  String s = raw;

  // Fiyat bağlamında harf-rakam karışıklıkları
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

  return s;
}

String _cleanRow(String raw) {
  return _ocrClean(raw);
}

// ═══════════════════════════════════════════════════════════════════════
// ANA PARSER (TÜRKİYE ÖKC, E-ARŞİV, YEMEK KARTI, AKARYAKIT, İPTAL UYUMLU)
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
    'T.C.', 'www.', 'http', 'MALİ DEĞER', 'MALI DEGER',
    'MALİ SEMBOL', 'EKÜ', 'EKU', 'TESEKKUR', 'TEŞEKKÜR',
    'SADECE TEMASSIZ', 'BU BELGEYİ', 'BU BELGEYI',
    'TUTAR KARSILIGI', 'TUTAR KARŞILIĞI',
    'MUSTERI NUSHASI', 'MÜŞTERİ NÜSHASI',
    'KART HAMİLİ', 'KART HAMILI',
    'İŞLEMİNİZ ONAYLANDI', 'ISLEMINIZ ONAYLANDI',
    'BANKA REFERANS', 'ONAY KODU', 'ACQUIRER ID',
    'YİNE BEKLERİZ', 'YINE BEKLERIZ', 'AFİYET OLSUN', 'AFIYET OLSUN',
    'İYİ GÜNLER', 'IYI GUNLER', 'HOŞGELDİNİZ', 'HOSGELDINIZ',
    'MÜŞTERİ', 'MUSTERI', 'LÜTFEN', 'LUTFEN', 'BİLGİ FİŞİ', 'BILGI FISI',
    'MERSİS', 'MERSIS', 'IBAN', 'TR',
    'İNDİRİM', 'INDIRIM', 'PUAN', 'MONEY', 'KAZANCINIZ', // Market çöpleri
    'ETTN', // e-Arşiv 32 Haneli UUID Kodu
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
    'ÇİÇEK': 'Diğer',
    'CICEK': 'Diğer',
    'İNCİ ÇİÇEK': 'Diğer',
  };

  static final RegExp _priceReg = RegExp(
    r'\*?\d{1,3}(?:\.\d{3})*[.,]\d{2}(?!\d)',
  );

  static final RegExp _numOnlyReg = RegExp(
    r'\d{1,3}(?:\.\d{3})*[.,]\d{2}(?!\d)',
  );

  // ═══════════════════════════════════════════════════════════════════
  // ANA GİRİŞ NOKTASI
  // ═══════════════════════════════════════════════════════════════════
  static ReceiptData parse(RecognizedText ocr) {
    final rows = _buildRows(ocr);
    if (rows.isEmpty) return ReceiptData(uyari: 'Metin okunamadı.');

    // ── YENİ: İPTAL / İADE FİŞİ KONTROLÜ ──
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
    if (isIptal) {
      // İptal/İade uyarısı en yüksek önceliklidir
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
          finalToplamKdv = kdvDetayToplami
              .toStringAsFixed(2)
              .replaceAll('.', ',');
          uyari =
              (uyari == null ? '' : uyari + '\n') +
              'KDV tutarı yanlış okundu, fiş detaylarından otomatik düzeltildi.';
        } else {
          finalToplamTutar = "";
          if (!isIptal) {
            uyari =
                (uyari == null ? '' : uyari + '\n') +
                'Tutar ve KDV fiziksel olarak imkansız (KDV >= Toplam). Lütfen elle giriniz.';
          }
        }
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
      tarih: tarih.value,
      saat: saat.value,
      kdvDetay: kdvDetay,
      toplamKdv: finalToplamKdv,
      kdvHaricToplam: matrah.value,
      toplamTutar: finalToplamTutar,
      odemeYontemi: odeme.value,
      paraUstu: paraUstu.value,
      kategori: _kategori(firma.value, odeme.value, rows),
      confidenceScores: scores,
      uyari: uyari,
    );
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
  // SATIR İNŞA MOTORU
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
        String cleaned = rows[i].text
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
        final labeled =
            u.contains('VKN') ||
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
  // TARİH
  // ═══════════════════════════════════════════════════════════════════
  static _Field _tarih(List<_Row> rows) {
    final dateReg = RegExp(
      r'(0?[1-9]|[12][0-9]|3[01])[\s.\-\/,:;]+(0?[1-9]|1[012])[\s.\-\/,:;]+(20[1-3][0-9]|[1-2][0-9])',
    );

    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      String cleaned = _ocrClean(rows[i].text);

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
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // KDV ORAN DETAYLARI
  // ═══════════════════════════════════════════════════════════════════
  static List<KdvItem> _kdvDetay(List<_Row> rows) {
    final items = <KdvItem>[];
    final foundOranlar = <String>{};

    final oranFiyatReg = RegExp(r'%\s*(\d{1,2})\b');

    final tableSatirReg = RegExp(
      r'%\s*(\d{1,2})\s+([\d.,]+)\s+\*?([\d.,]+)\s+\*?([\d.,]+)',
    );

    for (final row in rows) {
      final u = row.upper;
      final cleaned = _ocrClean(row.text);

      if (u.contains('TOPKDV') ||
          u.contains('TOP KDV') ||
          u.contains('TOPLAM KDV'))
        continue;
      if (!u.contains('KDV') && !oranFiyatReg.hasMatch(cleaned)) continue;

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

      final oranMatches = oranFiyatReg.allMatches(cleaned);
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
        }
      }
    }

    return items;
  }

  // ═══════════════════════════════════════════════════════════════════
  // TOPLAM KDV
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
  // GENEL TOPLAM (YENİ: Ara Toplam Koruması Eklendi)
  // ═══════════════════════════════════════════════════════════════════
  static _Field _toplam(List<_Row> rows, _Field kdv, bool isBankaDekontu) {
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

      // ── YENİ: ARA TOPLAM KORUMASI ──
      // Eğer satırda "ARA" kelimesi geçiyorsa bu kesinlikle Genel Toplam değildir, atla.
      if (u.contains('ARA TOP') ||
          u.contains('ARATOP') ||
          u.contains('ARA TOPLAM'))
        continue;

      if (u.contains('TOPKDV') || u.contains('TOP KDV')) continue;
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

      if (kdv.found && norm == kdv.value) continue;
      final kdvVal = double.tryParse(kdv.value) ?? 0;
      final toplamVal = double.tryParse(norm) ?? 0;
      if (kdv.found && toplamVal < kdvVal && toplamVal > 0) continue;

      final exactMatch = _anyOf(u, _totalKw);
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
        u.contains('YEMEK ÇEKİ'))
      return 'Yemek Kartı';
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
