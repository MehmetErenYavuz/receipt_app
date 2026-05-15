import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Görüntü ön işleme servisi.
/// Kamera ve galeri için ayrı pipeline'lar kullanır.
class ImageProcessor {
  // ── Kamera fotoğrafı: minimal işlem (ML Kit zaten iyi okur) ──────
  static Future<XFile> enhanceForCamera(XFile originalFile) async {
    final processedBytes = await compute(_cameraProcess, originalFile.path);
    return _save(originalFile.path, processedBytes, 'cam');
  }

  // ── Galeri fotoğrafı: agresif iyileştirme ────────────────────────
  static Future<XFile> enhanceForGallery(XFile originalFile) async {
    final processedBytes = await compute(_galleryProcess, originalFile.path);
    return _save(originalFile.path, processedBytes, 'gal');
  }

  // ─────────────────────────────────────────────────────────────────
  // KAMERA PİPELINE (isolate'de çalışır)
  // ─────────────────────────────────────────────────────────────────
  static Uint8List _cameraProcess(String path) {
    final bytes = File(path).readAsBytesSync();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // 1. Boyut normalizasyonu (kamera çok yüksek resolüsyon verebilir)
    image = _normalizeSize(image, 2200);

    // 2. Grayscale
    image = img.grayscale(image);

    // 3. Hafif kontrast artırma
    image = img.adjustColor(image, contrast: 1.25, brightness: 1.03);

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  // ─────────────────────────────────────────────────────────────────
  // GALERİ PİPELINE (isolate'de çalışır)
  // ─────────────────────────────────────────────────────────────────
  static Uint8List _galleryProcess(String path) {
    final bytes = File(path).readAsBytesSync();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // 1. Boyut normalizasyonu
    image = _normalizeSize(image, 2000);

    // 2. Grayscale
    image = img.grayscale(image);

    // 3. Histogram bazlı adaptif kontrast
    image = _adaptiveContrast(image);

    // 4. Sharpen (bulanık galeri fotoğrafları için)
    image = img.convolution(
      image,
      filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
      div: 1,
    );

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  }

  // ─────────────────────────────────────────────────────────────────
  // YARDIMCI: Boyut normalizasyonu
  // ─────────────────────────────────────────────────────────────────
  static img.Image _normalizeSize(img.Image image, int targetLongEdge) {
    final w = image.width;
    final h = image.height;
    final longEdge = w > h ? w : h;
    if (longEdge <= targetLongEdge) return image;

    final scale = targetLongEdge / longEdge;
    return img.copyResize(
      image,
      width: (w * scale).round(),
      height: (h * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // YARDIMCI: Adaptif kontrast
  // Histogram örnekleyerek otomatik kontrast seviyesi belirler
  // ─────────────────────────────────────────────────────────────────
  static img.Image _adaptiveContrast(img.Image image) {
    final List<int> samples = [];
    final int totalPixels = image.width * image.height;
    final int step = (totalPixels / 1500).round().clamp(1, 200);

    for (int i = 0; i < totalPixels; i += step) {
      final x = i % image.width;
      final y = i ~/ image.width;
      samples.add(img.getLuminance(image.getPixel(x, y)).round());
    }

    samples.sort();
    final int low = samples[(samples.length * 0.05).round()];
    final int high = samples[(samples.length * 0.95).round()];
    final int range = high - low;

    double contrastFactor;
    if (range < 25) {
      // Çok düşük kontrast — soluk fiş, agresif artır
      contrastFactor = 1.9;
    } else if (range < 60) {
      contrastFactor = 1.5;
    } else if (range < 100) {
      contrastFactor = 1.25;
    } else {
      // Zaten iyi kontrast
      contrastFactor = 1.05;
    }

    return img.adjustColor(image, contrast: contrastFactor);
  }

  // ─────────────────────────────────────────────────────────────────
  // YARDIMCI: Dosyaya kaydet
  // ─────────────────────────────────────────────────────────────────
  static Future<XFile> _save(
    String originalPath,
    Uint8List bytes,
    String suffix,
  ) async {
    final newPath = '${originalPath}_${suffix}_enhanced.jpg';
    await File(newPath).writeAsBytes(bytes);
    return XFile(newPath);
  }
}
