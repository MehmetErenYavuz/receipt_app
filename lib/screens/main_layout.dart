import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/database_helper.dart';
import 'scanner_screen.dart';
import '../services/image_processor.dart';
import '../services/ocr_service.dart';
import '../utils/receipt_parser.dart';
import '../models/receipt_data.dart';
import '../main.dart'; // AppColors için

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
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _HistoryTab(db: _db),
          _ScannerTab(db: _db),
          _ExportTab(db: _db),
          const _ProfileTab(),
        ],
      ),
      bottomNavigationBar: _buildPremiumBottomBar(),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // PREMIUM BOTTOM BAR
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildPremiumBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(
                0,
                Icons.receipt_long_rounded,
                Icons.receipt_long,
                'Geçmiş',
              ),
              _navItem(
                1,
                Icons.add_a_photo_outlined,
                Icons.add_a_photo,
                'Tara',
              ),
              _navItem(2, Icons.bar_chart_outlined, Icons.bar_chart, 'Özet'),
              _navItem(
                3,
                Icons.person_outline_rounded,
                Icons.person_rounded,
                'Profil',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(
    int index,
    IconData iconOutline,
    IconData iconFilled,
    String label,
  ) {
    final bool selected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? iconFilled : iconOutline,
              color: selected ? AppColors.primary : AppColors.textTertiary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SEKME 1: GEÇMİŞ — Premium Liste Tasarımı
// ═══════════════════════════════════════════════════════════════════════
class _HistoryTab extends StatefulWidget {
  final DatabaseHelper db;
  const _HistoryTab({required this.db});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  String _filter = 'Tümü';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Text(
                    'Fişlerim',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => setState(() {}),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),

            // ── Kategori Filtre Pills ──
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _filterChip('Tümü'),
                  _filterChip('Market'),
                  _filterChip('Yakıt'),
                  _filterChip('Yeme-İçme'),
                  _filterChip('Sağlık'),
                  _filterChip('Faturalar'),
                  _filterChip('Diğer'),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Liste ──
            Expanded(
              child: FutureBuilder<List<ReceiptData>>(
                future: widget.db.getAllReceipts(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2.5,
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _emptyState();
                  }

                  var receipts = snapshot.data!;
                  if (_filter != 'Tümü') {
                    receipts = receipts
                        .where((r) => r.kategori == _filter)
                        .toList();
                  }

                  if (receipts.isEmpty) {
                    return _emptyState(
                      message: '$_filter kategorisinde fiş yok',
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: receipts.length,
                    itemBuilder: (context, index) =>
                        _ReceiptCard(receipt: receipts[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label) {
    final bool selected = _filter == label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => setState(() => _filter = label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState({String message = 'Henüz fiş eklenmedi'}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 36,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tara sekmesinden ilk fişinizi ekleyin',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FİŞ KARTI — Premium Tasarım
// ═══════════════════════════════════════════════════════════════════════
class _ReceiptCard extends StatelessWidget {
  final ReceiptData receipt;
  const _ReceiptCard({required this.receipt});

  Color get _kategoriRengi =>
      AppColors.kategoriRenkler[receipt.kategori] ?? AppColors.textTertiary;

  IconData get _kategoriIkonu {
    switch (receipt.kategori) {
      case 'Market':
        return Icons.shopping_basket_rounded;
      case 'Yakıt':
        return Icons.local_gas_station_rounded;
      case 'Yeme-İçme':
        return Icons.restaurant_rounded;
      case 'Sağlık':
        return Icons.local_hospital_rounded;
      case 'Giyim':
        return Icons.checkroom_rounded;
      case 'Elektronik':
        return Icons.devices_rounded;
      case 'Ulaşım':
        return Icons.directions_car_rounded;
      case 'Faturalar':
        return Icons.receipt_rounded;
      default:
        return Icons.shopping_bag_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // İleride detay sayfası eklenebilir
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Görsel veya kategori ikonu
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child:
                      receipt.imagePath != null &&
                          File(receipt.imagePath!).existsSync()
                      ? Image.file(
                          File(receipt.imagePath!),
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: _kategoriRengi.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _kategoriIkonu,
                            color: _kategoriRengi,
                            size: 26,
                          ),
                        ),
                ),
                const SizedBox(width: 12),

                // Firma + Tarih
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        receipt.firmaAdi.isEmpty
                            ? 'Bilinmeyen Firma'
                            : receipt.firmaAdi,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // Kategori etiketi
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _kategoriRengi.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              receipt.kategori,
                              style: TextStyle(
                                color: _kategoriRengi,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              receipt.tarih.isEmpty ? '—' : receipt.tarih,
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Tutar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      receipt.toplamTutar.isEmpty
                          ? '—'
                          : '${receipt.toplamTutar} ₺',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (receipt.uyari != null && receipt.uyari!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: AppColors.warning,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SEKME 2: FİŞ OKUTMA — Premium Beyaz
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
  int _pendingTasks = 0;

  Future<void> _processGalleryImage(XFile imageFile) async {
    setState(() {
      _isAnalyzing = true;
      _pendingTasks++;
    });

    try {
      final enhancedImage = await ImageProcessor.enhanceForGallery(imageFile);
      final recognizedText = await _ocr.processImage(enhancedImage);

      if (recognizedText != null) {
        final parsedData = ReceiptParser.parse(recognizedText);
        parsedData.imagePath = enhancedImage.path;
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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Fiş başarıyla kaydedildi',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.divider),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // ── Başlık ──
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Fiş Tara',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Fişinizi taratın veya galeriden yükleyin',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Arka Plan İşlem Banner ──
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: _isAnalyzing ? 64 : 0,
                margin: EdgeInsets.only(bottom: _isAnalyzing ? 20 : 0),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.accent.withOpacity(0.2)),
                ),
                child: _isAnalyzing
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: AppColors.accent,
                                strokeWidth: 2,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Arka planda $_pendingTasks fiş işleniyor',
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // ── Kamera ile Tara — Ana Aksiyon ──
              _PrimaryActionCard(
                title: 'Kamera ile Tara',
                subtitle: 'Anında çek ve analiz et',
                icon: Icons.camera_alt_rounded,
                isPrimary: true,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScannerScreen()),
                ),
              ),

              const SizedBox(height: 14),

              // ── Galeriden Yükle ──
              _PrimaryActionCard(
                title: 'Galeriden Yükle',
                subtitle: 'Mevcut bir fotoğrafı seç',
                icon: Icons.photo_library_rounded,
                isPrimary: false,
                onTap: () async {
                  final image = await _picker.pickImage(
                    source: ImageSource.gallery,
                  );
                  if (image != null) _processGalleryImage(image);
                },
              ),

              const Spacer(),

              // ── Bilgi kartı ──
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.tips_and_updates_rounded,
                        size: 18,
                        color: AppColors.info,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'En iyi sonuç için fişi düz bir zemine yerleştirin ve iyi ışıklandırın.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ANA AKSİYON KARTI — Premium Tasarım
// ═══════════════════════════════════════════════════════════════════════
class _PrimaryActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _PrimaryActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isPrimary ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isPrimary ? AppColors.primary : AppColors.divider,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? Colors.white.withOpacity(0.15)
                      : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: isPrimary ? Colors.white : AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isPrimary ? Colors.white : AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isPrimary
                            ? Colors.white.withOpacity(0.7)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: isPrimary ? Colors.white : AppColors.textTertiary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SEKME 3: ÖZET (Eski Excel)
// ═══════════════════════════════════════════════════════════════════════
class _ExportTab extends StatelessWidget {
  final DatabaseHelper db;
  const _ExportTab({required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Text(
                'Özet',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 24),

              // Kategori bazlı toplamlar
              Expanded(
                child: FutureBuilder<Map<String, double>>(
                  future: db.getKategoriToplamlari(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      );
                    }
                    final toplamlar = snapshot.data!;
                    if (toplamlar.isEmpty) {
                      return const Center(
                        child: Text(
                          'Veri yok',
                          style: TextStyle(color: AppColors.textTertiary),
                        ),
                      );
                    }
                    final genelToplam = toplamlar.values.fold(
                      0.0,
                      (a, b) => a + b,
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Toplam Harcama',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${genelToplam.toStringAsFixed(2)} ₺',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Kategori Bazlı',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView(
                            children: toplamlar.entries.map((e) {
                              final renk =
                                  AppColors.kategoriRenkler[e.key] ??
                                  AppColors.textTertiary;
                              final yuzde = genelToplam > 0
                                  ? (e.value / genelToplam * 100)
                                  : 0;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.divider),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: renk,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        e.key,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${e.value.toStringAsFixed(2)} ₺',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          '%${yuzde.toStringAsFixed(1)}',
                                          style: const TextStyle(
                                            color: AppColors.textTertiary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SEKME 4: PROFİL — Premium Beyaz
// ═══════════════════════════════════════════════════════════════════════
class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 32),

              // ── Avatar ──
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceAlt,
                  border: Border.all(color: AppColors.divider, width: 1),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 48,
                  color: AppColors.textTertiary,
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Mehmet Eren',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 6),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 14,
                      color: AppColors.warning,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'VIP Üye',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Profil seçenekleri ──
              _ProfileItem(
                icon: Icons.workspace_premium_rounded,
                title: 'Abonelik Yönetimi',
                subtitle: 'Yenileme: 20.06.2026',
              ),
              _ProfileItem(
                icon: Icons.cloud_sync_rounded,
                title: 'Bulut Yedekleme',
                subtitle: 'Son yedek: Bugün 14:32',
              ),
              _ProfileItem(
                icon: Icons.notifications_outlined,
                title: 'Bildirimler',
              ),
              _ProfileItem(
                icon: Icons.help_outline_rounded,
                title: 'Yardım & Destek',
              ),
              _ProfileItem(
                icon: Icons.info_outline_rounded,
                title: 'Hakkında',
                subtitle: 'v1.0.0',
              ),

              const Spacer(),

              _ProfileItem(
                icon: Icons.logout_rounded,
                title: 'Çıkış Yap',
                isDanger: true,
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isDanger;

  const _ProfileItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (isDanger ? AppColors.danger : AppColors.textPrimary)
                        .withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: isDanger ? AppColors.danger : AppColors.textPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isDanger
                              ? AppColors.danger
                              : AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isDanger)
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppColors.textTertiary,
                    size: 14,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
