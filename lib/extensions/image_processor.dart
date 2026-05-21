import 'dart:io';
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
  // YENİ: BURUŞUK FİŞ PIPELINE
  // Buruşuk/eğri/soluk fişler için en agresif iyileştirme
  // ─────────────────────────────────────────────────────────────────
  static Future<XFile> enhanceForCrumpled(XFile originalFile) async {
    final processedBytes = await compute(_crumpledProcess, originalFile.path);
    return _save(originalFile.path, processedBytes, 'crumpled');
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
  // YENİ: BURUŞUK FİŞ PIPELINE (en agresif)
  // ─────────────────────────────────────────────────────────────────
  static Uint8List _crumpledProcess(String path) {
    final bytes = File(path).readAsBytesSync();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // 1. Daha yüksek çözünürlük — buruşuklarda detay kritik
    image = _normalizeSize(image, 2400);

    // 2. Grayscale
    image = img.grayscale(image);

    // 3. Gauss bulanıklığı ile gürültü azalt (kırışıklıklar gürültü gibi davranır)
    // Önce yumuşat sonra sertleştir → kırışıklık izlerini siler ama yazıyı korur
    image = img.gaussianBlur(image, radius: 1);

    // 4. AGRESIF adaptif kontrast (soluk metni yakala)
    image = _aggressiveContrast(image);

    // 5. Unsharp mask — yazıyı belirginleştir ama gürültüyü artırma
    image = _unsharpMask(image, amount: 1.5, threshold: 10);

    // 6. ADAPTIF EŞIKLEME — yerel parlaklığa duyarlı binarizasyon
    // Buruşukların gölge alanlarındaki metni kurtarır
    image = _adaptiveThreshold(image, blockSize: 25, c: 12);

    // 7. Morfolojik temizleme — küçük gürültü noktalarını sil
    image = _morphologyClean(image);

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
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
  // YARDIMCI: Adaptif kontrast (mevcut)
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
      contrastFactor = 1.9;
    } else if (range < 60) {
      contrastFactor = 1.5;
    } else if (range < 100) {
      contrastFactor = 1.25;
    } else {
      contrastFactor = 1.05;
    }

    return img.adjustColor(image, contrast: contrastFactor);
  }

  // ─────────────────────────────────────────────────────────────────
  // YENİ: AGRESİF kontrast (buruşuk fişler için)
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

    // Histogram germe (stretch) — siyahı %2'ye, beyazı %98'e bağla
    if (high - low < 10) return image;

    final double scale = 255.0 / (high - low);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final lum = img.getLuminance(pixel).round();
        int stretched = ((lum - low) * scale).round();
        stretched = stretched.clamp(0, 255);
        // RGB üç kanalı da aynı değere set et (grayscale)
        pixel.setRgb(stretched, stretched, stretched);
      }
    }

    return image;
  }

  // ─────────────────────────────────────────────────────────────────
  // YENİ: Unsharp Mask — yazıyı belirginleştir
  // ─────────────────────────────────────────────────────────────────
  static img.Image _unsharpMask(
    img.Image image, {
    double amount = 1.5,
    int threshold = 0,
  }) {
    // Bulanık kopya oluştur
    final blurred = img.gaussianBlur(image.clone(), radius: 2);

    // Original - blurred = high-pass detail
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pOrig = image.getPixel(x, y);
        final pBlur = blurred.getPixel(x, y);

        final origLum = img.getLuminance(pOrig).round();
        final blurLum = img.getLuminance(pBlur).round();

        final diff = origLum - blurLum;
        if (diff.abs() < threshold) continue; // Düşük detay, gürültü kabul et

        int sharpened = (origLum + (diff * amount)).round();
        sharpened = sharpened.clamp(0, 255);

        pOrig.setRgb(sharpened, sharpened, sharpened);
      }
    }

    return image;
  }

  // ─────────────────────────────────────────────────────────────────
  // YENİ: Adaptif Eşikleme (Adaptive Threshold)
  // Her piksel için lokal ortalamadan c kadar küçükse → SİYAH (yazı)
  // Bu sayede gölgeler ve ışık dağılımı sorunları çözülür
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

    // Performans için: tüm piksellerin lümen değerini önceden cache
    final List<int> lumCache = List<int>.filled(width * height, 0);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        lumCache[y * width + x] =
            img.getLuminance(image.getPixel(x, y)).round();
      }
    }

    // Stride: her pikseli işlemek çok yavaş, her 1 pikselde bir
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Lokal blok ortalaması (örneklenmiş — hız için)
        int sum = 0;
        int count = 0;

        // Bloğun 4 köşesi + merkezi (yaklaşık ortalama, hızlı)
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

        // Lokal ortalamadan c kadar düşükse → yazı (siyah), aksi → arkaplan (beyaz)
        final int newVal = (pixelLum < mean - c) ? 0 : 255;

        result.getPixel(x, y).setRgb(newVal, newVal, newVal);
      }
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────────────
  // YENİ: Morfolojik Temizleme
  // 1-2 piksellik gürültü noktalarını siler, yazıyı korur
  // ─────────────────────────────────────────────────────────────────
  static img.Image _morphologyClean(img.Image image) {
    final width = image.width;
    final height = image.height;
    final result = img.Image.from(image);

    // Yazıyı koruyup gürültüyü kaldırmak için: median benzeri
    // Her piksel için 3x3 komşunun çoğunluğuna bak
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        int blackCount = 0;

        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final lum = img.getLuminance(image.getPixel(x + dx, y + dy));
            if (lum < 128) blackCount++;
          }
        }

        // 9 pikselden en az 5'i siyahsa → siyah; aksi → beyaz
        // Bu tek piksellik gürültü noktalarını siler
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
