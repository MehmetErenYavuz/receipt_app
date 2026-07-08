// ═══════════════════════════════════════════════════════════════════════
// BERT WordPiece Tokenizer (cased) — input_contract.md §3 paritesi
// ═══════════════════════════════════════════════════════════════════════
// dbmdz/distilbert-base-turkish-cased ile birebir: do_lower_case=false,
// strip_accents=null (küçültme yok → aksan korunur), max_length=512 (Faz 7;
// önce 320 idi), truncation_side=right. Girdi `is_split_into_words=True`: her
// "kelime" (ML Kit element metni) ayrı bir birimdir; içeride basic-tokenizer
// (noktalama ayırma) + WordPiece (## devam eki) uygulanır.
//
// `[TYPE=FIS]` (id 32000) / `[TYPE=EARSIV]` (id 32001) TEK parça özel token'dır;
// WordPiece'e SOKULMAZ, doğrudan id'si yazılır (input_contract §2).
//
// Parite çıpası: input_contract §5 örneğinin input_ids[:25] ve word_ids[:25]
// değerleri test/ner_tokenizer_test.dart içinde birebir assert edilir.
// ═══════════════════════════════════════════════════════════════════════

/// Tokenizer çıktısı: model girdileri + kelime hizalaması.
class EncodeResult {
  /// `[CLS] + içerik subword'leri + [SEP]` (int64 id listesi).
  final List<int> inputIds;

  /// `inputIds` ile aynı uzunlukta, hepsi 1 (tek belge, pad yok).
  final List<int> attentionMask;

  /// Her subword'ün ait olduğu kelime indeksi; `[CLS]`/`[SEP]` için `null`.
  /// Bir kelimenin tahmini, o kelimenin İLK subword pozisyonundan okunur.
  final List<int?> wordIds;

  /// Doğal subword uzunluğu `maxLength`'i aştı mı (sonu kesildi mi).
  final bool truncated;

  const EncodeResult({
    required this.inputIds,
    required this.attentionMask,
    required this.wordIds,
    required this.truncated,
  });

  /// `wordIndex` kelimesinin ilk subword'ünün `inputIds` içindeki pozisyonu;
  /// kelime truncation ile kesildiyse `null`.
  int? firstSubwordIndex(int wordIndex) {
    for (int i = 0; i < wordIds.length; i++) {
      if (wordIds[i] == wordIndex) return i;
    }
    return null;
  }
}

class BertWordPieceTokenizer {
  final Map<String, int> vocab;
  final int clsId;
  final int sepId;
  final int padId;
  final int unkId;

  /// Tek-parça özel tokenlar (ör. `[TYPE=FIS]` → 32000). WordPiece'e girmez.
  final Map<String, int> specialTokens;

  static const int _maxInputCharsPerWord = 100;
  static const String _unkToken = '[UNK]';

  BertWordPieceTokenizer._({
    required this.vocab,
    required this.clsId,
    required this.sepId,
    required this.padId,
    required this.unkId,
    required this.specialTokens,
  });

  /// vocab.txt içeriğinden tokenizer kurar (satır no = token id, 0-tabanlı).
  factory BertWordPieceTokenizer.fromVocabString(String content) {
    final lines = content.split('\n');
    final vocab = <String, int>{};
    for (int i = 0; i < lines.length; i++) {
      var tok = lines[i];
      // Windows CRLF: yalnız satır-sonu \r temizlenir (token içeriği değil).
      if (tok.endsWith('\r')) tok = tok.substring(0, tok.length - 1);
      // Dosya sonundaki olası boş satır id uzayını kaydırmamalı.
      if (tok.isEmpty && i == lines.length - 1) continue;
      vocab[tok] = i;
    }

    int idOf(String t, int fallback) => vocab[t] ?? fallback;
    return BertWordPieceTokenizer._(
      vocab: vocab,
      clsId: idOf('[CLS]', 2),
      sepId: idOf('[SEP]', 3),
      padId: idOf('[PAD]', 0),
      unkId: idOf(_unkToken, 1),
      specialTokens: {
        for (final t in const ['[TYPE=FIS]', '[TYPE=EARSIV]'])
          if (vocab.containsKey(t)) t: vocab[t]!,
      },
    );
  }

  /// Kelime listesini (prefix [TYPE=*] dahil) model girdisine çevirir.
  /// `maxLength` CLS/SEP DAHİL üst sınırdır; aşılırsa içerik SAĞDAN kesilir.
  /// Faz 7: model 512 ile eğitildi → çağıran 512 vermeli (parite).
  EncodeResult encode(List<String> words, {int maxLength = 512}) {
    final contentIds = <int>[];
    final contentWordIds = <int>[];

    for (int w = 0; w < words.length; w++) {
      final word = words[w];

      // Özel token (yalnız prefix): doğrudan id, parçalama yok.
      final special = specialTokens[word];
      if (special != null) {
        contentIds.add(special);
        contentWordIds.add(w);
        continue;
      }

      for (final piece in _basicTokenize(word)) {
        for (final id in _wordPiece(piece)) {
          contentIds.add(id);
          contentWordIds.add(w);
        }
      }
    }

    // Truncation (right): içerik, CLS+SEP için yer bırakacak şekilde kesilir.
    final maxContent = maxLength - 2;
    bool truncated = false;
    List<int> ids = contentIds;
    List<int> wIds = contentWordIds;
    if (ids.length > maxContent) {
      ids = ids.sublist(0, maxContent);
      wIds = wIds.sublist(0, maxContent);
      truncated = true;
    }

    final inputIds = <int>[clsId, ...ids, sepId];
    final wordIds = <int?>[null, ...wIds, null];
    final attentionMask = List<int>.filled(inputIds.length, 1);

    return EncodeResult(
      inputIds: inputIds,
      attentionMask: attentionMask,
      wordIds: wordIds,
      truncated: truncated,
    );
  }

  // ── BERT basic tokenizer (cased) ──────────────────────────────────────
  // clean_text → (chinese chars çevresine boşluk) → whitespace split →
  // her parçada noktalama ayırma. Küçültme/aksan-strip YOK.
  List<String> _basicTokenize(String text) {
    final cleaned = _cleanText(text);
    final out = <String>[];
    for (final token in cleaned.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      out.addAll(_splitOnPunctuation(token));
    }
    return out;
  }

  String _cleanText(String text) {
    final sb = StringBuffer();
    for (final cp in text.runes) {
      if (cp == 0 || cp == 0xFFFD || _isControl(cp)) continue;
      if (_isWhitespace(cp)) {
        sb.write(' ');
      } else {
        sb.writeCharCode(cp);
      }
    }
    return sb.toString();
  }

  List<String> _splitOnPunctuation(String token) {
    final runes = token.runes.toList();
    final out = <String>[];
    var current = StringBuffer();
    for (final cp in runes) {
      if (_isPunctuation(cp)) {
        if (current.isNotEmpty) {
          out.add(current.toString());
          current = StringBuffer();
        }
        out.add(String.fromCharCode(cp));
      } else {
        current.writeCharCode(cp);
      }
    }
    if (current.isNotEmpty) out.add(current.toString());
    return out;
  }

  // ── WordPiece: greedy longest-match-first, ## devam eki, [UNK] fallback ──
  List<int> _wordPiece(String token) {
    final runes = token.runes.toList();
    if (runes.length > _maxInputCharsPerWord) return [unkId];

    final subIds = <int>[];
    int start = 0;
    while (start < runes.length) {
      int end = runes.length;
      String? curSub;
      while (start < end) {
        var substr = String.fromCharCodes(runes.sublist(start, end));
        if (start > 0) substr = '##$substr';
        if (vocab.containsKey(substr)) {
          curSub = substr;
          break;
        }
        end--;
      }
      if (curSub == null) {
        // Token'ın herhangi bir parçası eşleşmezse TÜM token [UNK] olur (HF).
        return [unkId];
      }
      subIds.add(vocab[curSub]!);
      start = end;
    }
    return subIds;
  }

  // ── Karakter sınıfları (HF BasicTokenizer ASCII + yaygın Unicode) ──────
  static bool _isWhitespace(int cp) {
    if (cp == 0x20 || cp == 0x09 || cp == 0x0A || cp == 0x0D) return true;
    // Unicode Zs (yaygın olanlar) + satır/paragraf ayraçları.
    if (cp == 0xA0 || cp == 0x1680) return true;
    if (cp >= 0x2000 && cp <= 0x200A) return true;
    if (cp == 0x2028 || cp == 0x2029 || cp == 0x202F || cp == 0x205F ||
        cp == 0x3000) return true;
    return false;
  }

  static bool _isControl(int cp) {
    // Tab/newline/cr whitespace sayılır, control DEĞİL.
    if (cp == 0x09 || cp == 0x0A || cp == 0x0D) return false;
    if (cp < 0x20 || (cp >= 0x7F && cp <= 0x9F)) return true;
    return false;
  }

  static bool _isPunctuation(int cp) {
    // ASCII noktalama (HF ile birebir): 33-47, 58-64, 91-96, 123-126.
    if ((cp >= 33 && cp <= 47) ||
        (cp >= 58 && cp <= 64) ||
        (cp >= 91 && cp <= 96) ||
        (cp >= 123 && cp <= 126)) {
      return true;
    }
    // Yaygın Unicode noktalama (TR fiş bağlamında görülenler).
    if (cp == 0x2018 || cp == 0x2019 || cp == 0x201C || cp == 0x201D ||
        cp == 0x2013 || cp == 0x2014 || cp == 0x2026) {
      return true;
    }
    return false;
  }
}
