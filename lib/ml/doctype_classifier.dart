// ═══════════════════════════════════════════════════════════════════════
// DOCTYPE HEURİSTİĞİ — doctype_logic.md portu (fis | earsiv)
// ═══════════════════════════════════════════════════════════════════════
// `[TYPE=FIS]`/`[TYPE=EARSIV]` prefix'ini ve §5.2 doc_type alanını belirler.
// Gold 48'de %100 isabetli (48/48). Karar SIRALI ve asimetriktir: belirleyici
// e-arşiv sinyali (ETTN/GİB/"E-ARŞİV") fiş işaretlerini her zaman yener.
// Kaynak: src/doctype.py:heuristic_doctype + src/patterns.py
// ═══════════════════════════════════════════════════════════════════════

class DoctypeResult {
  /// "fis" | "earsiv"
  final String docType;
  final double confidence;
  final bool ambiguous;

  const DoctypeResult(this.docType, this.confidence, {this.ambiguous = false});

  /// input_contract §2 prefix token'ı.
  String get prefixToken => docType == 'earsiv' ? '[TYPE=EARSIV]' : '[TYPE=FIS]';
}

class DoctypeClassifier {
  // ── E-arşiv belirleyici sinyaller (yapısal — yalnız e-arşiv/e-faturada) ──
  static final RegExp _ettnReg = RegExp(
      r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b');
  // GİB no: 3 önek karakteri + "20" + 11 hane; önekte ≥1 HARF (saf 16-haneli
  // sayıyı = MERSIS/tutar bloğunu eler).
  static final RegExp _gibReg = RegExp(r'\b([A-Z0-9]{3}20\d{11})\b');
  static const List<String> _earsivText = [
    'E-ARŞİV', 'E-ARSIV', 'E ARŞİV', 'E ARSIV', 'E-FATURA', 'E FATURA',
    'EARŞIV', 'EARSIV', 'ELEKTRONİK ARŞİV', 'ELEKTRONIK ARSIV',
  ];

  // ── Fiş işaretleri ──
  static final RegExp _okcReg = RegExp(r'\b([A-Z]{2}\s?\d{8})\b');
  static const List<String> _strongFisText = [
    'EKÜ', 'EKU', 'ÖKC', 'OKC', 'YAZARKASA', 'YAZAR KASA',
    'Z NO', 'ZNO', 'Z-NO', 'FİŞ NO', 'FIS NO',
  ];
  static const List<String> _weakFisText = [
    'MALİ', 'MALI', 'BİLGİ FİŞİ', 'BILGI FISI',
  ];

  // ── Zayıf ipucu (belirleyici DEĞİL) ──
  static final RegExp _faturaNoReg = RegExp(
      r'(?:FATURA|BELGE|FATURA\s*NU)\s*N[O0]\.?\s*[:.\-]?\s*([A-Z0-9]{8,})',
      caseSensitive: false);

  /// `docText` = belgenin TÜM element metinleri (ham token'lar boşlukla
  /// birleştirilmiş). U = upper. Karar sıralı.
  static DoctypeResult classify(String docText) {
    final u = docText.toUpperCase();

    final hasEttn = _ettnReg.hasMatch(docText);
    final hasGib = _hasGib(u);
    final hasEarsivText = _earsivText.any(u.contains);
    final hasOkc = _okcReg.hasMatch(u);
    final hasFaturaNo = _faturaNoReg.hasMatch(docText);

    final strongFis = hasOkc || _strongFisText.any(u.contains);
    final anyFisHint = strongFis || _weakFisText.any(u.contains);

    final decisiveEarsiv = hasEttn || hasGib || hasEarsivText;

    if (decisiveEarsiv) {
      // 1) belirleyici e-arşiv → fiş işaretini geçersiz kılar
      return const DoctypeResult('earsiv', 0.97);
    } else if (hasFaturaNo && anyFisHint) {
      // 2) ÇELİŞKİ: FATURA NO + fiş ipucu → belirsiz, default fis
      return const DoctypeResult('fis', 0.50, ambiguous: true);
    } else if (strongFis) {
      // 3) saf fiş
      return const DoctypeResult('fis', 0.95);
    } else if (hasFaturaNo) {
      // 4) yalnız FATURA NO başlığı → zayıf earsiv
      return const DoctypeResult('earsiv', 0.70);
    } else {
      // 5) sinyalsiz → varsayılan fiş (en yaygın)
      return const DoctypeResult('fis', 0.55);
    }
  }

  static bool _hasGib(String upper) {
    for (final m in _gibReg.allMatches(upper)) {
      final prefix = m.group(1)!.substring(0, 3);
      if (prefix.contains(RegExp(r'[A-Z]'))) return true;
    }
    return false;
  }
}
