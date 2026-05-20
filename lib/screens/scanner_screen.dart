import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/camera_service.dart';
import '../services/ocr_service.dart';
import '../services/image_processor.dart';
import '../utils/receipt_parser.dart';
import '../widgets/result_sheet.dart';
import '../utils/database_helper.dart'; // YENİ: Veritabanı importu
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
    _camera.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    _camera.dispose();
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
      // YENİ: enhanced.path parametresi ile fotoğrafın yolunu iletiyoruz
      if (mounted && ocr != null) _showResult(ocr, enhanced.path);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // YENİ: imagePath parametresi eklendi
  void _showResult(RecognizedText ocr, String imagePath) {
    final data = ReceiptParser.parse(ocr);
    data.imagePath = imagePath; // Fotoğrafı fiş modeline ekle

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        builder: (_, ctrl) => ResultSheet(
          data: data,
          onSave: () async {
            // VERİTABANINA KAYDET
            await DatabaseHelper().insertReceipt(data);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Fiş Başarıyla Kaydedildi!')),
              );
              Navigator.pop(context); // Kameradan Ana Menüye geri dön
            }
          },
          onEdit: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_camera.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Kamera
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

          // Kılavuz çerçeve
          Center(
            child: IgnorePointer(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.88,
                height: MediaQuery.of(context).size.height * 0.58,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.greenAccent.withOpacity(0.6),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Fişi çerçeve içine hizalayın',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Odak karesi
          if (_focusPoint != null)
            Positioned(
              left: _focusPoint!.dx - 30,
              top: _focusPoint!.dy - 30,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 1.5),
                ),
              ),
            ),

          // Flash butonu
          Positioned(
            top: 50,
            right: 20,
            child: IconButton(
              icon: Icon(
                _flashOn ? Icons.flash_on : Icons.flash_off,
                color: Colors.white,
                size: 28,
              ),
              onPressed: () {
                setState(() => _flashOn = !_flashOn);
                _camera.toggleFlash(_flashOn ? FlashMode.torch : FlashMode.off);
              },
            ),
          ),

          // İşlem göstergesi
          if (_processing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.blueAccent),
                    SizedBox(height: 16),
                    Text(
                      'Analiz ediliyor...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

          // Alt kontroller
          if (!_processing)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Galeri
                  _CircleBtn(
                    icon: Icons.photo_library_outlined,
                    onTap: () async {
                      final f = await _picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (f != null) await _processImage(f, fromGallery: true);
                    },
                  ),

                  // Deklanşör
                  GestureDetector(
                    onTap: () async {
                      final f = await _camera.takePicture();
                      if (f != null) await _processImage(f);
                    },
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: Colors.blueAccent.withOpacity(0.85),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),

                  // YENİ: Geçmiş Butonu artık Ana Menüye dönecek
                  _CircleBtn(
                    icon: Icons.history,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white12,
        border: Border.all(color: Colors.white24),
      ),
      child: Icon(icon, color: Colors.white, size: 26),
    ),
  );
}
