import 'models.dart';

/// Prototype's static content, used when the backend isn't reachable so the
/// app demos exactly like lexika-prototype.html instead of crashing.
class Demo {
  Demo._();

  static const ubiquitous = WordEntry(
    headword: 'ubiquitous',
    phonetic: '/juːˈbɪk.wɪ.təs/',
    partOfSpeech: 'adjective',
    definitionEn:
        'Present, appearing, or found everywhere at the same time; widespread.',
    exampleEn:
        '"Smartphones have become ubiquitous in modern classrooms, changing how students take notes."',
    cefrLevel: 'B2',
    isAcademic: true,
    translations: {'ru': 'повсеместный', 'kk': 'бәрі жерде кездесетін'},
    synonyms: ['omnipresent', 'pervasive', 'widespread'],
    antonyms: ['rare', 'scarce'],
  );

  static const ubiquitousRelations = WordRelations(
    synonyms: ['omnipresent', 'pervasive', 'widespread'],
    antonyms: ['rare', 'scarce'],
    wordFamily: [
      WordFamilyItem('ubiquity', 'noun'),
      WordFamilyItem('ubiquitously', 'adv'),
    ],
    nominalization: Nominalization(
      basePos: 'adj',
      baseExample: 'Smartphones are ubiquitous in classrooms now.',
      nounWord: 'ubiquity',
      nounExample: 'The ubiquity of smartphones changed classrooms.',
    ),
  );

  static const recent = ['ephemeral', 'resilient', 'candid', 'arbitrary', 'nuance'];

  static const decks = [
    Deck(id: 1, name: 'Social media unit', cardCount: 28, dueCount: 18),
    Deck(id: 2, name: 'History club vocab', cardCount: 41, dueCount: 22),
    Deck(id: 3, name: 'Gaming talk', cardCount: 19, dueCount: 7),
    Deck(
        id: 4,
        name: 'Starred words',
        cardCount: 53,
        dueCount: 0,
        isSystemDeck: true),
  ];

  static const due = [
    ReviewCard(
        wordId: 0,
        headword: 'candid',
        phonetic: '/ˈkæn.dɪd/',
        translation: 'откровенный',
        exampleEn: 'She gave a candid account of the events.'),
    ReviewCard(
        wordId: 0,
        headword: 'ephemeral',
        phonetic: '/ɪˈfem.ər.əl/',
        translation: 'мимолётный',
        exampleEn: 'Fame can be ephemeral.'),
    ReviewCard(
        wordId: 0,
        headword: 'resilient',
        phonetic: '/rɪˈzɪl.i.ənt/',
        translation: 'устойчивый',
        exampleEn: 'A resilient community recovers quickly.'),
  ];

  static const weakWords = [
    WordTip(
        wordId: 0,
        headword: 'arbitrary',
        definitionEn: 'based on random choice rather than reason',
        translation: 'произвольный',
        cefrLevel: 'B2',
        accuracy: 0.33),
    WordTip(
        wordId: 0,
        headword: 'nuance',
        definitionEn: 'a subtle difference in meaning',
        translation: 'нюанс',
        cefrLevel: 'C1',
        accuracy: 0.5),
  ];

  static const suggestedWords = [
    WordTip(
        wordId: 0,
        headword: 'coherent',
        definitionEn: 'logical and consistent',
        translation: 'связный',
        cefrLevel: 'B2',
        isAcademic: true),
    WordTip(
        wordId: 0,
        headword: 'inevitable',
        definitionEn: 'certain to happen; unavoidable',
        translation: 'неизбежный',
        cefrLevel: 'B2'),
  ];
}
