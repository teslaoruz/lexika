// Plain data models mirroring CONTRACT.md responses. ponytail: hand-written
// fromJson, no codegen — the shapes are small and stable.

class WordEntry {
  final int? id;
  final String headword;
  final String? phonetic;
  final String? audioUrl;
  final String? partOfSpeech;
  final String? definitionEn;
  final String? exampleEn;
  final String? cefrLevel;
  final bool isAcademic;
  final String? translationRu;
  final String? translationKk;
  final List<String> synonyms;
  final List<String> antonyms;

  const WordEntry({
    this.id,
    required this.headword,
    this.phonetic,
    this.audioUrl,
    this.partOfSpeech,
    this.definitionEn,
    this.exampleEn,
    this.cefrLevel,
    this.isAcademic = false,
    this.translationRu,
    this.translationKk,
    this.synonyms = const [],
    this.antonyms = const [],
  });

  factory WordEntry.fromJson(Map<String, dynamic> j) => WordEntry(
        id: j['id'] as int?,
        headword: (j['headword'] ?? '') as String,
        phonetic: j['phonetic'] as String?,
        audioUrl: j['audio_url'] as String?,
        partOfSpeech: j['part_of_speech'] as String?,
        definitionEn: j['definition_en'] as String?,
        exampleEn: j['example_en'] as String?,
        cefrLevel: j['cefr_level'] as String?,
        isAcademic: (j['is_academic'] ?? false) as bool,
        translationRu: j['translation_ru'] as String?,
        translationKk: j['translation_kk'] as String?,
        synonyms: _strList(j['synonyms']),
        antonyms: _strList(j['antonyms']),
      );
}

class WordFamilyItem {
  final String word;
  final String pos;
  const WordFamilyItem(this.word, this.pos);

  factory WordFamilyItem.fromJson(Map<String, dynamic> j) =>
      WordFamilyItem((j['word'] ?? '') as String, (j['pos'] ?? '') as String);
}

class Nominalization {
  final String basePos;
  final String baseExample;
  final String nounWord;
  final String nounExample;
  const Nominalization({
    required this.basePos,
    required this.baseExample,
    required this.nounWord,
    required this.nounExample,
  });

  factory Nominalization.fromJson(Map<String, dynamic> j) => Nominalization(
        basePos: (j['base_pos'] ?? 'adj') as String,
        baseExample: (j['base_example'] ?? '') as String,
        nounWord: (j['noun_word'] ?? '') as String,
        nounExample: (j['noun_example'] ?? '') as String,
      );
}

class WordRelations {
  final List<String> synonyms;
  final List<String> antonyms;
  final List<WordFamilyItem> wordFamily;
  final Nominalization? nominalization;

  const WordRelations({
    this.synonyms = const [],
    this.antonyms = const [],
    this.wordFamily = const [],
    this.nominalization,
  });

  factory WordRelations.fromJson(Map<String, dynamic> j) => WordRelations(
        synonyms: _strList(j['synonyms']),
        antonyms: _strList(j['antonyms']),
        wordFamily: ((j['word_family'] as List?) ?? [])
            .map((e) => WordFamilyItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        nominalization: j['nominalization'] == null
            ? null
            : Nominalization.fromJson(
                j['nominalization'] as Map<String, dynamic>),
      );
}

class Deck {
  final int id;
  final String name;
  final int cardCount;
  final int dueCount;
  final bool isSystemDeck;

  const Deck({
    required this.id,
    required this.name,
    required this.cardCount,
    required this.dueCount,
    this.isSystemDeck = false,
  });

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
        id: (j['id'] ?? 0) as int,
        name: (j['name'] ?? '') as String,
        cardCount: (j['card_count'] ?? 0) as int,
        dueCount: (j['due_count'] ?? 0) as int,
        isSystemDeck: (j['is_system_deck'] ?? false) as bool,
      );
}

class ReviewCard {
  final int wordId;
  final String headword;
  final String? phonetic;
  final String? audioUrl;
  final String? translation;
  final String? definitionEn;
  final String? exampleEn;

  const ReviewCard({
    required this.wordId,
    required this.headword,
    this.phonetic,
    this.audioUrl,
    this.translation,
    this.definitionEn,
    this.exampleEn,
  });

  factory ReviewCard.fromJson(Map<String, dynamic> j) => ReviewCard(
        wordId: (j['word_id'] ?? 0) as int,
        headword: (j['headword'] ?? '') as String,
        phonetic: j['phonetic'] as String?,
        audioUrl: j['audio_url'] as String?,
        translation: j['translation'] as String?,
        definitionEn: j['definition_en'] as String?,
        exampleEn: j['example_en'] as String?,
      );
}

List<String> _strList(dynamic v) =>
    (v as List?)?.map((e) => e.toString()).toList() ?? const [];
