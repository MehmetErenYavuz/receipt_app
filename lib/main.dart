import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/main_layout.dart'; // ── YENİ: Artık doğrudan tarayıcıya değil, ana iskelete gidiyoruz ──

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Kamera iznini uygulamanın en başında bir kez güvenceye alıyoruz
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
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.blueAccent,
        scaffoldBackgroundColor: const Color(
          0xFF121212,
        ), // Premium Dark arka plan
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A1A),
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1A1A1A),
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.white38,
        ),
      ),
      home:
          const MainLayout(), // Uygulama artık 3 sekmeli ana ekranımızdan başlayacak
    );
  }
}
