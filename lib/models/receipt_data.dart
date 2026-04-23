class ReceiptData {
  String firmaAdi;
  String vergiTcNo;
  String tarih;
  String saat; // YENİ EKLENDİ
  String toplamKdv; // YENİ EKLENDİ
  String toplamTutar;
  String kategori;

  ReceiptData({
    this.firmaAdi = "",
    this.vergiTcNo = "",
    this.tarih = "",
    this.saat = "",
    this.toplamKdv = "",
    this.toplamTutar = "",
    this.kategori = "Diğer",
  });
}
