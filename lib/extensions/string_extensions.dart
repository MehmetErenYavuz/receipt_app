// lib/extensions/string_extensions.dart

extension OcrStringExtension on String {
  // Fonksiyonu 'getter' olarak tanımlıyoruz
  String get fixOcrConfusion {
    String result = this; // 'this' burada o anki metni temsil eder

    // Küçük harf 0 düzeltmesi
    result = result.replaceAllMapped(
      RegExp(r'([a-zğüşıöç])0([a-zğüşıöç])'),
      (Match m) => '${m[1]}o${m[2]}',
    );

    // Büyük harf 0 düzeltmesi
    result = result.replaceAllMapped(
      RegExp(r'([A-ZĞÜŞİÖÇ])0([A-ZĞÜŞİÖÇ])'),
      (Match m) => '${m[1]}O${m[2]}',
    );

    result = result.replaceAll('T0PLAM', 'TOPLAM');
    result = result.replaceAll('T9PLAM', 'TOPLAM');

    return result;
  }
}
