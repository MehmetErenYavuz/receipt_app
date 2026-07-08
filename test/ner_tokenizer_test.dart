// ═══════════════════════════════════════════════════════════════════════
// TOKENIZER PARİTE TESTİ — input_contract.md §5 golden vektörü
// ═══════════════════════════════════════════════════════════════════════
// Gerçek gold fişi (img_9ddd905bcc28) kelimeleri tokenize edilir ve
// dokümandaki input_ids[:25] + word_ids[:25] BİREBİR assert edilir.
// Bu test geçerse WordPiece + cased + özel token + kelime hizalaması doğrudur.
//
// Çalıştır: flutter test test/ner_tokenizer_test.dart
// ═══════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_app/ml/ner_tokenizer.dart';

void main() {
  late BertWordPieceTokenizer tok;

  setUpAll(() {
    final vocab = File('assets/models/vocab.txt');
    expect(vocab.existsSync(), isTrue,
        reason: 'assets/models/vocab.txt bulunamadı.');
    tok = BertWordPieceTokenizer.fromVocabString(vocab.readAsStringSync());
  });

  test('özel token id\'leri ve standartlar doğru', () {
    expect(tok.clsId, 2);
    expect(tok.sepId, 3);
    expect(tok.padId, 0);
    expect(tok.unkId, 1);
    expect(tok.specialTokens['[TYPE=FIS]'], 32000);
    expect(tok.specialTokens['[TYPE=EARSIV]'], 32001);
  });

  test('input_contract §5 golden: input_ids[:25] ve word_ids[:25]', () {
    // Prefix dahil ilk 12 kelime — ilk 25 subword tam bunlardan oluşur.
    final words = <String>[
      '[TYPE=FIS]', // 0
      'AAKUSfu', // 1
      'Kor', // 2
      'Ge', // 3
      'EFETI', // 4
      'KARAL', // 5
      'ut', // 6
      'TUZLUAYER', // 7
      'M', // 8
      '8', // 9
      'CD', // 10
      'piKiMEVvi', // 11
    ];

    final goldenIds = <int>[
      2, 32000, 9846, 1083, 9304, 1066, 1030, 3929, 6466, 20137, 3473, 1042,
      8788, 3538, 31018, 28621, 1163, 7777, 4331, 2864, 49, 28, 11798, 11551,
      1083,
    ];
    final goldenWordIds = <int?>[
      null, 0, 1, 1, 1, 1, 1, 2, 3, 4, 4, 4, 5, 5, 6, 7, 7, 7, 7, 7, 8, 9, 10,
      11, 11,
    ];

    final enc = tok.encode(words, maxLength: 512);

    expect(enc.inputIds.length, greaterThanOrEqualTo(25));
    expect(enc.inputIds.sublist(0, 25), goldenIds,
        reason: 'input_ids[:25] dokümanla eşleşmiyor (WordPiece paritesi).');
    expect(enc.wordIds.sublist(0, 25), goldenWordIds,
        reason: 'word_ids[:25] dokümanla eşleşmiyor (kelime hizalaması).');
    // attention_mask hepsi 1 (tek belge, pad yok).
    expect(enc.attentionMask.every((m) => m == 1), isTrue);
  });

  test('truncation: 512 üstü içerik sağdan kesilir + truncated bayrağı', () {
    // 700 uzun kelime → kesin > 512 subword (Faz 7 sınırı).
    final words = <String>['[TYPE=FIS]', for (int i = 0; i < 700; i++) 'KALEM'];
    final enc = tok.encode(words, maxLength: 512);
    expect(enc.inputIds.length, 512);
    expect(enc.inputIds.first, 2); // [CLS]
    expect(enc.inputIds.last, 3); // [SEP] korunur
    expect(enc.truncated, isTrue);
  });

  test('512 altı belge truncate OLMAZ (truncated=false)', () {
    final words = <String>['[TYPE=FIS]', for (int i = 0; i < 100; i++) 'KALEM'];
    final enc = tok.encode(words, maxLength: 512);
    expect(enc.truncated, isFalse);
  });

  test('noktalama ayrımı: tek kelime içi "." ve "/" parçalanır', () {
    // Aynı kelime indeksinde kalmalı (is_split_into_words), ama >1 subword.
    final enc = tok.encode(['[TYPE=FIS]', '08/112025'], maxLength: 512);
    // word 1'in subword'leri: '/' ayrımı nedeniyle >1 olmalı.
    final w1 = enc.wordIds.where((w) => w == 1).length;
    expect(w1, greaterThan(1));
  });
}
