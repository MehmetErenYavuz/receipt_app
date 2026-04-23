import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraService {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  CameraController? _controller;
  List<CameraDescription>? _cameras;

  bool get isInitialized =>
      _controller != null && _controller!.value.isInitialized;
  CameraController? get controller => _controller;

  Future<void> initialize() async {
    _cameras = await availableCameras();
    if (_cameras!.isEmpty) throw Exception("Cihazda kamera bulunamadı.");

    // OPTİMİZASYON 1: OCR için en iyi çözünürlük 1080p'dir (veryHigh).
    // max çözünürlük (48MP+) yapay zekayı boğar ve yanlış okutur.
    _controller = CameraController(
      _cameras![0],
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
    await _controller!.setFlashMode(FlashMode.off);

    // OPTİMİZASYON 2: Lensi Sürekli Otomatik Odaklanma moduna alıyoruz (Sıfır Gecikme)
    await _controller!.setFocusMode(FocusMode.auto);
    // Zoom optimizasyonu (Hafif yakınlaştırma yazıları büyütür)
    try {
      double maxZoom = await _controller!.getMaxZoomLevel();
      double targetZoom = 1.5; // 2.0 bazen çok bozabilir, 1.5 idealdir
      if (targetZoom > maxZoom) targetZoom = maxZoom;
      await _controller!.setZoomLevel(targetZoom);
    } catch (e) {
      debugPrint("Zoom ayarlanamadı: $e");
    }
  }

  Future<void> toggleFlash(FlashMode mode) async {
    if (isInitialized) await _controller!.setFlashMode(mode);
  }

  Future<void> setFocusPoint(Offset point) async {
    if (isInitialized) {
      try {
        await _controller!.setFocusPoint(point);
        // Dokunduktan sonra tekrar sürekli odağa dönmesini sağla
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (e) {
        debugPrint("Odaklanma hatası: $e");
      }
    }
  }

  // OPTİMİZASYON 3: Gecikme (Future.delayed) kaldırıldı. Deklanşöre basıldığı an çeker.
  Future<XFile?> takePicture() async {
    if (!isInitialized) return null;
    if (_controller!.value.isTakingPicture) return null;

    try {
      return await _controller!.takePicture();
    } catch (e) {
      debugPrint("Fotoğraf çekilemedi: $e");
      return null;
    }
  }

  void dispose() {
    _controller?.dispose();
  }
}
