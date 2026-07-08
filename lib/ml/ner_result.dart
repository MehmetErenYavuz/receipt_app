// ═══════════════════════════════════════════════════════════════════════
// §5.2 ÇIKTI ŞEMASI — output_contract.md (muhasebeciye giden son format)
// ═══════════════════════════════════════════════════════════════════════
// Yalnız BULUNAN alanlar `fields`'a girer. Para alanları float (2 hane).
// `toJson()` dokümandaki §5.2 JSON'u birebir üretir.
// ═══════════════════════════════════════════════════════════════════════

/// Basit "value + confidence" alanı (vendor, date, time, doc_no, total, ...).
class NerValueField {
  final Object value; // String veya double
  final double confidence;
  const NerValueField(this.value, this.confidence);
}

/// TAX_ID özel alanı: kind (VKN/TCKN/null) + checksum durumu.
class NerTaxIdField {
  final String value; // haneler
  final String? kind; // "VKN" | "TCKN" | null
  final bool checksumOk;
  final double confidence;
  const NerTaxIdField(this.value, this.kind, this.checksumOk, this.confidence);

  Map<String, dynamic> toJson() => {
        'value': value,
        'kind': kind,
        'checksum_ok': checksumOk,
        'confidence': confidence,
      };
}

/// MERSIS: excel=false (Excel'e YAZILMAZ — yanlış-pozitif sigortası).
class NerMersisField {
  final String value;
  final bool excel;
  final double confidence;
  const NerMersisField(this.value, this.confidence, {this.excel = false});

  Map<String, dynamic> toJson() => {
        'value': value,
        'excel': excel,
        'confidence': confidence,
      };
}

/// KDV: oran-bazlı tutar/matrah + toplam. `source` bilgi amaçlı ("ner"|"derived").
class NerVatInfo {
  /// oran (1/10/20) → KDV tutarı
  final Map<int, double> vat;

  /// oran (1/10/20) → matrah (= vat_x / (oran/100), türetilmiş)
  final Map<int, double> base;
  final double? vatTotal;
  final String source; // "ner" | "derived"

  const NerVatInfo({
    required this.vat,
    required this.base,
    required this.vatTotal,
    required this.source,
  });

  bool get isEmpty => vat.isEmpty && vatTotal == null;

  /// Σ vat_x (oran tutarlarının toplamı).
  double get sumRates => vat.values.fold(0.0, (a, b) => a + b);

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    for (final e in vat.entries) {
      m['vat_${e.key}'] = e.value;
    }
    for (final e in base.entries) {
      m['base_${e.key}'] = e.value;
    }
    if (vatTotal != null) m['vat_total'] = vatTotal;
    m['_source'] = source;
    return m;
  }
}

/// §5.2 tek belge çıktısı.
class NerResult {
  final String docType; // "fis" | "earsiv"
  final double docTypeConfidence;
  final bool docTypeAmbiguous;

  NerValueField? vendorName;
  NerTaxIdField? taxId;
  NerValueField? taxOffice;
  NerValueField? date; // ISO veya ham
  NerValueField? time;
  NerValueField? docNo;
  NerValueField? total; // double
  NerValueField? subtotal; // double
  NerValueField? cardPaid; // double
  NerValueField? cashPaid; // double
  NerVatInfo? vat;
  NerMersisField? mersisNo;
  final List<String> warnings;

  NerResult({
    required this.docType,
    required this.docTypeConfidence,
    this.docTypeAmbiguous = false,
    List<String>? warnings,
  }) : warnings = warnings ?? [];

  Map<String, dynamic> toJson() {
    final fields = <String, dynamic>{};
    void put(String key, NerValueField? f) {
      if (f != null) {
        fields[key] = {'value': f.value, 'confidence': f.confidence};
      }
    }

    put('vendor_name', vendorName);
    if (taxId != null) fields['tax_id'] = taxId!.toJson();
    put('tax_office', taxOffice);
    put('date', date);
    put('time', time);
    put('doc_no', docNo);
    put('total', total);
    put('subtotal', subtotal);
    put('card_paid', cardPaid);
    put('cash_paid', cashPaid);
    if (vat != null && !vat!.isEmpty) fields['vat'] = vat!.toJson();
    if (mersisNo != null) fields['mersis_no'] = mersisNo!.toJson();

    return {
      'doc_type': docType,
      'doc_type_confidence': docTypeConfidence,
      if (docTypeAmbiguous) 'doc_type_ambiguous': true,
      'fields': fields,
      'warnings': warnings,
    };
  }
}
