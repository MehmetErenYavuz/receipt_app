import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/receipt_data.dart';
import '../models/kdv_item.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'mey_receipts.db');

    // ── VERSİYON 2'YE YÜKSELTİLDİ ──
    return await openDatabase(
      path,
      version: 2, // Versiyonu 2 yaptık
      onCreate: _onCreate,
      onUpgrade: _onUpgrade, // Veritabanı güncelleme mantığı eklendi
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE receipts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        isApproved INTEGER DEFAULT 0,
        firmaAdi TEXT,
        firmaAdresi TEXT,
        vergiDairesi TEXT,
        vergiTcNo TEXT,
        belgeTuru TEXT,
        fisNo TEXT,
        seriNo TEXT,
        zNo TEXT,
        tarih TEXT,
        saat TEXT,
        kdvDetayJson TEXT,
        toplamKdv TEXT,
        kdvHaricToplam TEXT,
        toplamTutar TEXT,
        odemeYontemi TEXT,
        paraUstu TEXT,
        kategori TEXT,
        imagePath TEXT,
        uyari TEXT,
        confidenceScoresJson TEXT -- Doğruluk oranları için eklendi
      )
    ''');
  }

  // ── MIGRATION: UYGULAMAYI SİLMEDEN TABLOYU GÜNCELLEME METODU ──
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Eski versiyondan gelenler için tabloya eksik sütunlar ekleniyor
      try {
        await db.execute(
          'ALTER TABLE receipts ADD COLUMN isApproved INTEGER DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE receipts ADD COLUMN confidenceScoresJson TEXT',
        );
      } catch (_) {}
    }
  }

  Future<int> insertReceipt(ReceiptData data) async {
    Database db = await database;

    List<Map<String, dynamic>> kdvList = data.kdvDetay
        .map(
          (item) => {
            'oran': item.oran,
            'matrah': item.matrah,
            'tutar': item.tutar,
          },
        )
        .toList();

    // Veritabanına kaydetmek için hazırlanan map
    Map<String, dynamic> rowData = {
      'isApproved': data.isApproved ? 1 : 0,
      'firmaAdi': data.firmaAdi,
      'firmaAdresi': data.firmaAdresi,
      'vergiDairesi': data.vergiDairesi,
      'vergiTcNo': data.vergiTcNo,
      'belgeTuru': data.belgeTuru,
      'fisNo': data.fisNo,
      'seriNo': data.seriNo,
      'zNo': data.zNo,
      'tarih': data.tarih,
      'saat': data.saat,
      'kdvDetayJson': jsonEncode(kdvList),
      'toplamKdv': data.toplamKdv,
      'kdvHaricToplam': data.kdvHaricToplam,
      'toplamTutar': data.toplamTutar,
      'odemeYontemi': data.odemeYontemi,
      'paraUstu': data.paraUstu,
      'kategori': data.kategori,
      'imagePath': data.imagePath,
      'uyari': data.uyari ?? '',
      'confidenceScoresJson': jsonEncode(
        data.confidenceScores,
      ), // Doğruluk oranları DB'ye eklendi
    };

    // Eğer id varsa (Yani var olan bir fiş güncelleniyorsa) map'e id'yi de ekle.
    // Böylece 'replace' algoritması eski veriyi günceller.
    if (data.id != null) {
      rowData['id'] = data.id;
    }

    return await db.insert(
      'receipts',
      rowData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ReceiptData>> getAllReceipts() async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'receipts',
      orderBy: 'id DESC',
    );

    return List.generate(maps.length, (i) => _mapToReceipt(maps[i]));
  }

  // ═══════════════════════════════════════════════════════════════════
  // YENİ: TEK FİŞİ ID İLE GETİR (Detay/Yenileme amaçlı)
  // ═══════════════════════════════════════════════════════════════════
  Future<ReceiptData?> getReceiptById(int id) async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'receipts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return _mapToReceipt(maps[0]);
  }

  // ═══════════════════════════════════════════════════════════════════
  // YENİ: FİŞ SİLME (id ile)
  // Fişe ait fotoğraf da diskten silinir.
  // ═══════════════════════════════════════════════════════════════════
  Future<int> deleteReceipt(int id) async {
    Database db = await database;

    // Önce fotoğraf yolunu öğren ve diskten sil
    final result = await db.query(
      'receipts',
      columns: ['imagePath'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isNotEmpty) {
      final path = result[0]['imagePath'] as String?;
      if (path != null && path.isNotEmpty) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          // Silme başarısız olsa bile DB silme işlemi devam etsin
        }
      }
    }

    return await db.delete('receipts', where: 'id = ?', whereArgs: [id]);
  }

  // ═══════════════════════════════════════════════════════════════════
  // YENİ: TÜM FİŞLERİ SİL (ileride çoklu seçim için)
  // ═══════════════════════════════════════════════════════════════════
  Future<int> deleteAllReceipts() async {
    Database db = await database;

    // Önce tüm fotoğrafları diskten sil
    final allRows = await db.query('receipts', columns: ['imagePath']);
    for (final row in allRows) {
      final path = row['imagePath'] as String?;
      if (path != null && path.isNotEmpty) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }

    return await db.delete('receipts');
  }

  // ═══════════════════════════════════════════════════════════════════
  // PRIVATE: Database satırını ReceiptData modeline çevirir
  // ═══════════════════════════════════════════════════════════════════
  ReceiptData _mapToReceipt(Map<String, dynamic> map) {
    // ── 1. KDV JSON PARSE ──
    List<KdvItem> parsedKdv = [];
    if (map['kdvDetayJson'] != null &&
        map['kdvDetayJson'].toString().isNotEmpty) {
      List<dynamic> decoded = jsonDecode(map['kdvDetayJson']);
      parsedKdv = decoded
          .map(
            (e) => KdvItem(
              oran: e['oran'],
              matrah: e['matrah'],
              tutar: e['tutar'],
            ),
          )
          .toList();
    }

    // ── 2. DOĞRULUK ORANLARI JSON PARSE ──
    Map<String, double> parsedScores = {};
    if (map['confidenceScoresJson'] != null &&
        map['confidenceScoresJson'].toString().isNotEmpty) {
      try {
        Map<String, dynamic> decodedScores = jsonDecode(
          map['confidenceScoresJson'],
        );
        parsedScores = decodedScores.map(
          (key, value) => MapEntry(key, (value as num).toDouble()),
        );
      } catch (e) {
        // JSON parse hatası olursa boş map ile devam et
      }
    }

    return ReceiptData(
      id: map['id'],
      isApproved: map['isApproved'] == 1,
      firmaAdi: map['firmaAdi'] ?? '',
      firmaAdresi: map['firmaAdresi'] ?? '',
      vergiDairesi: map['vergiDairesi'] ?? '',
      vergiTcNo: map['vergiTcNo'] ?? '',
      belgeTuru: map['belgeTuru'] ?? '',
      fisNo: map['fisNo'] ?? '',
      seriNo: map['seriNo'] ?? '',
      zNo: map['zNo'] ?? '',
      tarih: map['tarih'] ?? '',
      saat: map['saat'] ?? '',
      kdvDetay: parsedKdv,
      toplamKdv: map['toplamKdv'] ?? '',
      kdvHaricToplam: map['kdvHaricToplam'] ?? '',
      toplamTutar: map['toplamTutar'] ?? '',
      odemeYontemi: map['odemeYontemi'] ?? '',
      paraUstu: map['paraUstu'] ?? '',
      kategori: map['kategori'] ?? 'Diğer',
      imagePath: map['imagePath'],
      uyari: map['uyari'] == '' ? null : map['uyari'],
      confidenceScores: parsedScores, // Kaydedilen oranlar modele aktarılıyor
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ÖZET SEKMESİ İÇİN EKLENTİ (Değiştirilmedi, olduğu gibi korundu)
// ═══════════════════════════════════════════════════════════════════════
extension KategoriToplamlariExtension on DatabaseHelper {
  /// Kategori bazında toplam harcamayı getirir.
  Future<Map<String, double>> getKategoriToplamlari() async {
    final db = await database;
    // Eğer kategori alanı dolu değilse, en azından Diğer diyerek gruplanır.
    final result = await db.rawQuery('''
      SELECT 
        COALESCE(NULLIF(kategori, ''), 'Diğer') as kategori, 
        SUM(CASE 
            WHEN toplamTutar IS NOT NULL AND toplamTutar != '' 
                  AND CAST(toplamTutar AS FLOAT) > 0
              THEN CAST(toplamTutar AS FLOAT)
            WHEN toplamTutar IS NOT NULL AND toplamTutar != ''
              THEN REPLACE(toplamTutar, ',', '.') -- Noktalı parse
            ELSE 0
        END
        ) as toplam
      FROM receipts
      GROUP BY kategori
      ''');

    final Map<String, double> kategoriToplamlar = {};
    for (var row in result) {
      var key = row['kategori']?.toString() ?? 'Diğer';
      var rawVal = row['toplam'];
      double val;
      if (rawVal is int) {
        val = rawVal.toDouble();
      } else if (rawVal is double) {
        val = rawVal;
      } else {
        val =
            double.tryParse((rawVal ?? '0').toString().replaceAll(',', '.')) ??
            0;
      }
      kategoriToplamlar[key] = val;
    }
    return kategoriToplamlar;
  }
}
