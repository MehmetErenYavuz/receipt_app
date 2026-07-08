// ═══════════════════════════════════════════════════════════════════════
// POSTPROCESS / HİBRİT MANTIK — postprocess_logic.md portu (KRİTİK)
// ═══════════════════════════════════════════════════════════════════════
// NER ham BIO → normalize + çoklu-etiket çöz + matematik türet + doğrula → §5.2.
// NER-ÖNCELİK: yapısal alanlarda regex YALNIZ NER boşken doldurur, NER'i EZMEZ.
// parse_money float tuzağına DÜŞME. Kurallar postprocess_logic.md ile birebir.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:math';
import 'doctype_classifier.dart';
import 'ner_result.dart';

class NerPostprocess {
  // ── 1. parse_money — TR para (⚠️ FLOAT TUZAĞI) ──────────────────────────
  /// Sayısal girdi DOĞRUDAN döner (60.0 → 60.0, asla 600.0). Yalnız String
  /// ayrıştırılır: son ayraçtan sonra TAM 2 hane → ondalık; değilse hepsi binlik.
  static double? parseMoney(Object? s) {
    if (s == null) return null;
    if (s is num) return s.toDouble(); // ⚠️ tuzak guard
    if (s is! String) return null;

    final t = s.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (t.isEmpty) return null;

    final dec = max(t.lastIndexOf(','), t.lastIndexOf('.'));
    final frac =
        dec != -1 ? t.substring(dec + 1).replaceAll(RegExp(r'[.,]'), '') : '';

    if (dec != -1 && frac.length == 2) {
      var intPart = t.substring(0, dec).replaceAll(RegExp(r'[.,]'), '');
      if (intPart.isEmpty) intPart = '0';
      return double.tryParse('$intPart.$frac');
    }
    return double.tryParse(t.replaceAll(RegExp(r'[.,]'), ''));
  }

  // ── 2. parse_date → ISO YYYY-MM-DD ──────────────────────────────────────
  static String? parseDate(String s) {
    final m =
        RegExp(r'\b(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})\b').firstMatch(s);
    if (m == null) return null;
    int d = int.parse(m.group(1)!);
    int mo = int.parse(m.group(2)!);
    int y = int.parse(m.group(3)!);
    if (y < 100) y += (y < 70) ? 2000 : 1900;
    if (!(d >= 1 && d <= 31 && mo >= 1 && mo <= 12 && y >= 1900 && y <= 2100)) {
      return null;
    }
    return '${y.toString().padLeft(4, '0')}-'
        '${mo.toString().padLeft(2, '0')}-'
        '${d.toString().padLeft(2, '0')}';
  }

  // ── 3. TAX_ID checksum (gerçek veriyle doğrulanmış) ─────────────────────
  static bool tcknValid(String n) {
    if (!RegExp(r'^\d{11}$').hasMatch(n) || n[0] == '0') return false;
    final d = n.split('').map(int.parse).toList();
    final d10 =
        ((((d[0] + d[2] + d[4] + d[6] + d[8]) * 7 - (d[1] + d[3] + d[5] + d[7])) %
                    10) +
                10) %
            10;
    final d11 = d.sublist(0, 10).reduce((a, b) => a + b) % 10;
    return d[9] == d10 && d[10] == d11;
  }

  static bool vknValid(String n) {
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
    final check = (10 - (total % 10)) % 10;
    return check == d[9];
  }

  static String? taxidKind(String n) {
    if (n.length == 10 && vknValid(n)) return 'VKN';
    if (n.length == 11 && tcknValid(n)) return 'TCKN';
    return null;
  }

  // ── 5. KDV türetme ──────────────────────────────────────────────────────
  /// Tek-oranlı fişte oranı tahmin et ({1,8,10,18,20}); sapma>3% → null.
  static int? inferVatRate(Object? vat, Object? total) {
    final v = parseMoney(vat);
    final t = parseMoney(total);
    if (v == null || t == null || v <= 0 || t <= v) return null;
    final raw = v / (t - v) * 100;
    int best = 1;
    double bestDiff = double.infinity;
    for (final c in const [1, 8, 10, 18, 20]) {
      final diff = (c - raw).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = c;
      }
    }
    return bestDiff <= 3.0 ? best : null;
  }

  static double deriveVatBase(Object? vat, int rate) =>
      _round2(parseMoney(vat)! / (rate / 100));

  // ── yardımcılar ─────────────────────────────────────────────────────────
  static double _round2(double x) => (x * 100).round() / 100;

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// distinct toplam: parse → 2 haneye yuvarla → KÜMEYE koy → topla.
  static double sumDistinct(List<String> cands) {
    final set = <double>{};
    for (final c in cands) {
      final v = parseMoney(c);
      if (v != null) set.add(_round2(v));
    }
    return set.fold(0.0, (a, b) => a + b);
  }

  static List<String> _ner(Map<String, List<String>> ner, String key) =>
      ner[key] ?? const [];
  static List<String> _rgx(Map<String, List<String>> rgx, String key) =>
      rgx[key] ?? const [];

  /// NER-öncelikli kaynak seçimi (NER doluysa NER, değilse regex).
  static List<String> _preferNer(
      Map<String, List<String>> ner, Map<String, List<String>> rgx, String k) {
    final n = _ner(ner, k);
    if (n.isNotEmpty) return n;
    return _rgx(rgx, k);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ANA POSTPROCESS — entity havuzları → §5.2 NerResult
  // ═══════════════════════════════════════════════════════════════════════
  static NerResult build({
    required Map<String, List<String>> ner,
    required Map<String, List<String>> regex,
    required DoctypeResult doctype,
    required bool truncated,
  }) {
    final res = NerResult(
      docType: doctype.docType,
      docTypeConfidence: doctype.confidence,
      docTypeAmbiguous: doctype.ambiguous,
    );

    // ── TOTAL: max(NER ∪ regex) ──
    final totalCands = [..._ner(ner, 'TOTAL'), ..._rgx(regex, 'TOTAL')];
    double? total;
    for (final c in totalCands) {
      final v = parseMoney(c);
      if (v != null && (total == null || v > total)) total = v;
    }
    if (total != null) {
      res.total = NerValueField(
          total, _ner(ner, 'TOTAL').isNotEmpty ? 0.80 : 0.95);
    }

    // ── TAX_ID (§3: NER-lokalizasyon, checksum) ──
    res.taxId = _resolveTaxId(_ner(ner, 'TAX_ID'), _rgx(regex, 'TAX_ID'));

    // ── DATE / TIME / DOC_NO (yapısal, NER-öncelik) ──
    final dateRaw = _structuralPick(ner, regex, 'DATE');
    if (dateRaw != null) {
      final iso = parseDate(dateRaw);
      res.date = NerValueField(
          iso ?? dateRaw, _ner(ner, 'DATE').isNotEmpty ? 0.80 : 0.95);
    }
    final timeRaw = _structuralPick(ner, regex, 'TIME');
    if (timeRaw != null) {
      res.time =
          NerValueField(timeRaw, _ner(ner, 'TIME').isNotEmpty ? 0.80 : 0.95);
    }
    final docNoRaw = _structuralPick(ner, regex, 'DOC_NO');
    if (docNoRaw != null) {
      res.docNo = NerValueField(
          docNoRaw, _ner(ner, 'DOC_NO').isNotEmpty ? 0.80 : 0.95);
    }

    // ── MERSIS (yapısal, excel=false) ──
    final mersisRaw = _structuralPick(ner, regex, 'MERSIS_NO');
    if (mersisRaw != null) {
      final dg = _digits(mersisRaw);
      if (dg.isNotEmpty) {
        res.mersisNo = NerMersisField(
            dg, _ner(ner, 'MERSIS_NO').isNotEmpty ? 0.80 : 0.95);
      }
    }

    // ── VENDOR / TAX_OFFICE (NER yalnız) ──
    final vend = _ner(ner, 'VENDOR_NAME');
    if (vend.isNotEmpty) res.vendorName = NerValueField(vend.first, 0.80);
    final office = _ner(ner, 'TAX_OFFICE');
    if (office.isNotEmpty) res.taxOffice = NerValueField(office.first, 0.80);

    // ── CARD / CASH (§4 distinct + §6 eksik bacak) ──
    final cardSrc = _preferNer(ner, regex, 'CARD_PAID');
    final cashSrc = _preferNer(ner, regex, 'CASH_PAID');
    double card = sumDistinct(cardSrc);
    double cash = sumDistinct(cashSrc);
    final cardFromNer = _ner(ner, 'CARD_PAID').isNotEmpty;
    final cashFromNer = _ner(ner, 'CASH_PAID').isNotEmpty;

    // eksik ödeme bacağı (XOR guard)
    bool cardDerived = false, cashDerived = false;
    if (total != null && (card > 0) != (cash > 0)) {
      final known = card > 0 ? card : cash;
      final missing = _round2(total - known);
      if (missing > 0.01) {
        if (card > 0) {
          cash = missing;
          cashDerived = true;
        } else {
          card = missing;
          cardDerived = true;
        }
      }
    }
    if (card > 0) {
      res.cardPaid = NerValueField(
          _round2(card), cardDerived ? 0.55 : (cardFromNer ? 0.80 : 0.95));
    }
    if (cash > 0) {
      res.cashPaid = NerValueField(
          _round2(cash), cashDerived ? 0.55 : (cashFromNer ? 0.80 : 0.95));
    }

    // ── VAT (§5) ──
    res.vat = _resolveVat(ner, regex, total);

    // ── SUBTOTAL (§6) ──
    final subNer = _ner(ner, 'SUBTOTAL');
    final subRgx = _rgx(regex, 'SUBTOTAL');
    final vatTotal = res.vat?.vatTotal;
    if (subNer.isNotEmpty) {
      final v = parseMoney(subNer.first);
      if (v != null) res.subtotal = NerValueField(v, 0.80);
    } else if (subRgx.isNotEmpty) {
      final v = parseMoney(subRgx.first);
      if (v != null) res.subtotal = NerValueField(v, 0.95);
    } else if (total != null && vatTotal != null) {
      res.subtotal = NerValueField(_round2(total - vatTotal), 0.55);
    }

    // ── 7. Doğrulama → warnings (belgeyi DÜŞÜRMEZ; FINAL float'larla) ──
    final cardFinal = res.cardPaid?.value as double? ?? 0.0;
    final cashFinal = res.cashPaid?.value as double? ?? 0.0;
    if (total != null && (cardFinal > 0 || cashFinal > 0)) {
      final paid = cardFinal + cashFinal;
      if ((paid - total).abs() > max(0.02, total * 0.015)) {
        res.warnings.add('card_cash_sum_mismatch('
            'total=${total.toStringAsFixed(2)},'
            'paid=${paid.toStringAsFixed(2)})');
      }
    }
    final subFinal = res.subtotal?.value as double?;
    if (total != null && subFinal != null) {
      final sumVat = vatTotal ?? (res.vat?.sumRates ?? 0.0);
      final tol = max(0.05, total * (doctype.docType == 'earsiv' ? 0.05 : 0.02));
      if ((subFinal + sumVat - total).abs() > tol) {
        res.warnings.add('vat_sum_total_mismatch('
            'total=${total.toStringAsFixed(2)},'
            'sub+vat=${(subFinal + sumVat).toStringAsFixed(2)})');
      }
    }
    if (truncated) res.warnings.add('input_truncated');

    return res;
  }

  // ── yapısal alan: NER kazanır, regex yalnız NER boşken doldurur ──
  static String? _structuralPick(
      Map<String, List<String>> ner, Map<String, List<String>> rgx, String k) {
    final n = _ner(ner, k);
    if (n.isNotEmpty) return n.first;
    final r = _rgx(rgx, k);
    if (r.isNotEmpty) return r.first;
    return null;
  }

  static NerTaxIdField? _resolveTaxId(
      List<String> nerTax, List<String> rgxTax) {
    if (nerTax.isNotEmpty) {
      // NER içinden checksum geçen İLK; yoksa NER[0]'ı KORU (OCR bozmuş olabilir)
      for (final c in nerTax) {
        final dg = _digits(c);
        final kind = taxidKind(dg);
        if (kind != null) return NerTaxIdField(dg, kind, true, 0.80);
      }
      return NerTaxIdField(_digits(nerTax.first), null, false, 0.80);
    }
    if (rgxTax.isNotEmpty) {
      for (final c in rgxTax) {
        final dg = _digits(c);
        final kind = taxidKind(dg);
        if (kind != null) return NerTaxIdField(dg, kind, true, 0.95);
      }
      return NerTaxIdField(_digits(rgxTax.first), null, false, 0.95);
    }
    return null;
  }

  static NerVatInfo _resolveVat(Map<String, List<String>> ner,
      Map<String, List<String>> regex, double? total) {
    final vat = <int, double>{};
    final base = <int, double>{};
    bool anyFromNer = false;

    // açık oran tutarları (1/10/20) — NER→regex rescue + guard
    final rateAmounts = <int, String>{};
    for (final r in const [1, 10, 20]) {
      final nerCand = _ner(ner, 'VAT_$r');
      final cand = nerCand.isNotEmpty ? nerCand : _rgx(regex, 'VAT_$r');
      if (cand.isEmpty) continue;
      final amt = parseMoney(cand.first);
      if (amt == null || amt <= 0) continue;
      // GUARD: implied base total'i aşamaz
      if (total != null && amt / (r / 100) > total * 1.05) continue;
      rateAmounts[r] = cand.first;
      if (nerCand.isNotEmpty) anyFromNer = true;
    }

    // vat_total: NER→regex, distinct max
    final vtCand = _preferNer(ner, regex, 'VAT_TOTAL');
    double? vatTotal;
    for (final c in vtCand) {
      final v = parseMoney(c);
      if (v != null && (vatTotal == null || v > vatTotal)) vatTotal = v;
    }
    // NOT: VAT_TOTAL'ın NER'den gelmesi `_source`'u "ner" YAPMAZ. `_source`
    // yalnız oran-bazlı tutarlar (vat_1/10/20) doğrudan NER etiketiyse "ner"dir;
    // NER yalnız lump VAT_TOTAL verip oran matematikle çıkarıldıysa "derived"
    // (output_contract §3 worked example: vat_10 inference → _source "derived").

    if (rateAmounts.isNotEmpty) {
      // çok-oranlı: açık tutarlar
      for (final e in rateAmounts.entries) {
        vat[e.key] = parseMoney(e.value)!;
        base[e.key] = deriveVatBase(e.value, e.key);
      }
    } else if (vatTotal != null) {
      // tek-oran inference (NER yalnız VAT_TOTAL verdi)
      final rate = inferVatRate(vatTotal, total);
      if (rate != null) {
        vat[rate] = vatTotal;
        base[rate] = deriveVatBase(vatTotal, rate);
      }
    }

    // vat_total yoksa ama oran tutarları varsa → topla
    if (vatTotal == null) {
      final s = vat.values.fold(0.0, (a, b) => a + b);
      if (s > 0) vatTotal = s;
    }
    if (vatTotal != null) vatTotal = _round2(vatTotal);

    return NerVatInfo(
      vat: vat,
      base: base,
      vatTotal: vatTotal,
      source: anyFromNer ? 'ner' : 'derived',
    );
  }
}
