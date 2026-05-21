import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/receipt_data.dart';

class ExcelExportService {
  /// Tutarları (KDV, Toplam) her türlü formattan saf double sayıya çeviren akıllı ayrıştırıcı.
  /// Örn: "1.250,50 TL" -> 1250.50 | "1,250.50" -> 1250.50 | "250,00" -> 250.00
  static double _parseAmount(String amountStr) {
    if (amountStr.isEmpty) return 0.0;

    // 1. Sadece rakam, nokta ve virgülü bırakır (TL, ₺, harf ve boşlukları siler)
    String clean = amountStr.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (clean.isEmpty) return 0.0;

    int lastDot = clean.lastIndexOf('.');
    int lastComma = clean.lastIndexOf(',');

    // 2. Format kontrolü ve düzeltmesi
    if (lastDot > -1 && lastComma > -1) {
      if (lastComma > lastDot) {
        // Türk formatı: 1.234,56 -> Noktaları sil, virgülü noktaya çevir -> 1234.56
        clean = clean.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // Uluslararası format: 1,234.56 -> Virgülleri sil -> 1234.56
        clean = clean.replaceAll(',', '');
      }
    } else if (lastComma > -1) {
      // Sadece virgül varsa: 250,50 -> 250.50
      clean = clean.replaceAll(',', '.');
    }
    // Sadece nokta varsa veya hiçbiri yoksa zaten double formatına uygundur (Örn: 250.50 veya 250)

    return double.tryParse(clean) ?? 0.0;
  }

  /// SQLite veritabanındaki fiş verilerini gerçek bir Excel (.xlsx) tablosuna dönüştürür.
  static Future<void> exportReceiptsToExcel(List<ReceiptData> receipts) async {
    // Yeni ve gerçek bir Excel çalışma kitabı oluşturulur
    final Excel excel = Excel.createExcel();

    const String sheetName = "Fiş Raporu";
    final String defaultSheet = excel.getDefaultSheet() ?? "Sheet1";
    excel.rename(defaultSheet, sheetName);

    final Sheet sheet = excel[sheetName];

    // Tablo Başlıkları
    final List<CellValue> headers = [
      TextCellValue('Tarih'),
      TextCellValue('Firma Adı'),
      TextCellValue('TC / Vergi No'),
      TextCellValue('Fiş / Seri No'),
      TextCellValue('Kategori'),
      TextCellValue('KDV Tutarı (₺)'),
      TextCellValue('Toplam Tutar (₺)'),
    ];
    sheet.appendRow(headers);

    // Fiş Verileri Hücrelere Yazılır
    for (final ReceiptData r in receipts) {
      // ── AKILLI TUTAR DÖNÜŞÜMÜ BURADA DEVREYE GİRİYOR ──
      final double kdvDouble = _parseAmount(r.toplamKdv);
      final double toplamDouble = _parseAmount(r.toplamTutar);

      String belgeNo = r.fisNo.isNotEmpty ? r.fisNo : r.seriNo;

      sheet.appendRow([
        TextCellValue(r.tarih),
        TextCellValue(r.firmaAdi),
        TextCellValue(r.vergiTcNo),
        TextCellValue(belgeNo),
        TextCellValue(r.kategori),
        DoubleCellValue(kdvDouble), // Kusursuz formatlanmış KDV
        DoubleCellValue(toplamDouble), // Kusursuz formatlanmış Toplam Tutar
      ]);
    }

    // Başlıkları Renklendirme ve Tasarım
    for (int col = 0; col < headers.length; col++) {
      final CellIndex cellIndex =
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0);
      final Data cell = sheet.cell(cellIndex);

      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex:
            ExcelColor.fromHexString('#107C41'), // Orijinal Excel Yeşili
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'), // Beyaz Yazı
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Binary Dönüşüm Yapılarak Cihazda .xlsx Dosyası Oluşturulur
    final List<int>? fileBytes = excel.save();
    if (fileBytes == null) return;

    final Directory directory = await getTemporaryDirectory();
    final String filePath = '${directory.path}/Fis_Harcama_Raporu.xlsx';
    final File file = File(filePath);

    await file.writeAsBytes(fileBytes, flush: true);

    // Dosyayı paylaşma/kaydetme penceresini açar
    await Share.shareXFiles(
      [
        XFile(
          filePath,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        )
      ],
      subject: 'Harcama Fişleri Excel Raporu',
    );
  }
}
