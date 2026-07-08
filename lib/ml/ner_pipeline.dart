// ═══════════════════════════════════════════════════════════════════════
// NER PIPELINE — orchestrator (input_contract → çıktı → postprocess)
// ═══════════════════════════════════════════════════════════════════════
// Akış (README boru hattı):
//   ocr → rawTokenOrder (HAM, parite) → doctype → [TYPE=*] prefix →
//   WordPiece (320) → ONNX → BIO topla → regex havuzu → postprocess → §5.2
//
// Model VEYA tokenizer yüklenemezse / inference hata atarsa `null` döner →
// çağıran (ReceiptAnalyzer) saf regex sonucuna fallback yapar.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/receipt_data.dart';
import '../utils/receipt_parser.dart';
import 'doctype_classifier.dart';
import 'ner_entities.dart';
import 'ner_postprocess.dart';
import 'ner_regex_pool.dart';
import 'ner_result.dart';
import 'ner_session.dart';
import 'ner_tokenizer.dart';

class NerPipeline {
  NerPipeline._();
  static final NerPipeline instance = NerPipeline._();

  static const String _vocabAsset = 'assets/models/vocab.txt';

  BertWordPieceTokenizer? _tokenizer;
  bool _triedTokenizer = false;

  Future<BertWordPieceTokenizer?> _ensureTokenizer() async {
    if (_tokenizer != null) return _tokenizer;
    if (_triedTokenizer) return null; // bir kez denendi, boşuna tekrar yükleme
    _triedTokenizer = true;
    try {
      final content = await rootBundle.loadString(_vocabAsset);
      _tokenizer = BertWordPieceTokenizer.fromVocabString(content);
      return _tokenizer;
    } catch (e) {
      // ignore: avoid_print
      print('NER tokenizer yüklenemedi (fallback regex): $e');
      return null;
    }
  }

  /// Model + tokenizer'ı önceden yükler (batch öncesi tek sefer ısıtma).
  /// `false` → NER kullanılamaz, çağıran regex'e düşer.
  Future<bool> warmUp() async {
    if (!await NerSession.instance.ensureLoaded()) return false;
    return (await _ensureTokenizer()) != null;
  }

  /// Tek belge inference. §5.2 [NerResult] döner; model/tokenizer yoksa ya da
  /// herhangi bir adım hata atarsa `null` (fallback sinyali).
  ///
  /// [regexData] = `ReceiptParser.parse(ocr)` (çift parse'ı önlemek için dışarıda
  /// üretilip verilir); postprocess'in regex kurtarma havuzunu besler.
  Future<NerResult?> run(RecognizedText ocr, ReceiptData regexData) async {
    try {
      if (!await NerSession.instance.ensureLoaded()) return null;
      final tokenizer = await _ensureTokenizer();
      if (tokenizer == null) return null;

      // 1. HAM token sırası (deterministik tie-break — eğitim girdisiyle parite).
      final rawTokens = ReceiptParser.rawTokenOrder(ocr);
      if (rawTokens.isEmpty) return null;

      // 2. doctype heuristik → [TYPE=*] prefix (input_contract §2).
      final doctype = DoctypeClassifier.classify(rawTokens.join(' '));
      final words = <String>[doctype.prefixToken, ...rawTokens];

      // 3. WordPiece (max_len=512, truncation=right). Faz 7: 320→512 (model
      //    512 ile yeniden eğitildi; uzun fişlerde alttaki TOPLAM/KDV kesilmesin).
      final enc = tokenizer.encode(words, maxLength: 512);

      // 4. ONNX inference → logits[seq][31].
      final logits = NerSession.instance.run(enc.inputIds, enc.attentionMask);

      // 5. argmax → BIO → entity havuzu (output_contract §1-2).
      final nerPool = NerEntities.collect(logits, enc.wordIds, words);

      // 6. regex kurtarma havuzu (yalnız NER boşken doldurur).
      final regexPool = NerRegexPool.fromReceiptData(regexData);

      // 7. HİBRİT postprocess → §5.2.
      return NerPostprocess.build(
        ner: nerPool,
        regex: regexPool,
        doctype: doctype,
        truncated: enc.truncated,
      );
    } catch (e) {
      // ignore: avoid_print
      print('NER pipeline hatası (fallback regex): $e');
      return null;
    }
  }
}
