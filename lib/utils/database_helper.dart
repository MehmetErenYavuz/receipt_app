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

    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE receipts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
        uyari TEXT
      )
    ''');
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

    return await db.insert('receipts', {
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
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ReceiptData>> getAllReceipts() async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'receipts',
      orderBy: 'id DESC',
    );

    return List.generate(maps.length, (i) {
      List<KdvItem> parsedKdv = [];
      if (maps[i]['kdvDetayJson'] != null &&
          maps[i]['kdvDetayJson'].toString().isNotEmpty) {
        List<dynamic> decoded = jsonDecode(maps[i]['kdvDetayJson']);
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

      return ReceiptData(
        firmaAdi: maps[i]['firmaAdi'] ?? '',
        firmaAdresi: maps[i]['firmaAdresi'] ?? '',
        vergiDairesi: maps[i]['vergiDairesi'] ?? '',
        vergiTcNo: maps[i]['vergiTcNo'] ?? '',
        belgeTuru: maps[i]['belgeTuru'] ?? '',
        fisNo: maps[i]['fisNo'] ?? '',
        seriNo: maps[i]['seriNo'] ?? '',
        zNo: maps[i]['zNo'] ?? '',
        tarih: maps[i]['tarih'] ?? '',
        saat: maps[i]['saat'] ?? '',
        kdvDetay: parsedKdv,
        toplamKdv: maps[i]['toplamKdv'] ?? '',
        kdvHaricToplam: maps[i]['kdvHaricToplam'] ?? '',
        toplamTutar: maps[i]['toplamTutar'] ?? '',
        odemeYontemi: maps[i]['odemeYontemi'] ?? '',
        paraUstu: maps[i]['paraUstu'] ?? '',
        kategori: maps[i]['kategori'] ?? 'Diğer',
        imagePath: maps[i]['imagePath'],
        uyari: maps[i]['uyari'] == '' ? null : maps[i]['uyari'],
      );
    });
  }
}
