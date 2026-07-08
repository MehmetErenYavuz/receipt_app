// ═══════════════════════════════════════════════════════════════════════
// ONNX Runtime oturumu — model_int8.onnx çalıştırıcı
// ═══════════════════════════════════════════════════════════════════════
// Girdi: int64 input_ids + attention_mask [1, seq] (onnx ile doğrulandı).
// Çıktı: logits FLOAT [1, seq, 31] → [seq][31] olarak döndürülür.
// Model bir kez yüklenir (lazy, ~68MB). Yükleme hata verirse isAvailable=false
// olur ve çağıran taraf saf-regex parser'a fallback yapar.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

class NerSession {
  NerSession._();
  static final NerSession instance = NerSession._();

  static const String _modelAsset = 'assets/models/model_int8.onnx';

  OrtSession? _session;
  bool _triedLoad = false;

  bool get isAvailable => _session != null;

  /// Modeli bir kez yükler. Başarısızsa false döner (fallback için).
  Future<bool> ensureLoaded() async {
    if (_session != null) return true;
    if (_triedLoad) return false; // bir kez denendi, tekrar boş yere yükleme
    _triedLoad = true;
    try {
      OrtEnv.instance.init();
      final raw = await rootBundle.load(_modelAsset);
      final bytes =
          raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
      final options = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes, options);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('NER modeli yüklenemedi (fallback regex): $e');
      _session = null;
      return false;
    }
  }

  /// Tek belge inference. `logits[seq][31]` döndürür.
  List<List<double>> run(List<int> inputIds, List<int> attentionMask) {
    final session = _session;
    if (session == null) {
      throw StateError('NER oturumu yüklü değil — önce ensureLoaded() çağır.');
    }

    final idsTensor = OrtValueTensor.createTensorWithDataList(
        [inputIds], [1, inputIds.length]);
    final maskTensor = OrtValueTensor.createTensorWithDataList(
        [attentionMask], [1, attentionMask.length]);
    final runOptions = OrtRunOptions();

    List<OrtValue?>? outputs;
    try {
      outputs = session.run(runOptions, {
        'input_ids': idsTensor,
        'attention_mask': maskTensor,
      });
      // value → List<List<List<double>>> [1][seq][31]
      final raw = outputs[0]?.value as List;
      final batch0 = raw[0] as List; // [seq][31]
      return [
        for (final row in batch0) (row as List).cast<double>(),
      ];
    } finally {
      idsTensor.release();
      maskTensor.release();
      runOptions.release();
      if (outputs != null) {
        for (final o in outputs) {
          o?.release();
        }
      }
    }
  }

  void dispose() {
    _session?.release();
    _session = null;
    _triedLoad = false;
  }
}
