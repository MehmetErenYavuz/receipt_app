import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/receipt_data.dart';
import '../main.dart'; // AppColors

class ResultSheet extends StatefulWidget {
  final ReceiptData data;
  final VoidCallback onSave;
  final VoidCallback onEdit;

  /// YENİ: Detay modu - kayıtlı bir fişi görüntülemek/düzenlemek için kullanılır.
  /// true ise: Silme butonu görünür, "Değişiklikleri Kaydet" yazar.
  /// false ise: Yeni fiş analizi modu (varsayılan davranış).
  final bool isDetailMode;

  /// YENİ: Detay modunda silme butonuna basıldığında çağrılır.
  final VoidCallback? onDelete;

  const ResultSheet({
    super.key,
    required this.data,
    required this.onSave,
    required this.onEdit,
    this.isDetailMode = false, // Geriye dönük uyumluluk için varsayılan false
    this.onDelete,
  });

  @override
  State<ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<ResultSheet> {
  late final Map<String, TextEditingController> _controllers;
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _controllers = {
      'firma': TextEditingController(text: d.firmaAdi),
      'vergi': TextEditingController(text: d.vergiTcNo),
      'fisNo': TextEditingController(text: d.fisNo),
      'seri': TextEditingController(text: d.seriNo),
      'tarih': TextEditingController(text: d.tarih),
      'saat': TextEditingController(text: d.saat),
      'kdv': TextEditingController(text: d.toplamKdv),
      'toplam': TextEditingController(text: d.toplamTutar),
      'kategori': TextEditingController(text: d.kategori),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── TAM EKRAN GÖRSEL İNCELEYİCİ ──
  void _showZoomedImage(BuildContext context, String path) {
    showDialog(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black.withOpacity(0.95),
      builder: (_) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Resim (Zoom edilebilir)
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 5.0,
                panEnabled: true,
                child: Image.file(File(path), fit: BoxFit.contain),
              ),
            ),
            // Kapat Butonu
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Doğruluk Oranı Yardımcıları ──────────────────────────────────
  Color _confMainColor(double conf) {
    if (conf >= 0.80) return AppColors.success;
    if (conf >= 0.55) return AppColors.warning;
    return AppColors.danger;
  }

  Color _confBgColor(double conf) {
    if (conf >= 0.80) return AppColors.success.withOpacity(0.08);
    if (conf >= 0.55) return AppColors.warning.withOpacity(0.08);
    return AppColors.danger.withOpacity(0.08);
  }

  Color _confBorderColor(double conf) {
    if (conf >= 0.80) return AppColors.success.withOpacity(0.25);
    if (conf >= 0.55) return AppColors.warning.withOpacity(0.25);
    return AppColors.danger.withOpacity(0.25);
  }

  IconData _confIcon(double conf) {
    if (conf >= 0.80) return Icons.verified_rounded;
    if (conf >= 0.55) return Icons.info_rounded;
    return Icons.warning_rounded;
  }

  String _confLabel(double conf) {
    if (conf >= 0.80) return 'Yüksek';
    if (conf >= 0.55) return 'Orta';
    return 'Düşük';
  }

  String _confSubtitle(double conf) {
    if (conf >= 0.80) return 'Güvenli kayıt';
    if (conf >= 0.55) return 'Kontrol önerilir';
    return 'Manuel kontrol şart';
  }

  // ─── Silme Onay Dialog'u ──────────────────────────────────────────
  Future<void> _handleDelete(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
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
              const Text(
                'Bu işlem geri alınamaz. Fiş ve varsa fotoğrafı kalıcı olarak silinecek.',
                textAlign: TextAlign.center,
                style: TextStyle(
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

    if (confirmed == true && mounted) {
      Navigator.pop(context); // Önce bottom sheet'i kapat
      widget.onDelete?.call(); // Sonra silme callback'ini çağır
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final conf = d.averageConfidence;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background, // Premium sade arkaplan
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isDetailMode ? 'Fiş Detayı' : 'Fiş Analizi',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Text(
                        widget.isDetailMode
                            ? (_editMode
                                ? 'Bilgileri düzenleyin'
                                : 'Bilgileri görüntülüyorsunuz')
                            : 'Verileri kontrol edip kaydedin',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                // Düzenle toggle (Premium tarz)
                Material(
                  color: _editMode
                      ? AppColors.success.withOpacity(0.12)
                      : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _editMode = !_editMode),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        _editMode ? Icons.check_rounded : Icons.edit_outlined,
                        color: _editMode
                            ? AppColors.success
                            : AppColors.textPrimary,
                        size: 22,
                      ),
                    ),
                  ),
                ),

                // Detay modunda silme butonu
                if (widget.isDetailMode) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: AppColors.danger.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _handleDelete(context),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.danger,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── DOĞRULUK ORANI BÜYÜK KARTI ──
          Container(
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _confBgColor(conf),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _confBorderColor(conf), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _confMainColor(conf).withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _confIcon(conf),
                    color: _confMainColor(conf),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Doğruluk Oranı',
                            style: TextStyle(
                              color: _confMainColor(conf),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: _confMainColor(conf).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _confLabel(conf),
                              style: TextStyle(
                                color: _confMainColor(conf),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '%${(conf * 100).round()}',
                            style: TextStyle(
                              color: _confMainColor(conf),
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              _confSubtitle(conf),
                              style: TextStyle(
                                color: _confMainColor(conf).withOpacity(0.75),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Fiş Görseli Önizleme (Tıklanabilir Premium Tasarım) ──
          if (d.imagePath != null && File(d.imagePath!).existsSync())
            GestureDetector(
              onTap: () => _showZoomedImage(context, d.imagePath!),
              child: Container(
                height: 130,
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  image: DecorationImage(
                    image: FileImage(File(d.imagePath!)),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
                child: Stack(
                  children: [
                    // Alt kısımdaki karartma efekti (yazı okunsun diye)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(16),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.6),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Büyüteç ikonu ve yazısı
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.zoom_in_rounded,
                              size: 16,
                              color: AppColors.textPrimary,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Fotoğrafı Büyüt',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Uyarı ──
          if (d.uyari != null)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.danger.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.danger,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      d.uyari!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── İçerik (Scroll edilebilir alan) ──
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── İşletme Bilgileri ──
                  const _SectionHeader(
                    title: 'İşletme Bilgileri',
                    icon: Icons.storefront_rounded,
                  ),
                  _EditableRow(
                    icon: Icons.business_rounded,
                    label: 'Firma Adı',
                    controller: _controllers['firma']!,
                    editMode: _editMode,
                    confidence: d.confidenceScores['firma'],
                  ),
                  if (d.firmaAdresi.isNotEmpty)
                    _StaticRow(
                      icon: Icons.location_on_outlined,
                      label: 'Adres',
                      value: d.firmaAdresi,
                    ),
                  if (d.vergiDairesi.isNotEmpty)
                    _StaticRow(
                      icon: Icons.account_balance_outlined,
                      label: 'Vergi Dairesi',
                      value: d.vergiDairesi,
                    ),
                  _EditableRow(
                    icon: Icons.badge_outlined,
                    label:
                        d.vergiTcNo.length == 11 ? 'TC Kimlik No' : 'Vergi No',
                    controller: _controllers['vergi']!,
                    editMode: _editMode,
                    confidence: d.confidenceScores['vergi'],
                  ),
                  if (d.telefon != null && d.telefon!.isNotEmpty)
                    _StaticRow(
                      icon: Icons.phone_outlined,
                      label: 'Telefon',
                      value: d.telefon!,
                    ),
                  if (d.mersisNo.isNotEmpty)
                    _StaticRow(
                      icon: Icons.fingerprint_rounded,
                      label: 'Mersis No',
                      value: d.mersisNo,
                    ),

                  const SizedBox(height: 24),

                  // ── Belge Bilgileri ──
                  const _SectionHeader(
                    title: 'Belge Bilgileri',
                    icon: Icons.description_outlined,
                  ),
                  if (d.belgeTuru.isNotEmpty)
                    _StaticRow(
                      icon: Icons.article_outlined,
                      label: 'Belge Türü',
                      value: d.belgeTuru,
                    ),
                  _EditableRow(
                    icon: Icons.tag_rounded,
                    label: 'Fiş / Belge No',
                    controller: _controllers['fisNo']!,
                    editMode: _editMode,
                    confidence: d.confidenceScores['fisNo'],
                  ),
                  if (d.seriNo.isNotEmpty)
                    _StaticRow(
                      icon: Icons.format_list_numbered_rtl,
                      label: 'Seri No',
                      value: d.seriNo,
                    ),
                  if (d.zNo.isNotEmpty)
                    _StaticRow(
                      icon: Icons.summarize_outlined,
                      label: 'Z No',
                      value: d.zNo,
                    ),
                  if (d.ekuNo.isNotEmpty)
                    _StaticRow(
                      icon: Icons.memory_rounded,
                      label: 'EKÜ No',
                      value: d.ekuNo,
                    ),
                  if (d.ettn.isNotEmpty)
                    _StaticRow(
                      icon: Icons.qr_code_2_rounded,
                      label: 'ETTN',
                      value: d.ettn,
                    ),
                  if (d.iban.isNotEmpty)
                    _StaticRow(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'IBAN',
                      value: d.iban,
                    ),

                  const SizedBox(height: 24),

                  // ── Zaman ──
                  const _SectionHeader(
                    title: 'Tarih / Saat',
                    icon: Icons.schedule_rounded,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _EditableRow(
                          icon: Icons.calendar_today_rounded,
                          label: 'Tarih',
                          controller: _controllers['tarih']!,
                          editMode: _editMode,
                          confidence: d.confidenceScores['tarih'],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _EditableRow(
                          icon: Icons.access_time_rounded,
                          label: 'Saat',
                          controller: _controllers['saat']!,
                          editMode: _editMode,
                          confidence: d.confidenceScores['saat'],
                        ),
                      ),
                    ],
                  ),

                  // ── Yakıt Detayları (varsa) ──
                  if (d.isYakitFisi) ...[
                    const SizedBox(height: 24),
                    const _SectionHeader(
                      title: 'Yakıt Detayları',
                      icon: Icons.local_gas_station_rounded,
                    ),
                    if (d.yakitTuru != null)
                      _StaticRow(
                        icon: Icons.water_drop_outlined,
                        label: 'Yakıt Türü',
                        value: d.yakitTuru!,
                      ),
                    if (d.yakitLitre != null)
                      _StaticRow(
                        icon: Icons.opacity_rounded,
                        label: 'Miktar',
                        value: d.yakitLitre!,
                      ),
                    if (d.pompaNo != null)
                      _StaticRow(
                        icon: Icons.local_gas_station_outlined,
                        label: 'Pompa',
                        value: d.pompaNo!,
                      ),
                    if (d.aracPlakasi != null)
                      _StaticRow(
                        icon: Icons.directions_car_rounded,
                        label: 'Plaka',
                        value: d.aracPlakasi!,
                      ),
                  ],

                  const SizedBox(height: 24),

                  // ── KDV Detayları ──
                  const _SectionHeader(
                    title: 'KDV Detayları',
                    icon: Icons.percent_rounded,
                  ),
                  if (d.kdvDetay.isNotEmpty)
                    ...d.kdvDetay.map((item) => _KdvDetailRow(item: item)),
                  _EditableRow(
                    icon: Icons.receipt_outlined,
                    label: 'Toplam KDV',
                    controller: _controllers['kdv']!,
                    editMode: _editMode,
                    suffix: '₺',
                    confidence: d.confidenceScores['kdv'],
                  ),
                  if (d.kdvHaricToplam.isNotEmpty)
                    _StaticRow(
                      icon: Icons.remove_circle_outline_rounded,
                      label: 'Matrah (KDV Hariç)',
                      value: '${d.kdvHaricToplam} ₺',
                    ),
                  if (d.araToplam.isNotEmpty)
                    _StaticRow(
                      icon: Icons.functions_rounded,
                      label: 'Ara Toplam',
                      value: '${d.araToplam} ₺',
                    ),

                  const SizedBox(height: 24),

                  // ── Ödeme ──
                  const _SectionHeader(
                    title: 'Ödeme Bilgileri',
                    icon: Icons.payments_rounded,
                  ),

                  // GENEL TOPLAM — Vurgulu Premium Kart
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.payments_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'GENEL TOPLAM',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        if (_editMode)
                          SizedBox(
                            width: 130,
                            child: TextField(
                              controller: _controllers['toplam']!,
                              textAlign: TextAlign.right,
                              keyboardType: TextInputType.text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.15),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                suffixText: '₺',
                                suffixStyle: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          )
                        else
                          Text(
                            '${_controllers['toplam']!.text.isEmpty ? '—' : _controllers['toplam']!.text} ₺',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (d.odemeYontemi.isNotEmpty)
                    _StaticRow(
                      icon: Icons.credit_card_rounded,
                      label: 'Ödeme Yöntemi',
                      value: d.odemeYontemi,
                    ),
                  if (d.paraUstu.isNotEmpty)
                    _StaticRow(
                      icon: Icons.attach_money_rounded,
                      label: 'Para Üstü',
                      value: '${d.paraUstu} ₺',
                    ),

                  const SizedBox(height: 24),

                  // ── Kategori ──
                  const _SectionHeader(
                    title: 'Kategori',
                    icon: Icons.category_outlined,
                  ),
                  _CategorySelector(
                    selected: _controllers['kategori']!.text,
                    onChanged: (v) =>
                        setState(() => _controllers['kategori']!.text = v),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),

          // ── Aksiyon Butonları ──
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(context).viewPadding.bottom + 16,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(
                        color: AppColors.divider,
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      widget.isDetailMode ? 'Kapat' : 'İptal',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    icon: Icon(
                      widget.isDetailMode
                          ? Icons.save_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 22,
                    ),
                    label: Text(
                      widget.isDetailMode
                          ? 'Değişiklikleri Kaydet'
                          : 'Onayla ve Kaydet',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    onPressed: () {
                      widget.data.firmaAdi = _controllers['firma']!.text;
                      widget.data.vergiTcNo = _controllers['vergi']!.text;
                      widget.data.fisNo = _controllers['fisNo']!.text;
                      widget.data.tarih = _controllers['tarih']!.text;
                      widget.data.saat = _controllers['saat']!.text;
                      widget.data.toplamKdv = _controllers['kdv']!.text;
                      widget.data.toplamTutar = _controllers['toplam']!.text;
                      widget.data.kategori = _controllers['kategori']!.text;
                      Navigator.pop(context);
                      widget.onSave();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION HEADER (Sadeleştirildi)
// ═══════════════════════════════════════════════════════════════════════
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════
// STATIC ROW
// ═══════════════════════════════════════════════════════════════════════
class _StaticRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StaticRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textTertiary, size: 18),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════
// EDITABLE ROW (Doğruluk Oranı Noktası İle)
// ═══════════════════════════════════════════════════════════════════════
class _EditableRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool editMode;
  final String? suffix;
  final double? confidence;

  const _EditableRow({
    required this.icon,
    required this.label,
    required this.controller,
    required this.editMode,
    this.suffix,
    this.confidence,
  });

  Color _confColor() {
    if (confidence == null) return Colors.transparent;
    if (confidence! >= 0.85) return AppColors.success;
    if (confidence! >= 0.65) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textTertiary, size: 18),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Güven noktası (Tasarım aynı korundu)
            if (confidence != null)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _confColor(),
                ),
              ),
            Expanded(
              flex: 3,
              child: editMode
                  ? TextField(
                      controller: controller,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceAlt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        suffixText: suffix,
                        suffixStyle: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 13,
                        ),
                      ),
                      textAlign: TextAlign.right,
                    )
                  : GestureDetector(
                      onLongPress: () {
                        Clipboard.setData(ClipboardData(text: controller.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$label kopyalandı'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Text(
                        controller.text.isEmpty
                            ? '—'
                            : '${controller.text}${suffix != null ? ' $suffix' : ''}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: controller.text.isEmpty
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════
// KDV DETAY ROW
// ═══════════════════════════════════════════════════════════════════════
class _KdvDetailRow extends StatelessWidget {
  final dynamic item;
  const _KdvDetailRow({required this.item});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(
              Icons.subdirectory_arrow_right_rounded,
              color: AppColors.textTertiary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.oran,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (item.matrah != null && item.matrah.toString().isNotEmpty)
              Text(
                'Matrah: ${item.matrah} ₺',
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 13),
              ),
            const Spacer(),
            Text(
              'KDV: ${item.tutar} ₺',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════
// CATEGORY SELECTOR
// ═══════════════════════════════════════════════════════════════════════
class _CategorySelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _CategorySelector({required this.selected, required this.onChanged});

  static const _categories = [
    ('Market', Icons.shopping_basket_rounded),
    ('Yeme-İçme', Icons.restaurant_rounded),
    ('Yakıt', Icons.local_gas_station_rounded),
    ('Sağlık', Icons.local_hospital_rounded),
    ('Giyim', Icons.checkroom_rounded),
    ('Elektronik', Icons.devices_rounded),
    ('Ulaşım', Icons.directions_car_rounded),
    ('Faturalar', Icons.receipt_rounded),
    ('Diğer', Icons.more_horiz_rounded),
  ];

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _categories.map((cat) {
          final isSelected = selected == cat.$1;
          final renk = AppColors.kategoriRenkler[cat.$1] ?? AppColors.primary;

          return GestureDetector(
            onTap: () => onChanged(cat.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? renk : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? renk : AppColors.divider,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cat.$2,
                    size: 16,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    cat.$1,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
}
