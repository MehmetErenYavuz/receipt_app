import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/scanner_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Kamera iznini baştan güvenceye alıyoruz
  await Permission.camera.request();

  runApp(const ReceiptApp());
}

class ReceiptApp extends StatelessWidget {
  const ReceiptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeyStudios Fiş Okuyucu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const ScannerScreen(), // Doğrudan tarayıcı ekranına gidiyoruz
    );
  }
}
