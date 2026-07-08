# ═══════════════════════════════════════════════════════════════════════
# R8 / ProGuard keep & dontwarn kuralları (release build)
# ═══════════════════════════════════════════════════════════════════════

# ── ML Kit Text Recognition ──────────────────────────────────────────────
# Plugin (google_mlkit_text_recognition) yalnız Latin script kullanılsa bile
# Çince/Japonca/Korece/Devanagari tanıyıcı sınıflarına referans veriyor; bu
# script paketleri bağımlılıkta yok → R8 "missing class" hatası verir.
# Latin tanıyıcıyı koru, opsiyonel script tanıyıcıların uyarılarını sustur.
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# ── ONNX Runtime (onnxruntime_flutter) ───────────────────────────────────
# FFI tabanlı; Java/JNI sınıfları stripping ile bozulmasın (savunmacı).
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
