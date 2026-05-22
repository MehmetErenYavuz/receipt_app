import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  OcrService._internal();

  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  Future<RecognizedText?> processImage(XFile imageFile) async {
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final result = await _textRecognizer.processImage(inputImage);
      print("═══ ML KİT HAM METİN ═══");
      print(result.text);
      print("═══ METİN SONU ═══");
      return result;
    } catch (e) {
      print("OCR Hatası: $e");
      return null;
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
