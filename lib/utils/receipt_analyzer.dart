// ═══════════════════════════════════════════════════════════════════════
// RECEIPT ANALYZER — tek giriş noktası (NER birincil + regex fallback)
// ═══════════════════════════════════════════════════════════════════════
// UI/batch çağrı noktaları `ReceiptParser.parse` yerine bunu kullanır:
//   1) regex parser çalışır (olgun, her zaman bir sonuç üretir + rescue havuzu)
//   2) NER pipeline denenir → başarılıysa §5.2 ReceiptData'ya map'lenir
//   3) model yok / hata → saf regex sonucu döner (fallback)
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../ml/ner_mapper.dart';
import '../ml/ner_pipeline.dart';
import '../models/receipt_data.dart';
import 'receipt_parser.dart';

class ReceiptAnalyzer {
  /// Foto OCR çıktısını analiz eder. NER varsa NER-birincil sonuç, yoksa regex.
  static Future<ReceiptData> analyze(RecognizedText ocr) async {
    final regexData = ReceiptParser.parse(ocr);
    final ner = await NerPipeline.instance.run(ocr, regexData);
    if (ner == null) {
      if (kDebugMode) print('═══ NER ÇALIŞMADI (regex fallback) ═══');
      return regexData; // model yok / hata → fallback
    }
    final mapped = mapNerToReceipt(ner, base: regexData);
    if (kDebugMode) {
      // Python §5.2 çıktısıyla kıyas için ham JSON (yalnız debug build).
      print('═══ NER §5.2 ═══\n${mapped.nerJson}\n═══════════════');
    }
    return mapped;
  }

  /// Batch öncesi modeli bir kez ısıtır (ilk fişte gecikmeyi azaltır). NER
  /// kullanılamıyorsa `false` — analyze yine regex'e fallback yapar.
  static Future<bool> warmUp() => NerPipeline.instance.warmUp();
}
