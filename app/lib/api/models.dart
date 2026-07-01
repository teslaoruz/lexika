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
  /// Set when the search was auto-corrected: the original (misspelled) query, so
  /// the UI can show "Showing results for X — you searched Y". Null otherwise.
  final String? correctedFrom;

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
    this.correctedFrom,
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
        correctedFrom: j['corrected_from'] as String?,
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
  /// True when this is a class deck shared by a teacher — read-only for students.
  final bool isShared;
  /// Teacher's name for a shared deck ("from Ms Lee"); null for own decks.
  final String? sharedBy;
  /// Name of the class this deck was shared from; null for own/system decks.
  final String? sharedClass;

  const Deck({
    required this.id,
    required this.name,
    required this.cardCount,
    required this.dueCount,
    this.isSystemDeck = false,
    this.isShared = false,
    this.sharedBy,
    this.sharedClass,
  });

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
        id: (j['id'] ?? 0) as int,
        name: (j['name'] ?? '') as String,
        cardCount: (j['card_count'] ?? 0) as int,
        dueCount: (j['due_count'] ?? 0) as int,
        isSystemDeck: (j['is_system_deck'] ?? false) as bool,
        isShared: (j['is_shared'] ?? false) as bool,
        sharedBy: j['shared_by'] as String?,
        sharedClass: j['shared_class'] as String?,
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

/// One row in the Progress screen's weak-words / suggested-words lists. Both
/// endpoints share this shape; the optional fields are what differs (accuracy
/// for weak words, isAcademic for suggestions). ponytail: one model, two lists.
class WordTip {
  final int wordId;
  final String headword;
  final String? definitionEn;
  final String? translation;
  final String? cefrLevel;
  final double? accuracy; // weak words only
  final bool isAcademic; // suggestions only

  const WordTip({
    required this.wordId,
    required this.headword,
    this.definitionEn,
    this.translation,
    this.cefrLevel,
    this.accuracy,
    this.isAcademic = false,
  });

  factory WordTip.fromJson(Map<String, dynamic> j) => WordTip(
        wordId: (j['word_id'] ?? 0) as int,
        headword: (j['headword'] ?? '') as String,
        definitionEn: j['definition_en'] as String?,
        translation: j['translation'] as String?,
        cefrLevel: j['cefr_level'] as String?,
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        isAcademic: (j['is_academic'] ?? false) as bool,
      );
}

/// Phase 7: a class group and one leaderboard row.
class Cohort {
  final int id;
  final String name;
  final String joinCode;
  final int memberCount;
  final bool isTeacher; // current user created this class → can see the dashboard

  const Cohort({
    required this.id,
    required this.name,
    required this.joinCode,
    this.memberCount = 0,
    this.isTeacher = false,
  });

  factory Cohort.fromJson(Map<String, dynamic> j) => Cohort(
        id: (j['id'] ?? 0) as int,
        name: (j['name'] ?? '') as String,
        joinCode: (j['join_code'] ?? '') as String,
        memberCount: (j['member_count'] ?? 0) as int,
        isTeacher: (j['is_teacher'] ?? false) as bool,
      );
}

/// Full info about one class (GET /cohorts/{id}) — the "tap a class" detail view.
class CohortDetail {
  final int id;
  final String name;
  final String joinCode;
  final int memberCount;
  final bool isTeacher;
  final String? teacherName;
  final List<ClassMember> members;
  final List<ClassDeck> decks; // decks shared to this class

  const CohortDetail({
    required this.id,
    required this.name,
    required this.joinCode,
    this.memberCount = 0,
    this.isTeacher = false,
    this.teacherName,
    this.members = const [],
    this.decks = const [],
  });

  factory CohortDetail.fromJson(Map<String, dynamic> j) => CohortDetail(
        id: (j['id'] ?? 0) as int,
        name: (j['name'] ?? '') as String,
        joinCode: (j['join_code'] ?? '') as String,
        memberCount: (j['member_count'] ?? 0) as int,
        isTeacher: (j['is_teacher'] ?? false) as bool,
        teacherName: j['teacher_name'] as String?,
        members: ((j['members'] as List?) ?? [])
            .map((e) => ClassMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        decks: ((j['decks'] as List?) ?? [])
            .map((e) => ClassDeck.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ClassMember {
  final int userId;
  final String displayName;
  final bool isTeacher;
  const ClassMember(
      {required this.userId, required this.displayName, this.isTeacher = false});

  factory ClassMember.fromJson(Map<String, dynamic> j) => ClassMember(
        userId: (j['user_id'] ?? 0) as int,
        displayName: (j['display_name'] ?? '') as String,
        isTeacher: (j['is_teacher'] ?? false) as bool,
      );
}

class ClassDeck {
  final int id;
  final String name;
  final int cardCount;
  const ClassDeck(
      {required this.id, required this.name, this.cardCount = 0});

  factory ClassDeck.fromJson(Map<String, dynamic> j) => ClassDeck(
        id: (j['id'] ?? 0) as int,
        name: (j['name'] ?? '') as String,
        cardCount: (j['card_count'] ?? 0) as int,
      );
}

/// One row in the admin dashboard (GET /admin/users).
class AdminUser {
  final int id;
  final String? email;
  final String? displayName;
  final String? authProvider;
  final bool isAdmin;
  final int totalXp;
  final int currentStreak;
  final int wordsLearned;
  final int reviewsRecent;
  final String? lastActive;
  final String? createdAt;
  final List<String> classes;

  const AdminUser({
    required this.id,
    this.email,
    this.displayName,
    this.authProvider,
    this.isAdmin = false,
    this.totalXp = 0,
    this.currentStreak = 0,
    this.wordsLearned = 0,
    this.reviewsRecent = 0,
    this.lastActive,
    this.createdAt,
    this.classes = const [],
  });

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: (j['id'] ?? 0) as int,
        email: j['email'] as String?,
        displayName: j['display_name'] as String?,
        authProvider: j['auth_provider'] as String?,
        isAdmin: (j['is_admin'] ?? false) as bool,
        totalXp: (j['total_xp'] ?? 0) as int,
        currentStreak: (j['current_streak'] ?? 0) as int,
        wordsLearned: (j['words_learned'] ?? 0) as int,
        reviewsRecent: (j['reviews_recent'] ?? 0) as int,
        lastActive: j['last_active'] as String?,
        createdAt: j['created_at'] as String?,
        classes: _strList(j['classes']),
      );
}

/// One student row in the teacher dashboard.
class StudentProgress {
  final int userId;
  final String displayName;
  final bool isTeacher;
  final int totalXp;
  final int currentStreak;
  final int wordsLearned;
  final int weeklyXp;
  final String? lastActive; // ISO date, null if never active

  const StudentProgress({
    required this.userId,
    required this.displayName,
    this.isTeacher = false,
    this.totalXp = 0,
    this.currentStreak = 0,
    this.wordsLearned = 0,
    this.weeklyXp = 0,
    this.lastActive,
  });

  factory StudentProgress.fromJson(Map<String, dynamic> j) => StudentProgress(
        userId: (j['user_id'] ?? 0) as int,
        displayName: (j['display_name'] ?? '') as String,
        isTeacher: (j['is_teacher'] ?? false) as bool,
        totalXp: (j['total_xp'] ?? 0) as int,
        currentStreak: (j['current_streak'] ?? 0) as int,
        wordsLearned: (j['words_learned'] ?? 0) as int,
        weeklyXp: (j['weekly_xp'] ?? 0) as int,
        lastActive: j['last_active'] as String?,
      );
}

class LeaderboardEntry {
  final int rank;
  final String displayName;
  final int weeklyXp;
  final bool isMe;

  const LeaderboardEntry({
    required this.rank,
    required this.displayName,
    required this.weeklyXp,
    this.isMe = false,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        rank: (j['rank'] ?? 0) as int,
        displayName: (j['display_name'] ?? '') as String,
        weeklyXp: (j['weekly_xp'] ?? 0) as int,
        isMe: (j['is_me'] ?? false) as bool,
      );
}

/// One CEFR bar in the accuracy-by-level chart. accuracy == null means no
/// attempts at that level yet (rendered as an empty bar).
class LevelAccuracy {
  final String level;
  final double? accuracy;
  final int attempts;

  const LevelAccuracy({required this.level, this.accuracy, this.attempts = 0});

  factory LevelAccuracy.fromJson(Map<String, dynamic> j) => LevelAccuracy(
        level: (j['level'] ?? '') as String,
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        attempts: (j['attempts'] ?? 0) as int,
      );
}

/// A word saved in a deck (deck-detail row).
class DeckWord {
  final int wordId;
  final String headword;
  final String? definitionEn;
  final String? cefrLevel;

  const DeckWord({
    required this.wordId,
    required this.headword,
    this.definitionEn,
    this.cefrLevel,
  });

  factory DeckWord.fromJson(Map<String, dynamic> j) => DeckWord(
        wordId: (j['word_id'] ?? 0) as int,
        headword: (j['headword'] ?? '') as String,
        definitionEn: j['definition_en'] as String?,
        cefrLevel: j['cefr_level'] as String?,
      );
}

List<String> _strList(dynamic v) =>
    (v as List?)?.map((e) => e.toString()).toList() ?? const [];

Map<String, String> _strMap(dynamic v) =>
    (v as Map?)?.map((k, val) => MapEntry(k.toString(), val.toString())) ??
    const {};
