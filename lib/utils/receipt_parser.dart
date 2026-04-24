import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/receipt_data.dart';
import '../models/kdv_item.dart';

// ═══════════════════════════════════════════════════════════
// YARDIMCI: Koordinat Tabanlı Satır
// ═══════════════════════════════════════════════════════════
class _Row {
  double yCenter;
  final List<TextElement> elements;

  _Row(this.yCenter, this.elements);

  String get text => elements.map((e) => e.text).join(' ');
  String get upper => text.toUpperCase();

  double get rightX => elements.isEmpty
      ? 0
      : elements.map((e) => e.boundingBox.right.toDouble()).reduce(max);

  double get leftX => elements.isEmpty
      ? 0
      : elements.map((e) => e.boundingBox.left.toDouble()).reduce(min);

  // Satır içindeki tüm fiyat eşleşmeleri
  List<String> allPrices(RegExp reg) =>
      reg.allMatches(text).map((m) => m.group(0)!).toList();

  // En sağdaki fiyat
  String? rightmostPrice(RegExp reg) {
    for (int i = elements.length - 1; i >= 0; i--) {
      if (reg.hasMatch(elements[i].text)) return elements[i].text;
    }
    final all = allPrices(reg);
    return all.isNotEmpty ? all.last : null;
  }
}

// ═══════════════════════════════════════════════════════════
// YARDIMCI: Güven Skorlu Alan Sonucu
// ═══════════════════════════════════════════════════════════
class _Field {
  final String value;
  final double confidence;

  const _Field(this.value, this.confidence);
  static const _Field empty = _Field('', 0.0);
  bool get found => value.isNotEmpty;
}

// ═══════════════════════════════════════════════════════════
// ANA PARSER — Türkiye ÖKC / Fatura / Serbest Meslek Makbuzu
// GİB VUK 435 Tebliği + YN ÖKC Kılavuzu esas alınmıştır.
// ═══════════════════════════════════════════════════════════
class ReceiptParser {
  // ─── Türk Fiş Mevzuatı Keyword Sözlüğü ─────────────────

  static const _totalKw = [
    'TOPLAM',
    'GENEL TOPLAM',
    'G.TOPLAM',
    'GENEL TOP',
    'TOP.',
    'SATIS TOP',
    'SATISTOPLAM',
    'ODENEN',
    'ÖDENECEK',
    'ÖDENENTOP',
    'TAHSIL',
    'TAHSİL',
  ];

  static const _kdvKw = [
    'TOPKDV',
    'TOP KDV',
    'KDV TOPLAM',
    'K.D.V',
    'KATMA DEGER',
    'KATMADEĞERVERGİSİ',
  ];

  // KDV oranı geçen satırları da yakala
  static final _kdvOranReg = RegExp(
    r'%\s*(1|8|10|18|20)\b|\b(1|8|10|18|20)\s*%',
  );

  // Sadece "KDV" kelimesi (TOPKDV değil) — tek KDV satırı
  static final _sadeceKdvReg = RegExp(
    r'(?<![A-ZÇĞİÖŞÜa-zçğışöşü])KDV(?![A-ZÇĞİÖŞÜa-zçğışöşü])',
  );

  static const _paymentKw = [
    'NAKİT',
    'NAKIT',
    'KREDİ KARTI',
    'KREDI KARTI',
    'BANKA KARTI',
    'TEMASSIZ',
    'HEDİYE ÇEKİ',
    'HEDIYE CEKI',
    'EFT',
    'HAVALE',
    'KART',
  ];

  static const _skipKw = [
    'T.C.',
    'www.',
    'http',
    'MALİ DEĞER',
    'MALI DEGER',
    'MALİ SEMBOL',
    'MALI SEMBOL',
    'EKÜ',
    'EKU',
  ];

  static const _belgeKw = {
    'FATURA': 'Fatura',
    'E-FATURA': 'e-Fatura',
    'E-ARŞİV': 'e-Arşiv Fatura',
    'SERBEST MESLEK': 'Serbest Meslek Makbuzu',
    'ÖKC FİŞİ': 'ÖKC Fişi',
    'YAZAR KASA': 'ÖKC Fişi',
    'PERAKENDE SATIS': 'Perakende Satış Fişi',
  };

  static const Map<String, String> _kategoriMap = {
    // Market zinciri
    'MİGROS': 'Market', 'MIGROS': 'Market',
    'BİM': 'Market', 'BIM': 'Market',
    'A101': 'Market', 'A 101': 'Market',
    'ŞOK': 'Market', 'SOK': 'Market',
    'CARREFOUR': 'Market', 'FILE': 'Market',
    'METRO MARKET': 'Market', 'MAKRO': 'Market',
    'HAKMAR': 'Market', 'ÖZDILEK': 'Market',
    // Yakıt
    'SHELL': 'Yakıt', 'OPET': 'Yakıt', 'BP': 'Yakıt',
    'TOTAL': 'Yakıt', 'LUKOIL': 'Yakıt', 'PETROL': 'Yakıt',
    'AKARYAKIT': 'Yakıt', 'MOİL': 'Yakıt', 'MOIL': 'Yakıt',
    'PO': 'Yakıt', // Petrol Ofisi kısaltması
    // Yeme-İçme
    'MCDONALDS': 'Yeme-İçme', 'MCDONALD': 'Yeme-İçme',
    'BURGER': 'Yeme-İçme', 'PIZZA': 'Yeme-İçme',
    'RESTORAN': 'Yeme-İçme', 'RESTAURANT': 'Yeme-İçme',
    'CAFE': 'Yeme-İçme', 'KAFETERYA': 'Yeme-İçme',
    'STARBUCKS': 'Yeme-İçme', 'KAHVE': 'Yeme-İçme',
    'DÖNER': 'Yeme-İçme', 'PIDE': 'Yeme-İçme',
    'KEBAP': 'Yeme-İçme', 'LOKANTA': 'Yeme-İçme',
    // Sağlık
    'ECZANE': 'Sağlık', 'PHARMACY': 'Sağlık',
    'HASTANE': 'Sağlık', 'KLİNİK': 'Sağlık',
    'ECZACILIK': 'Sağlık',
    // Elektronik
    'TEKNOSA': 'Elektronik', 'MEDIAMARKT': 'Elektronik',
    'VATAN': 'Elektronik', 'TURKCELL': 'Elektronik',
    'VODAFONE': 'Elektronik', 'TURK TELEKOM': 'Elektronik',
    // Giyim
    'LC WAIKIKI': 'Giyim', 'LCWAIKIKI': 'Giyim',
    'ZARA': 'Giyim', 'H&M': 'Giyim', 'MANGO': 'Giyim',
    'KOTON': 'Giyim', 'DeFacto': 'Giyim', 'DEFACTO': 'Giyim',
    // Ulaşım
    'TAXI': 'Ulaşım', 'TAKSİ': 'Ulaşım',
    'OTOPARK': 'Ulaşım', 'OTOBUS': 'Ulaşım',
  };

  // Fiyat regex: 1-6 rakam + virgül/nokta + 2 rakam
  static final _priceReg = RegExp(r'\b\d{1,6}[.,]\d{2}\b');

  // ═══════════════════════════════════════════════════════
  // ANA GİRİŞ NOKTASI
  // ═══════════════════════════════════════════════════════
  static ReceiptData parse(RecognizedText ocr) {
    final rows = _buildRows(ocr);
    if (rows.isEmpty) return ReceiptData(uyari: 'Metin okunamadı.');

    // ── Her alanı bağımsız stratejilerle çıkar ──
    final firma = _firma(rows);
    final adres = _adres(rows);
    final vd = _vergiDairesi(rows);
    final vkn = _vergiNo(rows);
    final belge = _belgeTuru(rows);
    final fisNo = _fisNo(rows);
    final seri = _seriNo(rows);
    final zNo = _zNo(rows);
    final tarih = _tarih(rows);
    final saat = _saat(rows);
    final kdvDetay = _kdvDetay(rows); // KDV oranı detayları
    final topKdv = _toplamKdv(rows, kdvDetay);
    final matrah = _matrah(rows);
    final toplam = _toplam(rows, topKdv);
    final odeme = _odemeYontemi(rows);
    final paraUstu = _paraUstu(rows);

    // ── Güven skorları ──
    final Map<String, double> scores = {
      if (firma.found) 'firma': firma.confidence,
      if (vkn.found) 'vergi': vkn.confidence,
      if (tarih.found) 'tarih': tarih.confidence,
      if (saat.found) 'saat': saat.confidence,
      if (topKdv.found) 'kdv': topKdv.confidence,
      if (toplam.found) 'toplam': toplam.confidence,
      if (fisNo.found) 'fisNo': fisNo.confidence,
    };

    // ── Tutarlılık kontrolü ──
    String? uyari;
    if (!toplam.found) {
      uyari = 'Toplam tutar tespit edilemedi. Lütfen kontrol edin.';
    } else if (toplam.confidence < 0.6) {
      uyari = 'Toplam tutar düşük güvenle okundu. Kontrol önerilir.';
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
      toplamKdv: topKdv.value,
      kdvHaricToplam: matrah.value,
      toplamTutar: toplam.value,
      odemeYontemi: odeme.value,
      paraUstu: paraUstu.value,
      kategori: _kategori(firma.value),
      confidenceScores: scores,
      uyari: uyari,
    );
  }

  // ═══════════════════════════════════════════════════════
  // SATIR İNŞA MOTORU
  // ═══════════════════════════════════════════════════════
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

  // ═══════════════════════════════════════════════════════
  // FİRMA ADI
  // ═══════════════════════════════════════════════════════
  static _Field _firma(List<_Row> rows) {
    for (int i = 0; i < rows.length && i < 7; i++) {
      final t = rows[i].text.trim();
      final u = t.toUpperCase();

      if (t.length < 2) continue;
      if (_anyOf(u, _skipKw)) continue;
      if (RegExp(r'^\W+$').hasMatch(t)) continue; // Sadece sembol
      if (RegExp(r'^\d+$').hasMatch(t)) continue; // Sadece rakam

      // VKN satırı değilse
      if (!u.contains('VKN') &&
          !u.contains('V.K.N') &&
          !RegExp(r'\b\d{10,11}\b').hasMatch(t)) {
        // Belge türü satırı değilse
        if (!_anyOf(u, _belgeKw.keys.toList())) {
          return _Field(t, i == 0 ? 0.92 : 0.78);
        }
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════
  // ADRES
  // ═══════════════════════════════════════════════════════
  static _Field _adres(List<_Row> rows) {
    final adresKw = RegExp(
      r'\b(CAD\.?|CADDE|SOK\.?|SOKAK|MAH\.?|MAHALLE|BULVAR|BLV\.?|NO:?|APT\.?|KAT)\b',
      caseSensitive: false,
    );
    for (int i = 1; i < rows.length && i < 10; i++) {
      if (adresKw.hasMatch(rows[i].text)) {
        return _Field(rows[i].text.trim(), 0.82);
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════
  // VERGİ DAİRESİ
  // ═══════════════════════════════════════════════════════
  static _Field _vergiDairesi(List<_Row> rows) {
    for (int i = 0; i < rows.length && i < 12; i++) {
      final u = rows[i].upper;
      if (u.contains(' VD') ||
          u.contains('V.D') ||
          u.contains('VERGİ DAİRESİ') ||
          u.contains('VERGI DAIRESI')) {
        final cleaned = rows[i].text
            .replaceAll(RegExp(r'VD|V\.D\.?', caseSensitive: false), '')
            .replaceAll(RegExp(r'\b\d{10,11}\b'), '')
            .replaceAll(RegExp(r'VKN|V\.K\.N', caseSensitive: false), '')
            .trim();
        if (cleaned.length > 2) return _Field(cleaned, 0.85);
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════
  // VKN / TC NO
  // ═══════════════════════════════════════════════════════
  static _Field _vergiNo(List<_Row> rows) {
    final reg = RegExp(r'\b(\d{10,11})\b');
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      final m = reg.firstMatch(rows[i].text);
      if (m == null) continue;

      final num = m.group(1)!;

      // Telefon filtresi
      if (num.startsWith('0') && num.length == 10) continue;
      // Fiş no / seri no satırı değil
      if (_anyOf(u, ['FIS NO', 'FİŞ NO', 'SERI', 'SERİ', 'Z NO'])) continue;

      final labeled =
          u.contains('VKN') || u.contains('V.K.N') || u.contains('VD');
      final posRatio = i / rows.length;
      return _Field(num, labeled ? 0.97 : (posRatio < 0.4 ? 0.83 : 0.65));
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════
  // BELGE TÜRÜ
  // ═══════════════════════════════════════════════════════
  static _Field _belgeTuru(List<_Row> rows) {
    for (int i = 0; i < rows.length && i < 8; i++) {
      final u = rows[i].upper;
      for (final entry in _belgeKw.entries) {
        if (u.contains(entry.key)) {
          return _Field(entry.value, 0.95);
        }
      }
    }
    return const _Field('ÖKC Fişi', 0.50); // varsayılan
  }

  // ═══════════════════════════════════════════════════════
  // FİŞ NO
  // ═══════════════════════════════════════════════════════
  static _Field _fisNo(List<_Row> rows) {
    final numReg = RegExp(r'\b(\d{3,8})\b');
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (u.contains('FIS NO') ||
          u.contains('FİŞ NO') ||
          u.contains('FISNO') ||
          u.contains('FİŞNO') ||
          u.contains('BELGE NO') ||
          u.contains('BELGE:') ||
          u.contains('FIS:') ||
          u.contains('FİŞ:')) {
        final m = numReg.firstMatch(rows[i].text);
        if (m != null) return _Field(m.group(1)!, 0.93);
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════
  // SERİ NO
  // ═══════════════════════════════════════════════════════
  static _Field _seriNo(List<_Row> rows) {
    // Türk fişlerinde "SERİ: A001" veya "SERİ NO: 001" formatı
    final seriReg = RegExp(
      r'SER[İI]\s*(?:NO\s*)?[:\-]?\s*([A-Z0-9]{3,12})',
      caseSensitive: false,
    );
    for (int i = 0; i < rows.length && i < 15; i++) {
      final m = seriReg.firstMatch(rows[i].text);
      if (m != null) return _Field(m.group(1)!.trim(), 0.90);
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════
  // Z NO (Günlük Z Rapor No)
  // ═══════════════════════════════════════════════════════
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

  // ═══════════════════════════════════════════════════════
  // TARİH
  // ═══════════════════════════════════════════════════════
  static _Field _tarih(List<_Row> rows) {
    final dateReg = RegExp(
      r'\b(0?[1-9]|[12]\d|3[01])[.\-\/](0?[1-9]|1[012])[.\-\/](20\d{2}|\d{2})\b',
    );
    for (int i = 0; i < rows.length; i++) {
      final m = dateReg.firstMatch(rows[i].text);
      if (m == null) continue;

      String raw = m.group(0)!.replaceAll(RegExp(r'[\-\/]'), '.');
      final parts = raw.split('.');
      if (parts.length == 3 && parts[2].length == 2) {
        raw = '${parts[0]}.${parts[1]}.20${parts[2]}';
      }

      if (_validDate(raw)) return _Field(raw, 0.97);
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════
  // SAAT
  // ═══════════════════════════════════════════════════════
  static _Field _saat(List<_Row> rows) {
    final timeReg = RegExp(r'\b([01]?\d|2[0-3])[:;]([0-5]\d)\b');
    for (int i = 0; i < rows.length; i++) {
      final m = timeReg.firstMatch(rows[i].text);
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

  // ═══════════════════════════════════════════════════════
  // KDV ORANI DETAYLARI — En zeki kısım
  // Türk fişlerinde format:
  //   %10   KDV  12,50
  //   %20   KDV   5,00
  //   veya: A %10  matrah: 125,00  kdv: 12,50
  // ═══════════════════════════════════════════════════════
  static List<KdvItem> _kdvDetay(List<_Row> rows) {
    final items = <KdvItem>[];
    // Format 1: Satırda oran + fiyat
    final oranFiyatReg = RegExp(r'%\s*(\d{1,2})\b.*?(\d{1,6}[.,]\d{2})');
    // Format 2: Harf kodu (A, B, C) + oran
    final harfOranReg = RegExp(
      r'\b([ABC])\s*%?\s*(\d{1,2})\b.*?(\d{1,6}[.,]\d{2})',
    );

    final foundOranlar = <String>{};

    for (final row in rows) {
      final u = row.upper;

      // Sadece KDV içeren satırlar (TOPKDV değil)
      if (u.contains('TOPKDV') || u.contains('TOP KDV')) continue;
      if (!u.contains('KDV') && !_kdvOranReg.hasMatch(u)) continue;

      // Format 1
      final m1 = oranFiyatReg.firstMatch(row.text);
      if (m1 != null) {
        final oran = m1.group(1)!;
        final fiyat = _normPrice(m1.group(2)!);
        if (!foundOranlar.contains(oran)) {
          foundOranlar.add(oran);
          // Matrahı bulmaya çalış: ilk fiyat matrah, ikincisi KDV olabilir
          final prices = row.allPrices(_priceReg);
          final matrah = prices.length >= 2 ? _normPrice(prices[0]) : '';
          items.add(KdvItem(oran: '%$oran', matrah: matrah, tutar: fiyat));
        }
      }

      // Format 2
      final m2 = harfOranReg.firstMatch(row.text);
      if (m2 != null && !foundOranlar.contains(m2.group(2))) {
        final oran = m2.group(2)!;
        foundOranlar.add(oran);
        final fiyat = _normPrice(m2.group(3)!);
        items.add(KdvItem(oran: '%$oran', matrah: '', tutar: fiyat));
      }
    }

    return items;
  }

  // ═══════════════════════════════════════════════════════
  // TOPLAM KDV (TOPKDV)
  // ═══════════════════════════════════════════════════════
  static _Field _toplamKdv(List<_Row> rows, List<KdvItem> detay) {
    // Strateji A: "TOPKDV" / "TOP KDV" satırı
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (!_fuzzy(u, 'TOPKDV') && !_fuzzy(u, 'TOP KDV') && !_anyOf(u, _kdvKw))
        continue;

      final p = rows[i].rightmostPrice(_priceReg);
      if (p != null) return _Field(_normPrice(p), 0.94);
    }

    // Strateji B: KDV detaylarını topla
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
        return _Field(total.toStringAsFixed(2), 0.82);
      }
    }

    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════
  // MATRAH (KDV HARİÇ TOPLAM)
  // ═══════════════════════════════════════════════════════
  static _Field _matrah(List<_Row> rows) {
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (u.contains('MATRAH') ||
          u.contains('KDV HARİÇ') ||
          u.contains('KDV HARIC') ||
          u.contains('VERGISIZ') ||
          u.contains('VERGİSİZ')) {
        final p = rows[i].rightmostPrice(_priceReg);
        if (p != null) return _Field(_normPrice(p), 0.90);
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════
  // GENEL TOPLAM — En kritik alan, 4 kademeli strateji
  // VUK 435: TOPKDV'nin hemen altında "TOPLAM" veya "TOP"
  // ═══════════════════════════════════════════════════════
  static _Field _toplam(List<_Row> rows, _Field kdv) {
    _Field best = _Field.empty;

    // ── Strateji 1: Açık etiketli TOPLAM satırı ──
    for (int i = 0; i < rows.length; i++) {
      final u = rows[i].upper;
      if (u.contains('TOPKDV') || u.contains('TOP KDV')) continue;

      bool matched = false;
      for (final kw in _totalKw) {
        if (_fuzzy(u, kw)) {
          matched = true;
          break;
        }
      }
      if (!matched) continue;

      final p = rows[i].rightmostPrice(_priceReg);
      if (p == null) continue;

      final norm = _normPrice(p);
      if (kdv.found && norm == kdv.value) continue; // KDV ile aynı → yanlış

      final exactMatch = _anyOf(u, _totalKw);
      final posBonus = (i / rows.length) >= 0.5 ? 0.05 : 0.0;
      final conf = ((exactMatch ? 0.95 : 0.76) + posBonus).clamp(0.0, 1.0);

      if (conf > best.confidence) best = _Field(norm, conf);
    }

    if (best.confidence >= 0.70) return best;

    // ── Strateji 2: TOPKDV'nin hemen altındaki satır ──
    // VUK 435 standardı: TOPKDV → TOPLAM sırası kesin
    for (int i = 0; i < rows.length - 1; i++) {
      final u = rows[i].upper;
      if (u.contains('TOPKDV') || _anyOf(u, _kdvKw)) {
        // Bir sonraki 1-3 satırda fiyat ara
        for (int j = i + 1; j <= i + 3 && j < rows.length; j++) {
          final p = rows[j].rightmostPrice(_priceReg);
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

    if (best.confidence >= 0.60) return best;

    // ── Strateji 3: Ödeme yöntemi satırındaki tutar ──
    for (int i = rows.length - 1; i >= 0; i--) {
      final u = rows[i].upper;
      if (_anyOf(u, _paymentKw)) {
        final p = rows[i].rightmostPrice(_priceReg);
        if (p != null) {
          final norm = _normPrice(p);
          if (0.68 > best.confidence) best = _Field(norm, 0.68);
          break;
        }
      }
    }

    if (best.confidence >= 0.55) return best;

    // ── Strateji 4 (Fallback): Fişin son %35'indeki en büyük tutar ──
    final startIdx = (rows.length * 0.65).round();
    double maxAmt = 0;
    String maxP = '';
    for (int i = startIdx; i < rows.length; i++) {
      final p = rows[i].rightmostPrice(_priceReg);
      if (p == null) continue;
      final amt =
          double.tryParse(
            p.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), ''),
          ) ??
          0;
      if (amt > maxAmt) {
        maxAmt = amt;
        maxP = p;
      }
    }
    if (maxP.isNotEmpty && 0.48 > best.confidence) {
      best = _Field(_normPrice(maxP), 0.48);
    }

    return best;
  }

  // ═══════════════════════════════════════════════════════
  // ÖDEME YÖNTEMİ
  // ═══════════════════════════════════════════════════════
  static _Field _odemeYontemi(List<_Row> rows) {
    // Mevzuat: Ödeme yöntemi TOPLAM'dan sonra gelir → sondan tara
    for (int i = rows.length - 1; i >= 0; i--) {
      final u = rows[i].upper;
      for (final kw in _paymentKw) {
        if (u.contains(kw)) {
          return _Field(_normOdeme(kw), 0.92);
        }
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════
  // PARA ÜSTÜ
  // ═══════════════════════════════════════════════════════
  static _Field _paraUstu(List<_Row> rows) {
    for (int i = rows.length - 1; i >= 0; i--) {
      final u = rows[i].upper;
      if (u.contains('PARA ÜSTÜ') ||
          u.contains('PARA USTU') ||
          u.contains('ÜSTÜ') ||
          u.contains('USTU')) {
        final p = rows[i].rightmostPrice(_priceReg);
        if (p != null) return _Field(_normPrice(p), 0.88);
      }
    }
    return _Field.empty;
  }

  // ═══════════════════════════════════════════════════════
  // KATEGORİ
  // ═══════════════════════════════════════════════════════
  static String _kategori(String firmaAdi) {
    final u = firmaAdi.toUpperCase();
    for (final entry in _kategoriMap.entries) {
      if (u.contains(entry.key)) return entry.value;
    }
    return 'Diğer';
  }

  // ═══════════════════════════════════════════════════════
  // YARDIMCI METODLAR
  // ═══════════════════════════════════════════════════════

  static String _normPrice(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.');

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
      final day = int.parse(p[0]);
      final month = int.parse(p[1]);
      final year = int.parse(p[2]);
      return day >= 1 &&
          day <= 31 &&
          month >= 1 &&
          month <= 12 &&
          year >= 2000 &&
          year <= 2099;
    } catch (_) {
      return false;
    }
  }

  static bool _anyOf(String src, List<String> kws) =>
      kws.any((kw) => src.contains(kw));

  // Levenshtein tabanlı fuzzy eşleşme
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
