import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/database_helper.dart';
import 'scanner_screen.dart';
import '../services/image_processor.dart';
import '../services/ocr_service.dart';
import '../utils/receipt_parser.dart';
import '../models/receipt_data.dart';
import '../widgets/result_sheet.dart'; // Fiş detay analizi için eklendi
import '../main.dart'; // AppColors için
import '../services/excel_export_service.dart';

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
// SEKME 1: GEÇMİŞ — Premium Liste Tasarımı (Onay Sekmeleri Entegre Edildi)
// ═══════════════════════════════════════════════════════════════════════
class _HistoryTab extends StatefulWidget {
  final DatabaseHelper db;
  const _HistoryTab({required this.db});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab>
    with SingleTickerProviderStateMixin {
  String _filter = 'Tümü';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Fiş doğrulama ve detay ekranını açan fonksiyon ──
  // isDetailMode: true ise (onaylananlardan tıklanmışsa), detay/düzenleme modu açılır
  // isDetailMode: false ise (onay bekleyenlerden tıklanmışsa), onaylama akışı çalışır
  void _openReceiptDetail(ReceiptData receipt, {required bool isDetailMode}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        builder: (_, ctrl) => ResultSheet(
          data: receipt,
          isDetailMode: isDetailMode,
          onSave: () async {
            // Onay bekleyenden geliyorsa onayla
            if (!isDetailMode) {
              try {
                receipt.isApproved = true;
              } catch (_) {}
            }

            // Yerel veritabanına güncel halini kaydet
            await widget.db.insertReceipt(receipt);

            if (mounted) {
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isDetailMode
                            ? 'Değişiklikler kaydedildi'
                            : 'Fiş onaylandı ve kaydedildi',
                        style: const TextStyle(fontWeight: FontWeight.w500),
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
          },
          onEdit: () {},
          // ── YENİ: Detay modunda silme callback'i ──
          onDelete: () async {
            if (receipt.id != null) {
              await widget.db.deleteReceipt(receipt.id!);
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.danger,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Fiş silindi',
                          style: TextStyle(fontWeight: FontWeight.w500),
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
          },
        ),
      ),
    );
  }

  // ── Kaydırarak silme onay dialog'u ──
  Future<bool> _confirmSwipeDelete(BuildContext context, ReceiptData r) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.danger,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Fişi sil?',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '"${r.firmaAdi.isEmpty ? 'Bilinmeyen Firma' : r.firmaAdi}" silinecek. Geri alınamaz.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.divider),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text(
                        'Vazgeç',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        'Sil',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

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

            // ── Onay Durumu TabBar Seçici ──
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: AppColors.primary,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(text: 'Onay Bekleyenler'),
                  Tab(text: 'Onaylananlar'),
                ],
              ),
            ),

            const SizedBox(height: 6),

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

            // ── Liste Bölümü (TabBarView Entegrasyonu) ──
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

                  // Kategori Filtreleme Uygulaması
                  if (_filter != 'Tümü') {
                    receipts =
                        receipts.where((r) => r.kategori == _filter).toList();
                  }

                  // Fişleri onay durumuna göre ayırma
                  var pendingReceipts = receipts.where((r) {
                    try {
                      return !r.isApproved;
                    } catch (_) {
                      return true; // Varsayılan durum: Onay bekliyor
                    }
                  }).toList();

                  var approvedReceipts = receipts.where((r) {
                    try {
                      return r.isApproved;
                    } catch (_) {
                      return false;
                    }
                  }).toList();

                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTabList(
                        pendingReceipts,
                        'Onay bekleyen fiş bulunamadı.',
                        isPendingTab: true,
                      ),
                      _buildTabList(
                        approvedReceipts,
                        'Onaylanmış harcama bulunamadı.',
                        isPendingTab: false,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabList(
    List<ReceiptData> list,
    String emptyMessage, {
    required bool isPendingTab,
  }) {
    if (list.isEmpty) {
      return _emptyState(message: emptyMessage);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final receipt = list[index];
        return _ReceiptCard(
          receipt: receipt,
          // YENİ: Hem onay bekleyen hem onaylanan TIKLANABİLİR
          // Onay bekleyen → onaylama modu
          // Onaylanan → detay/düzenleme modu (isDetailMode: true)
          onTap: () => _openReceiptDetail(receipt, isDetailMode: !isPendingTab),
          // YENİ: Kaydırma ile silme her iki sekmede de aktif
          onConfirmDelete: () => _confirmSwipeDelete(context, receipt),
          onDeleted: () async {
            if (receipt.id != null) {
              await widget.db.deleteReceipt(receipt.id!);
              if (mounted) setState(() {});
            }
          },
        );
      },
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
// YENİ: Tıklanabilir + Kaydırarak silme + Mini doğruluk badge
// ═══════════════════════════════════════════════════════════════════════
class _ReceiptCard extends StatelessWidget {
  final ReceiptData receipt;
  final VoidCallback? onTap; // Kart tıklama eventi
  final Future<bool> Function()? onConfirmDelete; // Silme onayı dialog'u
  final VoidCallback? onDeleted; // Silme gerçekleşince callback

  const _ReceiptCard({
    required this.receipt,
    this.onTap,
    this.onConfirmDelete,
    this.onDeleted,
  });

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

  // YENİ: Doğruluk oranı rengi
  Color get _confColor {
    final c = receipt.averageConfidence;
    if (c >= 0.80) return AppColors.success;
    if (c >= 0.55) return AppColors.warning;
    return AppColors.danger;
  }

  IconData get _confIcon {
    final c = receipt.averageConfidence;
    if (c >= 0.80) return Icons.verified_rounded;
    if (c >= 0.55) return Icons.info_rounded;
    return Icons.warning_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final conf = receipt.averageConfidence;

    final cardBody = Container(
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
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Görsel veya kategori ikonu
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: receipt.imagePath != null &&
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

                // Firma + Tarih + Kategori
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
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
                          ),
                          // YENİ: Mini doğruluk badge
                          if (conf > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _confColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_confIcon, size: 10, color: _confColor),
                                  const SizedBox(width: 3),
                                  Text(
                                    '%${(conf * 100).round()}',
                                    style: TextStyle(
                                      color: _confColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
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

                const SizedBox(width: 8),

                // Tutar + Chevron
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
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (receipt.uyari != null &&
                            receipt.uyari!.isNotEmpty) ...[
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 4),
                        ],
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Eğer silme fonksiyonları sağlanmadıysa düz kart döner
    if (onConfirmDelete == null || onDeleted == null) {
      return cardBody;
    }

    // Kaydırarak silme
    return Dismissible(
      key: ValueKey('receipt_${receipt.id ?? receipt.hashCode}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
            SizedBox(height: 2),
            Text(
              'Sil',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) => onConfirmDelete!(),
      onDismissed: (_) => onDeleted!(),
      child: cardBody,
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
// ═══════════════════════════════════════════════════════════════════════
// SEKME 3: ÖZET VE EXCEL DIŞA AKTARIM
// ═══════════════════════════════════════════════════════════════════════
class _ExportTab extends StatelessWidget {
  final DatabaseHelper db;
  const _ExportTab({required this.db});

  void _showExportSelectionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => _ExportSelectionSheet(
          db: db,
          scrollController: scrollController,
        ),
      ),
    );
  }

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
              // ── BAŞLIK VE EXCEL BUTONU ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Özet',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.8,
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF107C41), // Premium Excel Yeşili
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.explicit_rounded, size: 18),
                    label: const Text(
                      'Excel\'e Aktar',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    onPressed: () => _showExportSelectionSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Kategori bazlı toplamlar (Mevcut yapı bozulmadan korundu)
              Expanded(
                child: FutureBuilder<Map<String, double>>(
                  future: db.getKategoriToplamlari(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.primary),
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
                    final genelToplam =
                        toplamlar.values.fold(0.0, (a, b) => a + b);

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
                              final renk = AppColors.kategoriRenkler[e.key] ??
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
// EXCEL SEÇİM EKRANI (Premium Bottom Sheet)
// Sadece onaylanmış fişleri gösterir ve seçim yaptırır.
// ═══════════════════════════════════════════════════════════════════════
class _ExportSelectionSheet extends StatefulWidget {
  final DatabaseHelper db;
  final ScrollController scrollController;

  const _ExportSelectionSheet({
    required this.db,
    required this.scrollController,
  });

  @override
  State<_ExportSelectionSheet> createState() => _ExportSelectionSheetState();
}

class _ExportSelectionSheetState extends State<_ExportSelectionSheet> {
  List<ReceiptData> _approvedReceipts = [];
  Set<int> _selectedIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadApprovedReceipts();
  }

  Future<void> _loadApprovedReceipts() async {
    final allReceipts = await widget.db.getAllReceipts();
    setState(() {
      // SADECE onaylanmış fişleri filtreliyoruz
      _approvedReceipts = allReceipts.where((r) => r.isApproved).toList();
      // Varsayılan olarak tümünü seçili hale getirerek kullanıcıya kolaylık sağlıyoruz
      _selectedIds = _approvedReceipts.map((r) => r.id!).toSet();
      _isLoading = false;
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selectedIds.length == _approvedReceipts.length) {
        _selectedIds.clear(); // Hepsini kaldır
      } else {
        _selectedIds =
            _approvedReceipts.map((r) => r.id!).toSet(); // Hepsini seç
      }
    });
  }

  Future<void> _exportSelected() async {
    if (_selectedIds.isEmpty) return;

    // Sadece ID'si seçilmiş olan fişleri filtrele
    final selectedReceipts =
        _approvedReceipts.where((r) => _selectedIds.contains(r.id)).toList();

    // Bottom sheet'i kapat
    Navigator.pop(context);

    // Servise gönder ve Excel oluştur
    await ExcelExportService.exportReceiptsToExcel(selectedReceipts);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // ── Tutamaç ──
          Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          // ── Başlık ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF107C41).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.explicit_rounded,
                    color: Color(0xFF107C41),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Excel\'e Aktar',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Text(
                        'Dışa aktarılacak fişleri seçin',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Seçim Araç Çubuğu ──
          if (!_isLoading && _approvedReceipts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedIds.length} Fiş Seçildi',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontSize: 14,
                    ),
                  ),
                  TextButton(
                    onPressed: _toggleAll,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(50, 30),
                    ),
                    child: Text(
                      _selectedIds.length == _approvedReceipts.length
                          ? 'Tümünü Kaldır'
                          : 'Tümünü Seç',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          // ── Liste ──
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _approvedReceipts.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _approvedReceipts.length,
                        itemBuilder: (context, index) {
                          final receipt = _approvedReceipts[index];
                          final isSelected = _selectedIds.contains(receipt.id);

                          return GestureDetector(
                            onTap: () => _toggleSelection(receipt.id!),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF107C41).withOpacity(0.08)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF107C41).withOpacity(0.5)
                                      : AppColors.divider,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Özel Checkbox
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF107C41)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF107C41)
                                            : AppColors.textTertiary,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check,
                                            size: 16, color: Colors.white)
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          receipt.firmaAdi.isEmpty
                                              ? 'Bilinmeyen Firma'
                                              : receipt.firmaAdi,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                            color: AppColors.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${receipt.tarih} • ${receipt.kategori}',
                                          style: const TextStyle(
                                            color: AppColors.textTertiary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${receipt.toplamTutar} ₺',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // ── Aksiyon Butonu ──
          Container(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, MediaQuery.of(context).viewPadding.bottom + 16),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedIds.isEmpty
                    ? AppColors.surfaceAlt
                    : const Color(0xFF107C41),
                foregroundColor: _selectedIds.isEmpty
                    ? AppColors.textTertiary
                    : Colors.white,
                minimumSize: const Size(double.infinity, 54),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.file_download_outlined, size: 22),
              label: Text(
                _selectedIds.isEmpty
                    ? 'Fiş Seçilmedi'
                    : 'Seçili ${_selectedIds.length} Fişi İndir',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              onPressed: _selectedIds.isEmpty ? null : _exportSelected,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.done_all_rounded,
              size: 32,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Onaylanmış Fiş Yok',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Excel\'e aktarabilmek için önce\ngeçmiş sekmesinden fiş onaylamalısınız.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textTertiary, fontSize: 13, height: 1.4),
          ),
        ],
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
