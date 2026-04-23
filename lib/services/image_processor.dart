import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImageProcessor {
  static Future<XFile> enhanceForGallery(XFile originalFile) async {
    // İşlemi arka planda yap ki uygulama donmasın
    final processedBytes = await compute(_processLogic, originalFile.path);

    final String newPath = "${originalFile.path}_enhanced.jpg";
    final File newFile = File(newPath);
    await newFile.writeAsBytes(processedBytes);

    return XFile(newPath);
  }

  static Uint8List _processLogic(String imagePath) {
    final bytes = File(imagePath).readAsBytesSync();
    img.Image? image = img.decodeImage(bytes);

    if (image == null) return bytes;

    // 1. Siyah Beyaz (Grayscale) - Renk karmaşasını önler
    image = img.grayscale(image);

    // 2. Kontrast Artırma - Soluk fiş yazılarını keskinleştirir (1.5 = %150)
    image = img.adjustColor(image, contrast: 1.5);

    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }
}
