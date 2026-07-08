import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/receipt_data.dart';

// ═══════════════════════════════════════════════════════════════════════
// MUHASEBECİ ODAKLI EXCEL DIŞA AKTARIM
// ═══════════════════════════════════════════════════════════════════════
// İki sayfa üretir:
//   1) "Fiş Listesi"  → her fiş bir satır (gider listesi / icmal)
//   2) "KDV Detayı"   → her (fiş × KDV oranı) bir satır (KDV beyannamesi için)
// Tutarlar gerçek SAYI hücresi olarak (#,##0.00) yazılır; muhasebe
// programlarına ve formüllere sorunsuz girer. Her sayfada TOPLAM satırı vardır.
// ═══════════════════════════════════════════════════════════════════════
class ExcelExportService {
  // Para renkleri / biçimleri
  static final ExcelColor _headerBg = ExcelColor.fromHexString('#107C41');
  static final ExcelColor _headerFg = ExcelColor.fromHexString('#FFFFFF');
  static final ExcelColor _totalBg = ExcelColor.fromHexString('#D9E1F2');

  /// Tutarları her formattan ("1.250,50 TL", "1,250.50", "1234,56", "1.234.56")
  /// saf double'a çevirir. receipt_parser._normPrice ile aynı kuralı uygular:
  /// son ayraçtan sonra TAM 2 hane varsa ondalık, değilse tüm ayraçlar binlik.
  static double _parseAmount(String amountStr) {
    if (amountStr.isEmpty) return 0.0;
    final String clean = amountStr.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (clean.isEmpty) return 0.0;

    final int lastSep = clean.lastIndexOf(RegExp(r'[.,]'));
    if (lastSep == -1) return double.tryParse(clean) ?? 0.0;

    final String frac = clean.substring(lastSep + 1);
    final String intDigits =
        clean.substring(0, lastSep).replaceAll(RegExp(r'[.,]'), '');

    if (frac.length == 2) {
      final String intPart = intDigits.isEmpty ? '0' : intDigits;
      return double.tryParse('$intPart.$frac') ?? 0.0;
    }
    return double.tryParse(clean.replaceAll(RegExp(r'[.,]'), '')) ?? 0.0;
  }

  /// Fişin KDV hariç tutarını (matrah) verir. Doğrudan okunduysa onu; yoksa
  /// Genel Toplam − Toplam KDV'den hesaplar (muhasebeci her zaman matrah ister).
  static double _kdvHaric(ReceiptData r) {
    final double matrah = _parseAmount(r.kdvHaricToplam);
    if (matrah > 0) return matrah;
    final double toplam = _parseAmount(r.toplamTutar);
    final double kdv = _parseAmount(r.toplamKdv);
    if (toplam > 0 && kdv > 0 && kdv < toplam) return toplam - kdv;
    return matrah; // 0 olabilir (KDV'siz / eksik veri)
  }

  /// "%20" / "20" / "% 20" → "20"
  static String _oranSade(String oran) {
    final m = RegExp(r'(\d{1,2})').firstMatch(oran);
    return m != null ? m.group(1)! : oran.trim();
  }

  // ── Stil yardımcıları ──────────────────────────────────────────────
  static CellStyle _headerStyle() => CellStyle(
        bold: true,
        backgroundColorHex: _headerBg,
        fontColorHex: _headerFg,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

  static CellStyle _moneyStyle({bool bold = false}) => CellStyle(
        bold: bold,
        numberFormat: NumFormat.standard_4, // #,##0.00
        horizontalAlign: HorizontalAlign.Right,
      );

  static CellStyle _totalStyle() => CellStyle(
        bold: true,
        backgroundColorHex: _totalBg,
        numberFormat: NumFormat.standard_4,
        horizontalAlign: HorizontalAlign.Right,
      );

  static CellStyle _totalLabelStyle() => CellStyle(
        bold: true,
        backgroundColorHex: _totalBg,
        horizontalAlign: HorizontalAlign.Right,
      );

  /// SQLite'taki fişleri muhasebeci dostu bir Excel (.xlsx) dosyasına dönüştürür.
  static Future<void> exportReceiptsToExcel(List<ReceiptData> receipts) async {
    final Excel excel = Excel.createExcel();

    // ── Varsayılan sayfayı "Fiş Listesi" yap, sonra "KDV Detayı" ekle ──
    final String defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    const String ozetName = 'Fiş Listesi';
    const String kdvName = 'KDV Detayı';
    excel.rename(defaultSheet, ozetName);

    _buildOzetSheet(excel[ozetName], receipts);
    _buildKdvSheet(excel[kdvName], receipts);

    final List<int>? fileBytes = excel.save();
    if (fileBytes == null) return;

    final Directory directory = await getTemporaryDirectory();
    final String stamp = _dateStamp();
    final String filePath = '${directory.path}/Fis_Raporu_$stamp.xlsx';
    final File file = File(filePath);
    await file.writeAsBytes(fileBytes, flush: true);

    await Share.shareXFiles(
      [
        XFile(
          filePath,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        )
      ],
      subject: 'Fiş / Fatura Gider Raporu',
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SAYFA 1 — FİŞ LİSTESİ (icmal)
  // ═══════════════════════════════════════════════════════════════════
  static void _buildOzetSheet(Sheet sheet, List<ReceiptData> receipts) {
    final List<String> headers = [
      'Sıra',
      'Tarih',
      'Saat',
      'Belge Türü',
      'Belge / Fiş No',
      'Seri No', // Muhasebeci fiş no'dan ayrı olarak seri no'yu da ister
      'ETTN', // e-Arşiv / e-Fatura için muhasebeci tarafından istenir
      'Firma / Satıcı',
      'VKN / TCKN',
      'Vergi Dairesi',
      'Ara Toplam',
      'KDV Hariç (Matrah)',
      'Toplam KDV',
      'KDV Dahil Toplam',
      'Para Birimi',
      'Ödeme Yöntemi',
      'Kategori',
      'Durum',
      'Not',
    ];

    // Para sütunları (0 tabanlı): Ara Toplam, Matrah, KDV, Toplam
    const List<int> moneyCols = [10, 11, 12, 13];
    // TOPLAM satırında "GENEL TOPLAM" etiketinin oturacağı sütun (Vergi Dairesi)
    const int totalLabelCol = 9;

    sheet.appendRow(headers.map((h) => TextCellValue(h) as CellValue).toList());
    _applyRowStyle(sheet, 0, headers.length, _headerStyle());

    double sumAra = 0, sumMatrah = 0, sumKdv = 0, sumToplam = 0;
    int rowIdx = 1;
    int sira = 1;

    for (final r in receipts) {
      final double ara = _parseAmount(r.araToplam);
      final double matrah = _kdvHaric(r);
      final double kdv = _parseAmount(r.toplamKdv);
      final double toplam = _parseAmount(r.toplamTutar);
      sumAra += ara;
      sumMatrah += matrah;
      sumKdv += kdv;
      sumToplam += toplam;

      sheet.appendRow(<CellValue?>[
        IntCellValue(sira),
        TextCellValue(r.tarih),
        TextCellValue(r.saat),
        TextCellValue(r.belgeTuru),
        TextCellValue(r.fisNo),
        TextCellValue(r.seriNo),
        TextCellValue(r.ettn),
        TextCellValue(r.firmaAdi),
        TextCellValue(r.vergiTcNo),
        TextCellValue(r.vergiDairesi),
        _moneyCell(r.araToplam.isNotEmpty && ara > 0 ? ara : null),
        _moneyCell(r.kdvHaricToplam.isNotEmpty || matrah > 0 ? matrah : null),
        _moneyCell(r.toplamKdv.isNotEmpty ? kdv : null),
        _moneyCell(r.toplamTutar.isNotEmpty ? toplam : null),
        TextCellValue(r.paraBirimi.isEmpty ? 'TL' : r.paraBirimi),
        TextCellValue(r.odemeYontemi),
        TextCellValue(r.kategori),
        TextCellValue(r.isApproved ? 'Onaylı' : 'Bekliyor'),
        TextCellValue((r.uyari ?? '').replaceAll('\n', ' | ')),
      ]);

      for (final c in moneyCols) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx))
            .cellStyle = _moneyStyle();
      }
      rowIdx++;
      sira++;
    }

    // ── TOPLAM satırı ──
    if (receipts.isNotEmpty) {
      final List<CellValue?> totalRow =
          List<CellValue?>.filled(headers.length, TextCellValue(''));
      totalRow[totalLabelCol] = TextCellValue('GENEL TOPLAM');
      totalRow[10] = DoubleCellValue(_round2(sumAra));
      totalRow[11] = DoubleCellValue(_round2(sumMatrah));
      totalRow[12] = DoubleCellValue(_round2(sumKdv));
      totalRow[13] = DoubleCellValue(_round2(sumToplam));
      sheet.appendRow(totalRow);

      sheet
          .cell(CellIndex.indexByColumnRow(
              columnIndex: totalLabelCol, rowIndex: rowIdx))
          .cellStyle = _totalLabelStyle();
      for (final c in moneyCols) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx))
            .cellStyle = _totalStyle();
      }
    }

    _setWidths(sheet, const {
      0: 6, // Sıra
      1: 12, // Tarih
      2: 8, // Saat
      3: 18, // Belge Türü
      4: 16, // Belge / Fiş No
      5: 14, // Seri No
      6: 36, // ETTN (UUID uzunluğunda)
      7: 28, // Firma / Satıcı
      8: 14, // VKN / TCKN
      9: 18, // Vergi Dairesi
      10: 14, // Ara Toplam
      11: 16, // KDV Hariç (Matrah)
      12: 14, // Toplam KDV
      13: 16, // KDV Dahil Toplam
      14: 10, // Para Birimi
      15: 16, // Ödeme Yöntemi
      16: 14, // Kategori
      17: 10, // Durum
      18: 30, // Not
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // SAYFA 2 — KDV DETAYI (oran kırılımı, beyanname için)
  // ═══════════════════════════════════════════════════════════════════
  static void _buildKdvSheet(Sheet sheet, List<ReceiptData> receipts) {
    final List<String> headers = [
      'Tarih',
      'Belge / Fiş No',
      'Firma / Satıcı',
      'VKN / TCKN',
      'KDV Oranı (%)',
      'Matrah',
      'KDV Tutarı',
    ];
    const List<int> moneyCols = [5, 6];

    sheet.appendRow(headers.map((h) => TextCellValue(h) as CellValue).toList());
    _applyRowStyle(sheet, 0, headers.length, _headerStyle());

    double sumMatrah = 0, sumKdv = 0;
    int rowIdx = 1;

    for (final r in receipts) {
      final String belgeNo = r.fisNo.isNotEmpty ? r.fisNo : r.seriNo;

      if (r.kdvDetay.isNotEmpty) {
        for (final item in r.kdvDetay) {
          final double matrah = _parseAmount(item.matrah);
          final double kdv = _parseAmount(item.tutar);
          sumMatrah += matrah;
          sumKdv += kdv;
          sheet.appendRow(<CellValue?>[
            TextCellValue(r.tarih),
            TextCellValue(belgeNo),
            TextCellValue(r.firmaAdi),
            TextCellValue(r.vergiTcNo),
            TextCellValue(_oranSade(item.oran)),
            _moneyCell(item.matrah.isNotEmpty ? matrah : null),
            _moneyCell(item.tutar.isNotEmpty ? kdv : null),
          ]);
          for (final c in moneyCols) {
            sheet
                .cell(CellIndex.indexByColumnRow(
                    columnIndex: c, rowIndex: rowIdx))
                .cellStyle = _moneyStyle();
          }
          rowIdx++;
        }
      } else if (r.toplamKdv.isNotEmpty) {
        // Oran kırılımı yoksa tek satırlık özet (oran boş).
        final double matrah = _kdvHaric(r);
        final double kdv = _parseAmount(r.toplamKdv);
        sumMatrah += matrah;
        sumKdv += kdv;
        sheet.appendRow(<CellValue?>[
          TextCellValue(r.tarih),
          TextCellValue(belgeNo),
          TextCellValue(r.firmaAdi),
          TextCellValue(r.vergiTcNo),
          TextCellValue(''),
          _moneyCell(matrah > 0 ? matrah : null),
          _moneyCell(kdv),
        ]);
        for (final c in moneyCols) {
          sheet
              .cell(
                  CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx))
              .cellStyle = _moneyStyle();
        }
        rowIdx++;
      }
    }

    if (rowIdx > 1) {
      sheet.appendRow(<CellValue?>[
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('TOPLAM'),
        DoubleCellValue(_round2(sumMatrah)),
        DoubleCellValue(_round2(sumKdv)),
      ]);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx))
          .cellStyle = _totalLabelStyle();
      for (final c in moneyCols) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx))
            .cellStyle = _totalStyle();
      }
    }

    _setWidths(sheet, const {
      0: 12,
      1: 16,
      2: 28,
      3: 14,
      4: 12,
      5: 16,
      6: 16,
    });
  }

  // ── Ortak yardımcılar ──────────────────────────────────────────────
  static CellValue _moneyCell(double? v) =>
      v == null ? TextCellValue('') : DoubleCellValue(_round2(v));

  static double _round2(double v) => (v * 100).round() / 100;

  static void _applyRowStyle(
      Sheet sheet, int rowIndex, int colCount, CellStyle style) {
    for (int c = 0; c < colCount; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex))
          .cellStyle = style;
    }
  }

  static void _setWidths(Sheet sheet, Map<int, double> widths) {
    widths.forEach((col, w) => sheet.setColumnWidth(col, w));
  }

  static String _dateStamp() {
    final now = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }
}
