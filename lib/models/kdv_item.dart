class KdvItem {
  final String oran; // "%10", "%20" vb.
  final String matrah; // KDV hariç tutar
  final String tutar; // KDV tutarı

  const KdvItem({
    required this.oran,
    required this.matrah,
    required this.tutar,
  });

  @override
  String toString() => '%$oran → $tutar TL';
}
