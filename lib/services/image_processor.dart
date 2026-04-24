import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImageProcessor {
  // Kamera için: Hızlı, minimal işlem (ML Kit zaten iyi okur)
  static Future<XFile> enhanceForCamera(XFile originalFile) async {
    final processedBytes = await compute(_cameraProcess, originalFile.path);
    return _saveProcessed(originalFile.path, processedBytes, "cam");
  }

  // Galeri için: Agresif iyileştirme (bilinmeyen koşullar)
  static Future<XFile> enhanceForGallery(XFile originalFile) async {
    final processedBytes = await compute(_galleryProcess, originalFile.path);
    return _saveProcessed(originalFile.path, processedBytes, "gal");
  }

  static Uint8List _cameraProcess(String imagePath) {
    final bytes = File(imagePath).readAsBytesSync();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // Kamera için sadece hafif iyileştirme
    image = img.grayscale(image);
    image = img.adjustColor(image, contrast: 1.3, brightness: 1.05);

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  static Uint8List _galleryProcess(String imagePath) {
    final bytes = File(imagePath).readAsBytesSync();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // 1. Boyut normalizasyonu (çok büyük = yavaş, çok küçük = hatalı)
    image = _normalizeSize(image, targetLongEdge: 2000);

    // 2. Grayscale
    image = img.grayscale(image);

    // 3. Adaptive contrast (histogram bazlı)
    image = _adaptiveContrast(image);

    // 4. Sharpen — bulanık galeri fotoğrafları için kritik
    image = img.convolution(
      image,
      filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
      div: 1,
    );

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  }

  /// Görüntüyü hedef uzun kenara göre orantılı küçültür
  static img.Image _normalizeSize(
    img.Image image, {
    required int targetLongEdge,
  }) {
    int w = image.width;
    int h = image.height;
    int longEdge = w > h ? w : h;

    if (longEdge <= targetLongEdge) return image; // Zaten küçük, dokunma

    double scale = targetLongEdge / longEdge;
    return img.copyResize(
      image,
      width: (w * scale).round(),
      height: (h * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  /// Histogram analizi ile otomatik kontrast ayarı
  static img.Image _adaptiveContrast(img.Image image) {
    // Piksel yoğunluklarını örnekle
    List<int> samples = [];
    int step = (image.width * image.height / 1000).round().clamp(1, 100);

    for (int i = 0; i < image.width * image.height; i += step) {
      int x = i % image.width;
      int y = i ~/ image.width;
      samples.add(img.getLuminance(image.getPixel(x, y)).round());
    }

    samples.sort();

    // %5 - %95 aralığını kullan (outlier'ları atla)
    int low = samples[(samples.length * 0.05).round()];
    int high = samples[(samples.length * 0.95).round()];

    if (high - low < 30) {
      // Çok düşük kontrast: agresif artır
      return img.adjustColor(image, contrast: 1.8);
    } else if (high - low < 80) {
      return img.adjustColor(image, contrast: 1.4);
    } else {
      // Kontrast zaten iyi
      return img.adjustColor(image, contrast: 1.1);
    }
  }

  static Future<XFile> _saveProcessed(
    String originalPath,
    Uint8List bytes,
    String suffix,
  ) async {
    final String newPath = "${originalPath}_${suffix}_enhanced.jpg";
    await File(newPath).writeAsBytes(bytes);
    return XFile(newPath);
  }
}
