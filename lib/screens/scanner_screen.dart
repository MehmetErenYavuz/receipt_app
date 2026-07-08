import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/camera_service.dart';
import '../services/ocr_service.dart';
import '../services/image_processor.dart';
import '../utils/receipt_analyzer.dart';
import '../widgets/result_sheet.dart';
import '../utils/database_helper.dart';
import '../main.dart'; // AppColors
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _camera = CameraService();
  final _ocr = OcrService();
  final _picker = ImagePicker();

  bool _flashOn = false;
  bool _processing = false;
  Offset? _focusPoint;
  Timer? _focusTimer;

  @override
  void initState() {
    super.initState();
    // Kamera ekranında status bar'ı beyaz ikonlu yap
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    _camera.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    _camera.dispose();
    // Status bar'ı eski haline döndür
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    super.dispose();
  }

  void _onTap(TapDownDetails d, BoxConstraints c) {
    if (!_camera.isInitialized) return;
    final offset = Offset(
      d.localPosition.dx / c.maxWidth,
      d.localPosition.dy / c.maxHeight,
    );
    _camera.setFocusPoint(offset);
    setState(() => _focusPoint = d.localPosition);
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _focusPoint = null);
    });
  }

  Future<void> _processImage(XFile file, {bool fromGallery = false}) async {
    setState(() => _processing = true);
    try {
      final enhanced = fromGallery
          ? await ImageProcessor.enhanceForGallery(file)
          : await ImageProcessor.enhanceForCamera(file);
      final ocr = await _ocr.processImage(enhanced);
      if (mounted && ocr != null) _showResult(ocr, enhanced.path);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showResult(RecognizedText ocr, String imagePath) async {
    // NER birincil + regex fallback (model yoksa saf regex'e düşer).
    final data = await ReceiptAnalyzer.analyze(ocr);
    data.imagePath = imagePath;
    data.isApproved = false; // Onay bekleyenlere düşsün

    // Tamamen lokal cihazda SQLite'a kayıt yapılıyor
    await DatabaseHelper().insertReceipt(data);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.access_time_rounded, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Fiş okundu. Geçmiş sekmesinden onaylayın.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.primary,
          elevation: 8,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
      Navigator.pop(context); // Kamerayı kapatıp ana ekrana dön
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_camera.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Kamera Önizleme ──
          LayoutBuilder(
            builder: (ctx, c) => GestureDetector(
              onTapDown: (d) => _onTap(d, c),
              child: SizedBox(
                width: c.maxWidth,
                height: c.maxHeight,
                child: CameraPreview(_camera.controller!),
              ),
            ),
          ),

          // ── Kılavuz Çerçeve (Premium tasarım) ──
          Center(
            child: IgnorePointer(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.86,
                height: MediaQuery.of(context).size.height * 0.6,
                child: Stack(
                  children: [
                    // 4 köşe işaretleyici (L şeklinde köşeler)
                    _cornerMarker(top: 0, left: 0, rotation: 0),
                    _cornerMarker(top: 0, right: 0, rotation: 1),
                    _cornerMarker(bottom: 0, left: 0, rotation: 3),
                    _cornerMarker(bottom: 0, right: 0, rotation: 2),
                    // Üst tarafta ipucu
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Fişi çerçeve içine hizalayın',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Odak Karesi ──
          if (_focusPoint != null)
            Positioned(
              left: _focusPoint!.dx - 30,
              top: _focusPoint!.dy - 30,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1.4, end: 1.0),
                duration: const Duration(milliseconds: 300),
                builder: (_, scale, __) => Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 1.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),

          // ── Üst Bar: Kapat + Flash ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CircleIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  _CircleIconButton(
                    icon: _flashOn
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    isActive: _flashOn,
                    onTap: () {
                      setState(() => _flashOn = !_flashOn);
                      _camera.toggleFlash(
                        _flashOn ? FlashMode.torch : FlashMode.off,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── İşlem Göstergesi ──
          if (_processing)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 28,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          color: Colors.amber,
                          strokeWidth: 3,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Analiz ediliyor',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Bu işlem birkaç saniye sürebilir',
                        style: TextStyle(color: Colors.cyan, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Alt Kontroller ──
          if (!_processing)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  24,
                  16,
                  24,
                  MediaQuery.of(context).viewPadding.bottom + 20,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Galeri
                    _CircleIconButton(
                      icon: Icons.photo_library_outlined,
                      size: 56,
                      onTap: () async {
                        final f = await _picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (f != null)
                          await _processImage(f, fromGallery: true);
                      },
                    ),

                    // Deklanşör (premium tasarım)
                    GestureDetector(
                      onTap: () async {
                        final f = await _camera.takePicture();
                        if (f != null) await _processImage(f);
                      },
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    // Geri
                    _CircleIconButton(
                      icon: Icons.history_rounded,
                      size: 56,
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── L şeklinde köşe işaretleyicisi ──
  Widget _cornerMarker({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required int rotation,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Transform.rotate(
        angle: rotation * 1.5708, // 90 derece * rotation
        child: Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white, width: 3),
              left: BorderSide(color: Colors.white, width: 3),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PREMIUM YUVARLAK BUTON
// ═══════════════════════════════════════════════════════════════════════
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool isActive;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? Colors.white : Colors.black.withOpacity(0.45),
          border: Border.all(
            color: Colors.white.withOpacity(isActive ? 1 : 0.25),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.black : Colors.white,
          size: size * 0.45,
        ),
      ),
    );
  }
}
