import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/database_helper.dart';
import 'scanner_screen.dart';
import '../services/image_processor.dart';
import '../services/ocr_service.dart';
import '../utils/receipt_parser.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 1;
  final DatabaseHelper _db = DatabaseHelper();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _HistoryTab(db: _db),
          _ScannerTab(
            db: _db,
          ), // ── YENİ: Artık veritabanını tarama sekmesine de gönderiyoruz
          const _ExportTab(),
          const _ProfileTab(),
        ],
      ),
      bottomNavigationBar: _buildPremiumBottomBar(),
    );
  }

  Widget _buildPremiumBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: BottomNavigationBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: Colors.cyanAccent,
        unselectedItemColor: Colors.white24,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_rounded),
            label: 'Geçmiş',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_a_photo_rounded),
            label: 'Okut',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.ios_share_rounded),
            label: 'Excel',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_2_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SEKME 1: GEÇMİŞ
// ═══════════════════════════════════════════════════════════════════════
class _HistoryTab extends StatefulWidget {
  final DatabaseHelper db;
  const _HistoryTab({required this.db});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Onaylanan Fişler',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder(
        future: widget.db.getAllReceipts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'Henüz kaydedilmiş fiş yok.',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }
          final receipts = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: receipts.length,
            itemBuilder: (context, index) {
              final r = receipts[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2128),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child:
                        r.imagePath != null && File(r.imagePath!).existsSync()
                        ? Image.file(
                            File(r.imagePath!),
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 50,
                            height: 50,
                            color: Colors.white10,
                            child: const Icon(
                              Icons.receipt,
                              color: Colors.white54,
                            ),
                          ),
                  ),
                  title: Text(
                    r.firmaAdi.isEmpty ? 'Bilinmeyen Firma' : r.firmaAdi,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    '${r.tarih} • ${r.toplamTutar} TL',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.edit_note_rounded,
                      color: Colors.cyanAccent,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Düzenleme ekranı yakında eklenecek'),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SEKME 2: FİŞ OKUTMA (YENİ: ARKA PLAN ANALİZ SİSTEMİ)
// ═══════════════════════════════════════════════════════════════════════
class _ScannerTab extends StatefulWidget {
  final DatabaseHelper db;
  const _ScannerTab({required this.db});

  @override
  State<_ScannerTab> createState() => _ScannerTabState();
}

class _ScannerTabState extends State<_ScannerTab> {
  final ImagePicker _picker = ImagePicker();
  final OcrService _ocr = OcrService();

  bool _isAnalyzing = false;
  int _pendingTasks = 0; // Aynı anda kaç fişin işlendiğini tutar

  // ── Arka Plan Görüntü İşleme ve Kayıt Fonksiyonu ──
  Future<void> _processGalleryImage(XFile imageFile) async {
    setState(() {
      _isAnalyzing = true;
      _pendingTasks++;
    });

    try {
      // 1. Görüntüyü Galeri modunda iyileştir (Siyah beyaz, kontrast)
      final enhancedImage = await ImageProcessor.enhanceForGallery(imageFile);

      // 2. OCR Motorundan geçir
      final recognizedText = await _ocr.processImage(enhancedImage);

      if (recognizedText != null) {
        // 3. Fişi Parse Et
        final parsedData = ReceiptParser.parse(recognizedText);
        parsedData.imagePath =
            enhancedImage.path; // İşlenmiş görüntünün yolunu kaydet

        // 4. Sessizce SQLite Çelik Kasasına (Veritabanına) Kaydet
        await widget.db.insertReceipt(parsedData);
      }
    } catch (e) {
      debugPrint("Arka plan analiz hatası: $e");
    } finally {
      if (mounted) {
        setState(() {
          _pendingTasks--;
          if (_pendingTasks == 0) _isAnalyzing = false;
        });

        // İşlem bitince kullanıcıya zarif bir bildirim ver
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Fiş arka planda analiz edildi ve Geçmişe kaydedildi!',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── ARKA PLAN İŞLEM DURUM KUTUCUĞU ──
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _isAnalyzing ? 70 : 0,
            margin: const EdgeInsets.only(bottom: 20, left: 30, right: 30),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
            ),
            child: _isAnalyzing
                ? Row(
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.cyanAccent,
                          strokeWidth: 2.5,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Arka planda $_pendingTasks fiş analiz ediliyor...\nSiz işlem yapmaya devam edebilirsiniz.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          _ActionCard(
            title: 'Kamera İle Tara',
            icon: Icons.camera_alt,
            color: Colors.cyanAccent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScannerScreen()),
            ),
          ),
          const SizedBox(height: 20),
          _ActionCard(
            title: 'Galeriden Seç',
            icon: Icons.photo_library,
            color: Colors.orangeAccent,
            onTap: () async {
              // Kullanıcı fotoğrafı seçer seçmez işlem arka planda başlar, menü kilitlenmez
              final image = await _picker.pickImage(
                source: ImageSource.gallery,
              );
              if (image != null) {
                _processGalleryImage(
                  image,
                ); // Await koymadık, asenkron (arka planda) devam eder
              }
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SEKME 3: EXCEL ÇIKTISI
// ═══════════════════════════════════════════════════════════════════════
class _ExportTab extends StatelessWidget {
  const _ExportTab();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        "Excel Çıktısı Yakında...",
        style: TextStyle(color: Colors.white54),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SEKME 4: PROFİL
// ═══════════════════════════════════════════════════════════════════════
class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 30),
          const CircleAvatar(
            radius: 50,
            backgroundColor: Colors.cyanAccent,
            child: Icon(Icons.person, size: 50, color: Colors.black),
          ),
          const SizedBox(height: 16),
          const Text(
            'Mehmet Eren',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Text(
            'Mey Studios VIP Üyesi',
            style: TextStyle(color: Colors.cyanAccent, fontSize: 12),
          ),
          const SizedBox(height: 30),
          _buildProfileItem(
            Icons.workspace_premium,
            'Abonelik Yönetimi',
            'Yenileme: 20.06.2026',
          ),
          _buildProfileItem(Icons.help_outline, 'Yardım & Destek', null),
          const Spacer(),
          _buildProfileItem(Icons.logout, 'Çıkış Yap', null, isDanger: true),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildProfileItem(
    IconData icon,
    String title,
    String? sub, {
    bool isDanger = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: isDanger ? Colors.redAccent : Colors.white70),
      title: Text(
        title,
        style: TextStyle(color: isDanger ? Colors.redAccent : Colors.white),
      ),
      subtitle: sub != null
          ? Text(
              sub,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            )
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.white12),
    );
  }
}

// Ortak Buton Tasarımı
class _ActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 250,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF1C2128),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 20)],
        ),
        child: Column(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
