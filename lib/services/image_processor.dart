import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Görüntü ön işleme servisi.
/// Kamera, galeri ve BURUŞUK fişler için ayrı pipeline'lar kullanır.
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
  // BURUŞUK FİŞ PIPELINE
  // Buruşuk/eğri/soluk fişler için en agresif iyileştirme
  // ─────────────────────────────────────────────────────────────────
  static Future<XFile> enhanceForCrumpled(XFile originalFile) async {
    final processedBytes = await compute(_crumpledProcess, originalFile.path);
    return _save(originalFile.path, processedBytes, 'crumpled');
  }

  // ─────────────────────────────────────────────────────────────────
  // KAMERA PİPELINE (isolate'de çalışır) - DOKUNULMADI
  // ─────────────────────────────────────────────────────────────────
  static Uint8List _cameraProcess(String path) {
    final bytes = File(path).readAsBytesSync();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    image = _normalizeSize(image, 2200);
    image = img.grayscale(image);
    image = img.adjustColor(image, contrast: 1.25, brightness: 1.03);

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  // ─────────────────────────────────────────────────────────────────
  // GALERİ PİPELINE — YENİDEN YAZILDI
  // Hem silik/küçük termal fişleri iyileştirir,
  // hem normal kaliteli fişlere zarar vermez (adaptif)
  // ─────────────────────────────────────────────────────────────────
  static Uint8List _galleryProcess(String path) {
    final bytes = File(path).readAsBytesSync();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // 1. Boyut normalizasyonu — UZUN fişler için 2400px'e çıkarıldı
    // Sebep: Termal fişlerde satır yüksekliği zaten 30-50px civarı,
    // 2000px'e küçülttüğümüzde satırlar 25-35px'e düşüp ML Kit boğuluyor.
    image = _normalizeSize(image, 2400);

    // 2. Grayscale
    image = img.grayscale(image);

    // 3. Görüntü kalitesi analizi — hangi işlemi uygulayacağımıza karar verir
    // İyi kontrastlı fişlerde minimum, silik fişlerde agresif işlem
    final quality = _analyzeImageQuality(image);

    // 4. Histogram stretching — silik termal yazıyı koyulaştırır
    // Adaptif: zaten kontrastlı görsellerde minimal etki, silik olanlarda büyük etki
    image = _smartHistogramStretch(image, quality);

    // 5. Gamma correction — orta tonları koyulaştırır (yazıyı belirginleştirir)
    // Sadece silik görsellerde uygulanır
    if (quality.isFaded) {
      image = _gammaCorrection(image, gamma: 0.85);
    }

    // 6. Unsharp Mask — yazıyı belirginleştir
    // ÖNEMLİ: Eski sharpen convolution [-1,-1,-1,-1,5,-1,...] yerine kullanıldı.
    // Convolution sharpen küçük yazıları yer; unsharp mask kontrollü.
    final sharpAmount = quality.isFaded ? 1.4 : 0.8;
    image = _unsharpMask(image, amount: sharpAmount, threshold: 5);

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  // ─────────────────────────────────────────────────────────────────
  // BURUŞUK FİŞ PIPELINE - DOKUNULMADI
  // ─────────────────────────────────────────────────────────────────
  static Uint8List _crumpledProcess(String path) {
    final bytes = File(path).readAsBytesSync();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    image = _normalizeSize(image, 2400);
    image = img.grayscale(image);
    image = img.gaussianBlur(image, radius: 1);
    image = _aggressiveContrast(image);
    image = _unsharpMask(image, amount: 1.5, threshold: 10);
    image = _adaptiveThreshold(image, blockSize: 25, c: 12);
    image = _morphologyClean(image);

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  // ─────────────────────────────────────────────────────────────────
  // YENİ: Görüntü kalitesi analizi
  // Histogram dağılımına bakarak görselin "ne kadar silik" olduğunu ölçer
  // ─────────────────────────────────────────────────────────────────
  static _ImageQuality _analyzeImageQuality(img.Image image) {
    final List<int> samples = [];
    final int totalPixels = image.width * image.height;
    final int step = (totalPixels / 3000).round().clamp(1, 150);

    for (int i = 0; i < totalPixels; i += step) {
      final x = i % image.width;
      final y = i ~/ image.width;
      samples.add(img.getLuminance(image.getPixel(x, y)).round());
    }

    samples.sort();
    final int p5 = samples[(samples.length * 0.05).round()];
    final int p50 = samples[(samples.length * 0.50).round()];
    final int p95 = samples[(samples.length * 0.95).round()];
    final int range = p95 - p5;

    // Silik fiş tanımı: dar dinamik aralık + medyan açık tarafa kaymış
    // Normal fiş: p5 ~30 (siyah yazı), p95 ~230 (beyaz kağıt) → range ~200
    // Silik fiş: p5 ~80 (gri yazı), p95 ~210 (gri-beyaz kağıt) → range ~130
    final bool isFaded = range < 150 || p50 > 180;
    final bool isLowContrast = range < 120;

    return _ImageQuality(
      p5: p5,
      p95: p95,
      median: p50,
      range: range,
      isFaded: isFaded,
      isLowContrast: isLowContrast,
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // YENİ: Akıllı histogram germe
  // Görselin kalitesine göre değişen yoğunlukta uygulanır
  // ─────────────────────────────────────────────────────────────────
  static img.Image _smartHistogramStretch(
    img.Image image,
    _ImageQuality quality,
  ) {
    // İyi görsellerde minimal stretch (kenarlardaki uç pikselleri biraz çek)
    // Silik görsellerde agresif stretch (dinamik aralığı 0-255'e zorla)
    final int low;
    final int high;

    if (quality.isLowContrast) {
      // En agresif: %2-98 percentile'ı 0-255'e map et
      low = quality.p5;
      high = quality.p95;
    } else if (quality.isFaded) {
      // Orta: %5-95 percentile
      low = (quality.p5 - 5).clamp(0, 255);
      high = (quality.p95 + 5).clamp(0, 255);
    } else {
      // İyi görseller: çok hafif dokunma
      low = (quality.p5 - 15).clamp(0, 255);
      high = (quality.p95 + 15).clamp(0, 255);
    }

    if (high - low < 10) return image;

    final double scale = 255.0 / (high - low);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final lum = img.getLuminance(pixel).round();
        int stretched = ((lum - low) * scale).round();
        stretched = stretched.clamp(0, 255);
        pixel.setRgb(stretched, stretched, stretched);
      }
    }

    return image;
  }

  // ─────────────────────────────────────────────────────────────────
  // YENİ: Gamma correction (silik termal yazıyı koyulaştırır)
  // gamma < 1 → orta tonları KOYULAŞTIRIR (silik yazı için)
  // gamma > 1 → orta tonları AÇAR (gereksiz)
  // ─────────────────────────────────────────────────────────────────
  static img.Image _gammaCorrection(img.Image image, {double gamma = 0.85}) {
    // Lookup table — performans için (her piksel için pow hesaplamak yerine)
    final List<int> lut = List<int>.generate(256, (i) {
      final double normalized = i / 255.0;
      final double corrected = math.pow(normalized, gamma).toDouble();
      return (corrected * 255).round().clamp(0, 255);
    });

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final lum = img.getLuminance(pixel).round();
        final newVal = lut[lum];
        pixel.setRgb(newVal, newVal, newVal);
      }
    }

    return image;
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
  // AGRESİF kontrast (buruşuk fişler için) - DOKUNULMADI
  // ─────────────────────────────────────────────────────────────────
  static img.Image _aggressiveContrast(img.Image image) {
    final List<int> samples = [];
    final int totalPixels = image.width * image.height;
    final int step = (totalPixels / 2500).round().clamp(1, 100);

    for (int i = 0; i < totalPixels; i += step) {
      final x = i % image.width;
      final y = i ~/ image.width;
      samples.add(img.getLuminance(image.getPixel(x, y)).round());
    }

    samples.sort();
    final int low = samples[(samples.length * 0.02).round()];
    final int high = samples[(samples.length * 0.98).round()];

    if (high - low < 10) return image;

    final double scale = 255.0 / (high - low);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final lum = img.getLuminance(pixel).round();
        int stretched = ((lum - low) * scale).round();
        stretched = stretched.clamp(0, 255);
        pixel.setRgb(stretched, stretched, stretched);
      }
    }

    return image;
  }

  // ─────────────────────────────────────────────────────────────────
  // Unsharp Mask - DOKUNULMADI
  // ─────────────────────────────────────────────────────────────────
  static img.Image _unsharpMask(
    img.Image image, {
    double amount = 1.5,
    int threshold = 0,
  }) {
    final blurred = img.gaussianBlur(image.clone(), radius: 2);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pOrig = image.getPixel(x, y);
        final pBlur = blurred.getPixel(x, y);

        final origLum = img.getLuminance(pOrig).round();
        final blurLum = img.getLuminance(pBlur).round();

        final diff = origLum - blurLum;
        if (diff.abs() < threshold) continue;

        int sharpened = (origLum + (diff * amount)).round();
        sharpened = sharpened.clamp(0, 255);

        pOrig.setRgb(sharpened, sharpened, sharpened);
      }
    }

    return image;
  }

  // ─────────────────────────────────────────────────────────────────
  // Adaptif Eşikleme - DOKUNULMADI (crumpled pipeline için)
  // ─────────────────────────────────────────────────────────────────
  static img.Image _adaptiveThreshold(
    img.Image image, {
    int blockSize = 25,
    int c = 10,
  }) {
    final width = image.width;
    final height = image.height;
    final result = img.Image.from(image);

    final int half = blockSize ~/ 2;

    final List<int> lumCache = List<int>.filled(width * height, 0);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        lumCache[y * width + x] =
            img.getLuminance(image.getPixel(x, y)).round();
      }
    }

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int sum = 0;
        int count = 0;

        final samplePts = [
          [x - half, y - half],
          [x + half, y - half],
          [x - half, y + half],
          [x + half, y + half],
          [x, y],
        ];

        for (final pt in samplePts) {
          final px = pt[0].clamp(0, width - 1);
          final py = pt[1].clamp(0, height - 1);
          sum += lumCache[py * width + px];
          count++;
        }

        final mean = sum / count;
        final pixelLum = lumCache[y * width + x];

        final int newVal = (pixelLum < mean - c) ? 0 : 255;

        result.getPixel(x, y).setRgb(newVal, newVal, newVal);
      }
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────────────
  // Morfolojik Temizleme - DOKUNULMADI
  // ─────────────────────────────────────────────────────────────────
  static img.Image _morphologyClean(img.Image image) {
    final width = image.width;
    final height = image.height;
    final result = img.Image.from(image);

    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        int blackCount = 0;

        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final lum = img.getLuminance(image.getPixel(x + dx, y + dy));
            if (lum < 128) blackCount++;
          }
        }

        final int newVal = blackCount >= 5 ? 0 : 255;
        result.getPixel(x, y).setRgb(newVal, newVal, newVal);
      }
    }

    return result;
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

/// Görüntü kalite analizi sonucu
class _ImageQuality {
  final int p5;
  final int p95;
  final int median;
  final int range;
  final bool isFaded;
  final bool isLowContrast;

  const _ImageQuality({
    required this.p5,
    required this.p95,
    required this.median,
    required this.range,
    required this.isFaded,
    required this.isLowContrast,
  });
}
