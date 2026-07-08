// ═══════════════════════════════════════════════════════════════════════
// id2label — 31 model çıktı indeksi → BIO etiketi (id2label.json / config.json)
// ═══════════════════════════════════════════════════════════════════════
// Sabit ve asla değişmez (model bununla eğitildi); asset yerine const tutulur.
// ═══════════════════════════════════════════════════════════════════════

const List<String> kId2Label = [
  'O', // 0
  'B-VENDOR_NAME', // 1
  'I-VENDOR_NAME', // 2
  'B-TAX_ID', // 3
  'I-TAX_ID', // 4
  'B-TAX_OFFICE', // 5
  'I-TAX_OFFICE', // 6
  'B-DATE', // 7
  'I-DATE', // 8
  'B-TIME', // 9
  'I-TIME', // 10
  'B-DOC_NO', // 11
  'I-DOC_NO', // 12
  'B-SUBTOTAL', // 13
  'I-SUBTOTAL', // 14
  'B-TOTAL', // 15
  'I-TOTAL', // 16
  'B-CARD_PAID', // 17
  'I-CARD_PAID', // 18
  'B-CASH_PAID', // 19
  'I-CASH_PAID', // 20
  'B-VAT_1', // 21
  'I-VAT_1', // 22
  'B-VAT_10', // 23
  'I-VAT_10', // 24
  'B-VAT_20', // 25
  'I-VAT_20', // 26
  'B-VAT_TOTAL', // 27
  'I-VAT_TOTAL', // 28
  'B-MERSIS_NO', // 29
  'I-MERSIS_NO', // 30
];

/// Bir logit vektöründe (31 sınıf) en yüksek indeks (argmax).
int argmax31(List<double> logits) {
  int best = 0;
  double bestVal = logits[0];
  for (int i = 1; i < logits.length; i++) {
    if (logits[i] > bestVal) {
      bestVal = logits[i];
      best = i;
    }
  }
  return best;
}
