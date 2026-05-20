import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/receipt_data.dart';
import '../main.dart'; // AppColors

class ResultSheet extends StatefulWidget {
  final ReceiptData data;
  final VoidCallback onSave;
  final VoidCallback onEdit;

  const ResultSheet({
    super.key,
    required this.data,
    required this.onSave,
    required this.onEdit,
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

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final conf = d.averageConfidence;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.amber,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Tutamaç ──
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── Başlık ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Colors.deepOrange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fiş Analizi',
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Text(
                        'Verileri kontrol edip kaydedin',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                _ConfidenceBadge(confidence: conf),
                const SizedBox(width: 8),
                // Düzenle toggle
                Material(
                  color: _editMode
                      ? AppColors.success.withOpacity(0.12)
                      : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _editMode = !_editMode),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        _editMode ? Icons.check_rounded : Icons.edit_outlined,
                        color: _editMode
                            ? AppColors.success
                            : AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Uyarı ──
          if (d.uyari != null)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      d.uyari!,
                      style: TextStyle(
                        color: AppColors.warning.withRed(180),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── İçerik ──
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                    label: d.vergiTcNo.length == 11
                        ? 'TC Kimlik No'
                        : 'Vergi No',
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

                  const SizedBox(height: 18),

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

                  const SizedBox(height: 18),

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
                    const SizedBox(height: 18),
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

                  const SizedBox(height: 18),

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

                  const SizedBox(height: 18),

                  // ── Ödeme ──
                  const _SectionHeader(
                    title: 'Ödeme',
                    icon: Icons.payments_rounded,
                  ),

                  // GENEL TOPLAM — vurgulu kart
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.payments_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'GENEL TOPLAM',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
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
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
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
                              fontSize: 22,
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

                  const SizedBox(height: 18),

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

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ── Aksiyon Butonları ──
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
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
                      side: const BorderSide(color: AppColors.divider),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'İptal',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text(
                      'Onayla ve Kaydet',
                      style: TextStyle(
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
// SECTION HEADER
// ═══════════════════════════════════════════════════════════════════════
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 2),
    child: Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
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
    padding: const EdgeInsets.symmetric(vertical: 7),
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
              fontSize: 13.5,
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
              fontSize: 13.5,
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
// EDITABLE ROW
// ═══════════════════════════════════════════════════════════════════════
class _EditableRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool editMode;
  final String? suffix;
  final bool isHighlight;
  final double? confidence;

  const _EditableRow({
    required this.icon,
    required this.label,
    required this.controller,
    required this.editMode,
    this.suffix,
    this.isHighlight = false,
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
    padding: const EdgeInsets.symmetric(vertical: 7),
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
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // Güven noktası
        if (confidence != null)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
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
                      horizontal: 10,
                      vertical: 8,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    suffixText: suffix,
                    suffixStyle: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
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
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        const Icon(
          Icons.subdirectory_arrow_right_rounded,
          color: AppColors.textTertiary,
          size: 16,
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            item.oran,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (item.matrah != null && item.matrah.toString().isNotEmpty)
          Text(
            'Matrah: ${item.matrah} ₺',
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
        const Spacer(),
        Text(
          'KDV: ${item.tutar} ₺',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// CONFIDENCE BADGE
// ═══════════════════════════════════════════════════════════════════════
class _ConfidenceBadge extends StatelessWidget {
  final double confidence;
  const _ConfidenceBadge({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).round();
    Color color;
    String label;
    IconData icon;
    if (pct >= 80) {
      color = AppColors.success;
      label = '$pct%';
      icon = Icons.check_circle_rounded;
    } else if (pct >= 55) {
      color = AppColors.warning;
      label = '$pct%';
      icon = Icons.info_rounded;
    } else {
      color = AppColors.danger;
      label = '$pct%';
      icon = Icons.error_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
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
    spacing: 8,
    runSpacing: 8,
    children: _categories.map((cat) {
      final isSelected = selected == cat.$1;
      final renk = AppColors.kategoriRenkler[cat.$1] ?? AppColors.primary;
      return GestureDetector(
        onTap: () => onChanged(cat.$1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? renk : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(20),
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
                size: 14,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                cat.$1,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                  fontSize: 12.5,
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
