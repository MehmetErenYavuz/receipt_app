import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/receipt_data.dart';

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
  // Düzenlenebilir alanlar için controller'lar
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
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final conf = d.averageConfidence;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Tutamaç ──
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── Başlık ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.blueAccent),
                const SizedBox(width: 10),
                const Text(
                  'Fiş Analizi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Güven badge
                _ConfidenceBadge(confidence: conf),
                const SizedBox(width: 8),
                // Düzenle toggle
                IconButton(
                  icon: Icon(
                    _editMode ? Icons.check_circle : Icons.edit,
                    color: _editMode ? Colors.greenAccent : Colors.white54,
                  ),
                  onPressed: () => setState(() => _editMode = !_editMode),
                ),
              ],
            ),
          ),

          // ── Uyarı (varsa) ──
          if (d.uyari != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    color: Colors.orangeAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      d.uyari!,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── İçerik ──
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Firma Bilgileri
                  _SectionHeader(
                    title: 'İşletme Bilgileri',
                    icon: Icons.business,
                  ),
                  _EditableRow(
                    icon: Icons.store,
                    label: 'Firma Adı',
                    controller: _controllers['firma']!,
                    editMode: _editMode,
                    confidence: d.confidenceScores['firma'],
                  ),
                  if (d.firmaAdresi.isNotEmpty)
                    _StaticRow(
                      icon: Icons.location_on,
                      label: 'Adres',
                      value: d.firmaAdresi,
                    ),
                  if (d.vergiDairesi.isNotEmpty)
                    _StaticRow(
                      icon: Icons.account_balance,
                      label: 'Vergi Dairesi',
                      value: d.vergiDairesi,
                    ),
                  _EditableRow(
                    icon: Icons.badge,
                    label: d.vergiTcNo.length == 11
                        ? 'TC Kimlik No'
                        : 'Vergi No (VKN)',
                    controller: _controllers['vergi']!,
                    editMode: _editMode,
                    confidence: d.confidenceScores['vergi'],
                  ),

                  const SizedBox(height: 12),
                  // Belge Bilgileri
                  _SectionHeader(
                    title: 'Belge Bilgileri',
                    icon: Icons.description,
                  ),
                  if (d.belgeTuru.isNotEmpty)
                    _StaticRow(
                      icon: Icons.article,
                      label: 'Belge Türü',
                      value: d.belgeTuru,
                    ),
                  _EditableRow(
                    icon: Icons.numbers,
                    label: 'Fiş / Belge No',
                    controller: _controllers['fisNo']!,
                    editMode: _editMode,
                    confidence: d.confidenceScores['fisNo'],
                  ),
                  if (d.seriNo.isNotEmpty)
                    _StaticRow(
                      icon: Icons.tag,
                      label: 'Seri No',
                      value: d.seriNo,
                    ),
                  if (d.zNo.isNotEmpty)
                    _StaticRow(
                      icon: Icons.summarize,
                      label: 'Z No',
                      value: d.zNo,
                    ),

                  const SizedBox(height: 12),
                  // Zaman
                  _SectionHeader(title: 'Tarih / Saat', icon: Icons.schedule),
                  Row(
                    children: [
                      Expanded(
                        child: _EditableRow(
                          icon: Icons.calendar_today,
                          label: 'Tarih',
                          controller: _controllers['tarih']!,
                          editMode: _editMode,
                          confidence: d.confidenceScores['tarih'],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _EditableRow(
                          icon: Icons.access_time,
                          label: 'Saat',
                          controller: _controllers['saat']!,
                          editMode: _editMode,
                          confidence: d.confidenceScores['saat'],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  // KDV Detayları
                  _SectionHeader(title: 'KDV Detayları', icon: Icons.percent),
                  if (d.kdvDetay.isNotEmpty)
                    ...d.kdvDetay.map((item) => _KdvDetailRow(item: item)),
                  _EditableRow(
                    icon: Icons.receipt,
                    label: 'Toplam KDV',
                    controller: _controllers['kdv']!,
                    editMode: _editMode,
                    suffix: 'TL',
                    confidence: d.confidenceScores['kdv'],
                  ),
                  if (d.kdvHaricToplam.isNotEmpty)
                    _StaticRow(
                      icon: Icons.remove_circle_outline,
                      label: 'Matrah (KDV Hariç)',
                      value: '${d.kdvHaricToplam} TL',
                    ),

                  const SizedBox(height: 12),
                  // Toplam
                  _SectionHeader(title: 'Ödeme', icon: Icons.payments),
                  // GENEL TOPLAM — vurgulu
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blueAccent.withOpacity(0.2),
                          Colors.blueAccent.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.blueAccent.withOpacity(0.4),
                      ),
                    ),
                    child: _EditableRow(
                      icon: Icons.price_check,
                      label: 'GENEL TOPLAM',
                      controller: _controllers['toplam']!,
                      editMode: _editMode,
                      suffix: 'TL',
                      isHighlight: true,
                      confidence: d.confidenceScores['toplam'],
                    ),
                  ),
                  if (d.odemeYontemi.isNotEmpty)
                    _StaticRow(
                      icon: Icons.credit_card,
                      label: 'Ödeme Yöntemi',
                      value: d.odemeYontemi,
                    ),
                  if (d.paraUstu.isNotEmpty)
                    _StaticRow(
                      icon: Icons.money_off,
                      label: 'Para Üstü',
                      value: '${d.paraUstu} TL',
                    ),

                  const SizedBox(height: 12),
                  // Kategori
                  _SectionHeader(title: 'Sınıflandırma', icon: Icons.category),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 8)],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.close),
                    label: const Text('İPTAL'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.save),
                    label: const Text('ONAYLA VE KAYDET'),
                    onPressed: () {
                      // Düzenlenen değerleri geri yaz
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

// ── Alt Widget'lar ──────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 2),
    child: Row(
      children: [
        Icon(icon, size: 14, color: Colors.blueAccent),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: Colors.blueAccent,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: Colors.white12)),
      ],
    ),
  );
}

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
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, color: Colors.white38, size: 18),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ],
    ),
  );
}

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
    if (confidence! >= 0.85) return Colors.greenAccent;
    if (confidence! >= 0.65) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, color: Colors.white38, size: 18),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              color: isHighlight ? Colors.white : Colors.white54,
              fontSize: isHighlight ? 14 : 13,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
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
                  style: TextStyle(
                    color: isHighlight ? Colors.greenAccent : Colors.white,
                    fontSize: isHighlight ? 16 : 14,
                    fontWeight: isHighlight
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                    suffix: suffix != null
                        ? Text(
                            suffix!,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          )
                        : null,
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
                      color: isHighlight
                          ? Colors.greenAccent
                          : controller.text.isEmpty
                          ? Colors.white30
                          : Colors.white,
                      fontSize: isHighlight ? 16 : 14,
                      fontWeight: isHighlight
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
        ),
      ],
    ),
  );
}

class _KdvDetailRow extends StatelessWidget {
  final dynamic item;
  const _KdvDetailRow({required this.item});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        const Icon(Icons.arrow_right, color: Colors.white24, size: 18),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            item.oran,
            style: const TextStyle(
              color: Colors.blueAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (item.matrah.isNotEmpty)
          Text(
            'Matrah: ${item.matrah} TL  ',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        const Spacer(),
        Text(
          'KDV: ${item.tutar} TL',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    ),
  );
}

class _ConfidenceBadge extends StatelessWidget {
  final double confidence;
  const _ConfidenceBadge({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).round();
    Color color;
    String label;
    if (pct >= 80) {
      color = Colors.green;
      label = '$pct% Yüksek';
    } else if (pct >= 55) {
      color = Colors.orange;
      label = '$pct% Orta';
    } else {
      color = Colors.red;
      label = '$pct% Düşük';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _CategorySelector({required this.selected, required this.onChanged});

  static const _categories = [
    ('Market', Icons.shopping_cart),
    ('Yeme-İçme', Icons.restaurant),
    ('Yakıt', Icons.local_gas_station),
    ('Sağlık', Icons.local_hospital),
    ('Giyim', Icons.checkroom),
    ('Elektronik', Icons.devices),
    ('Ulaşım', Icons.directions_car),
    ('Diğer', Icons.more_horiz),
  ];

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: _categories.map((cat) {
      final isSelected = selected == cat.$1;
      return GestureDetector(
        onTap: () => onChanged(cat.$1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blueAccent.withOpacity(0.25)
                : Colors.white10,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.blueAccent : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                cat.$2,
                size: 14,
                color: isSelected ? Colors.blueAccent : Colors.white54,
              ),
              const SizedBox(width: 4),
              Text(
                cat.$1,
                style: TextStyle(
                  color: isSelected ? Colors.blueAccent : Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(),
  );
}
