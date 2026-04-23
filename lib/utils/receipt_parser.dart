import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/receipt_data.dart';

class ReceiptRow {
  double yCenter;
  List<TextElement> elements;
  ReceiptRow(this.yCenter, this.elements);
  String get fullText => elements.map((e) => e.text).join(" ");
}

class ReceiptParser {
  static ReceiptData parse(RecognizedText recognizedText) {
    ReceiptData data = ReceiptData();
    List<ReceiptRow> rows = [];

    // 1. KOORDİNAT TABANLI SATIR OLUŞTURMA (Hizalama Analizi)
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        for (TextElement element in line.elements) {
          double elementYCenter =
              element.boundingBox.top + (element.boundingBox.height / 2);
          bool added = false;
          for (ReceiptRow row in rows) {
            if ((row.yCenter - elementYCenter).abs() < 15.0) {
              row.elements.add(element);
              row.yCenter = (row.yCenter + elementYCenter) / 2;
              added = true;
              break;
            }
          }
          if (!added) rows.add(ReceiptRow(elementYCenter, [element]));
        }
      }
    }

    rows.sort((a, b) => a.yCenter.compareTo(b.yCenter));
    for (var row in rows) {
      row.elements.sort(
        (a, b) => a.boundingBox.left.compareTo(b.boundingBox.left),
      );
    }

    RegExp priceRegExp = RegExp(r'\b\d{1,5}[.,]\d{2}\b');

    // 2. GELİŞMİŞ VERİ AYIKLAMA (Proximity & Context Logic)
    for (int i = 0; i < rows.length; i++) {
      String rowText = rows[i].fullText.toUpperCase();

      // --- TOPLAM TUTAR VE KDV AYRIŞTIRMA ---
      // "TOPLAM" kelimesini içeren ama "KDV" içermeyen satırları ara
      if (_fuzzyContains(rowText, "TOPLAM") ||
          _fuzzyContains(rowText, "GENEL TOP") ||
          _fuzzyContains(rowText, "ODENEN")) {
        // Eğer satırda "KDV" geçiyorsa bu KDV toplamıdır, genel toplam değildir
        if (_fuzzyContains(rowText, "KDV") ||
            _fuzzyContains(rowText, "TOPKDV")) {
          String? price = _findPriceInRow(rows[i], priceRegExp);
          if (price != null) data.toplamKdv = _formatPrice(price);
        } else {
          // KDV içermeyen düz TOPLAM satırı
          String? price = _findPriceInRow(rows[i], priceRegExp);
          if (price != null) data.toplamTutar = _formatPrice(price);
        }
      }
      // Sadece KDV veya TOPKDV yazan satırlar için (alternatif)
      else if (_fuzzyContains(rowText, "TOPKDV") ||
          (_fuzzyContains(rowText, "KDV") && rowText.length < 15)) {
        String? price = _findPriceInRow(rows[i], priceRegExp);
        if (price != null) data.toplamKdv = _formatPrice(price);
      }

      // --- TARİH VE SAAT ---
      _parseDateTime(rowText, data);

      // --- VKN / TC ---
      if (_fuzzyContains(rowText, "VKN") ||
          _fuzzyContains(rowText, "VD") ||
          _fuzzyContains(rowText, "TC")) {
        RegExp vknReg = RegExp(r'\b\d{10,11}\b');
        Match? match = vknReg.firstMatch(rowText);
        if (match != null) data.vergiTcNo = match.group(0)!;
      }
    }

    // Firma adını ilk 3 satırdan al (Daha güvenli)
    if (rows.length > 0) data.firmaAdi = rows[0].fullText;

    return data;
  }

  // Satır içindeki kelimenin sağında kalan rakamı bulur
  static String? _findPriceInRow(ReceiptRow row, RegExp reg) {
    // Satırı sondan başa doğru tara (Fiyatlar genelde en sağdadır)
    for (int i = row.elements.length - 1; i >= 0; i--) {
      String text = row.elements[i].text;
      if (reg.hasMatch(text)) {
        return text;
      }
    }
    return null;
  }

  static void _parseDateTime(String text, ReceiptData data) {
    RegExp dReg = RegExp(
      r'\b(0?[1-9]|[12]\d|3[01])[./](0?[1-9]|1[012])[./](\d{4}|\d{2})\b',
    );
    RegExp tReg = RegExp(r'\b([01]?\d|2[0-3])[:;]([0-5]\d)\b');

    if (data.tarih.isEmpty) {
      Match? m = dReg.firstMatch(text);
      if (m != null) data.tarih = m.group(0)!.replaceAll('/', '.');
    }
    if (data.saat.isEmpty) {
      Match? m = tReg.firstMatch(text);
      if (m != null) data.saat = m.group(0)!.replaceAll(';', ':');
    }
  }

  static bool _fuzzyContains(String source, String target) {
    if (source.contains(target)) return true;
    List<String> words = source.split(RegExp(r'\s+'));
    for (String word in words) {
      if (word.length >= target.length - 1 &&
          word.length <= target.length + 1) {
        if (_levenshtein(word, target) <= (target.length <= 4 ? 1 : 2))
          return true;
      }
    }
    return false;
  }

  static int _levenshtein(String a, String b) {
    List<int> v0 = List<int>.generate(b.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(b.length + 1, 0);
    for (int i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        int cost = (a[i] == b[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      v0 = List.from(v1);
    }
    return v0[b.length];
  }

  static String _formatPrice(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.');
  }
}
