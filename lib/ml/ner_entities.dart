// ═══════════════════════════════════════════════════════════════════════
// BIO ENTITY TOPLAMA — output_contract.md §1-2 portu
// ═══════════════════════════════════════════════════════════════════════
// logits [seq][31] → her KELİMENİN ilk subword'ünün argmax'ı → id2label →
// BIO → entity havuzu {TYPE: [değer1, değer2, ...]}.
//
// Kelime hizalaması (input_contract §3): bir kelimenin yalnız İLK subword'ünün
// tahmini kullanılır; devam subword'leri (aynı word_id tekrarı) ve [CLS]/[SEP]
// (word_id null) yok sayılır. Truncation ile düşen kelimenin (firstPos yok)
// tahmini olmaz → açık entity o sınırda kapatılır.
//
// Entity metni = kelime (element) metinlerinin BOŞLUKLA birleşimi (§2).
// ═══════════════════════════════════════════════════════════════════════

import 'ner_labels.dart';

class NerEntities {
  /// `logits[seq][31]` + `wordIds` (subword→kelime) + `words` (prefix dahil
  /// kelime listesi) → `{TYPE: [değer, ...]}`. Bir tip birden çok kez geçebilir
  /// (çoklu-etiket çözümü postprocess'te).
  static Map<String, List<String>> collect(
    List<List<double>> logits,
    List<int?> wordIds,
    List<String> words,
  ) {
    // Her kelime indeksinin İLK subword pozisyonu (ilk görülme).
    final firstPos = <int, int>{};
    for (int i = 0; i < wordIds.length; i++) {
      final w = wordIds[i];
      if (w != null && !firstPos.containsKey(w)) firstPos[w] = i;
    }

    final entities = <String, List<String>>{};
    String? curType;
    final buf = <String>[];

    void flush() {
      if (curType != null && buf.isNotEmpty) {
        (entities[curType!] ??= <String>[]).add(buf.join(' '));
      }
      curType = null;
      buf.clear();
    }

    for (int w = 0; w < words.length; w++) {
      final pos = firstPos[w];
      if (pos == null) {
        // Kelime truncation ile düştü → tahmin yok; açık entity'yi kapat.
        flush();
        continue;
      }
      final label = kId2Label[argmax31(logits[pos])];

      if (label.startsWith('B-')) {
        flush(); // önceki entity'yi kapat
        curType = label.substring(2);
        buf.add(words[w]);
      } else if (label.startsWith('I-') && label.substring(2) == curType) {
        buf.add(words[w]); // aynı tipin devamı
      } else {
        // "O" veya tip değişimi / uyumsuz I- → kapat.
        flush();
      }
    }
    flush(); // dizinin sonunda açık entity kalmışsa kapat

    return entities;
  }
}
