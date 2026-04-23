import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // Galeri için eklendi
import '../services/camera_service.dart';
import '../services/ocr_service.dart';
import '../models/receipt_data.dart';
import '../utils/receipt_parser.dart';
import '../services/image_processor.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final CameraService _cameraService = CameraService();
  final OcrService _ocrService = OcrService();
  final ImagePicker _imagePicker = ImagePicker(); // Galeri motoru

  bool _isFlashOn = false;
  bool _isProcessing = false;

  // Görsel Odaklanma için değişkenler
  Offset? _focusPoint;
  Timer? _focusTimer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    await _cameraService.initialize();
    if (mounted) setState(() {});
  }

  void _onTapToFocus(TapDownDetails details, BoxConstraints constraints) {
    if (!_cameraService.isInitialized) return;

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );

    _cameraService.setFocusPoint(offset);

    setState(() {
      _focusPoint = details.localPosition;
    });

    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted)
        setState(() {
          _focusPoint = null;
        });
    });
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraService.isInitialized) {
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
          // 1. Kamera Görüntüsü
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapDown: (details) => _onTapToFocus(details, constraints),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: CameraPreview(_cameraService.controller!),
                ),
              );
            },
          ),

          // 2. Kılavuz Çerçeve (Yeşil Kutu)
          Center(
            child: IgnorePointer(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                height: MediaQuery.of(context).size.height * 0.6,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.greenAccent.withOpacity(0.5),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),

          // 3. Odaklanma Karesi
          if (_focusPoint != null)
            Positioned(
              left: _focusPoint!.dx - 30,
              top: _focusPoint!.dy - 30,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),

          // 4. Flaş Butonu
          Positioned(
            top: 50,
            right: 20,
            child: IconButton(
              icon: Icon(
                _isFlashOn ? Icons.flash_on : Icons.flash_off,
                color: Colors.white,
                size: 30,
              ),
              onPressed: () {
                setState(() {
                  _isFlashOn = !_isFlashOn;
                });
                _cameraService.toggleFlash(
                  _isFlashOn ? FlashMode.torch : FlashMode.off,
                );
              },
            ),
          ),

          // 5. Alt Kontrol Paneli (Galeri ve Kamera)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // GALERİ BUTONU (Filtreli ve Güçlendirilmiş İşlem)
                IconButton(
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          final XFile? galleryImage = await _imagePicker
                              .pickImage(source: ImageSource.gallery);
                          if (galleryImage != null) {
                            setState(() {
                              _isProcessing = true;
                            });
                            try {
                              // Galeriden gelen resmi yapay zekaya vermeden önce "yıka"
                              final enhancedImage =
                                  await ImageProcessor.enhanceForGallery(
                                    galleryImage,
                                  );
                              final okunanMetin = await _ocrService
                                  .processImage(enhancedImage);

                              if (mounted && okunanMetin != null) {
                                _showResultDialog(okunanMetin);
                              }
                            } finally {
                              if (mounted)
                                setState(() {
                                  _isProcessing = false;
                                });
                            }
                          }
                        },
                  icon: const Icon(
                    Icons.photo_library,
                    color: Colors.white,
                    size: 32,
                  ),
                ),

                // KAMERA (DEKLANŞÖR) BUTONU (Hızlı ve Saf İşlem)
                GestureDetector(
                  onTap: _isProcessing
                      ? null
                      : () async {
                          setState(() {
                            _isProcessing = true;
                          });
                          try {
                            // Kameradan gelen resmi doğrudan ML Kit'e ver
                            final cameraImage = await _cameraService
                                .takePicture();
                            if (cameraImage != null) {
                              final okunanMetin = await _ocrService
                                  .processImage(cameraImage);

                              if (mounted && okunanMetin != null) {
                                _showResultDialog(okunanMetin);
                              }
                            }
                          } finally {
                            if (mounted)
                              setState(() {
                                _isProcessing = false;
                              });
                          }
                        },
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: _isProcessing
                          ? Colors.grey
                          : Colors.blueAccent.withOpacity(0.8),
                    ),
                    child: _isProcessing
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 40,
                          ),
                  ),
                ),

                const SizedBox(width: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showResultDialog(RecognizedText recognizedTextObj) {
    ReceiptData parsedData = ReceiptParser.parse(recognizedTextObj);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A), // MeyStudios Koyu Tema
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.analytics_outlined, color: Colors.blueAccent),
            const SizedBox(width: 10),
            const Text("Analiz Sonucu", style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              _buildDataRow(Icons.business, "İşletme", parsedData.firmaAdi),
              _buildDataRow(Icons.numbers, "Vergi/TC No", parsedData.vergiTcNo),
              const Divider(color: Colors.white24),
              _buildDataRow(
                Icons.calendar_month,
                "İşlem Tarihi",
                parsedData.tarih,
              ),
              _buildDataRow(Icons.access_time, "İşlem Saati", parsedData.saat),
              const Divider(color: Colors.white24),
              // KDV bilgisini daha net veriyoruz
              _buildDataRow(
                Icons.receipt_long,
                "Toplam KDV Tutarı",
                parsedData.toplamKdv.isEmpty
                    ? "Tespit Edilemedi"
                    : "${parsedData.toplamKdv} TL",
              ),
              // GENEL TOPLAM vurgusu
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _buildDataRow(
                  Icons.payments,
                  "GENEL TOPLAM",
                  parsedData.toplamTutar.isEmpty
                      ? "---"
                      : "${parsedData.toplamTutar} TL",
                  isHighlight: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "DÜZENLE",
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              Navigator.pop(context);
              // TODO: SQLite Kayıt İşlemi
            },
            child: const Text("ONAYLA VE KAYDET"),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(
    IconData icon,
    String title,
    String value, {
    bool isHighlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 24),
          const SizedBox(width: 12),
          Text(
            "$title: ",
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? "-" : value,
              style: TextStyle(
                color: isHighlight ? Colors.greenAccent : Colors.white,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
                fontSize: 16,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
