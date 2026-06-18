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
  /// Extra (not the focus): {lang_code: text}. Empty when none available.
  final Map<String, String> translations;
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
    this.translations = const {},
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
        translations: _strMap(j['translations']),
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

class UserStats {
  final int currentStreak;
  final int longestStreak;
  final int totalXp;
  final int totalWordsLearned;

  const UserStats({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.totalXp = 0,
    this.totalWordsLearned = 0,
  });

  factory UserStats.fromJson(Map<String, dynamic> j) => UserStats(
        currentStreak: (j['current_streak'] ?? 0) as int,
        longestStreak: (j['longest_streak'] ?? 0) as int,
        totalXp: (j['total_xp'] ?? 0) as int,
        totalWordsLearned: (j['total_words_learned'] ?? 0) as int,
      );
}

List<String> _strList(dynamic v) =>
    (v as List?)?.map((e) => e.toString()).toList() ?? const [];

Map<String, String> _strMap(dynamic v) =>
    (v as Map?)?.map((k, val) => MapEntry(k.toString(), val.toString())) ??
    const {};
