import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/bounce_press.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/play_button.dart';
import '../../widgets/sfx.dart';

/// Phase 4 game suite (build-plan 5.3). All games pull the same due cards
/// (SM-2 picks *what*, the game picks *how*) and report each answer back through
/// /review/submit, so XP + SM-2 + streak all update with no game-specific
/// backend. ponytail: 4 games, 3 mechanics — listening is the choice game with
/// an audio prompt instead of a text one.
enum GameType { matching, listening, typing, quiz }

extension GameMeta on GameType {
  String get title => switch (this) {
        GameType.matching => 'Matching',
        GameType.listening => 'Listening',
        GameType.typing => 'Typing race',
        GameType.quiz => 'Quiz',
      };
  String get emoji => switch (this) {
        GameType.matching => '🔗',
        GameType.listening => '🎧',
        GameType.typing => '⌨️',
        GameType.quiz => '✅',
      };
  String get tag => name; // matches backend GAME_TYPES
  Color get color => switch (this) {
        GameType.matching => AppColors.violet,
        GameType.listening => AppColors.sky,
        GameType.typing => AppColors.coral,
        GameType.quiz => AppColors.mint,
      };
}

/// 2×2 grid of game tiles, dropped into the Decks screen.
class GamesSection extends StatelessWidget {
  const GamesSection({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile(GameType t) => Expanded(
          child: BouncePress(
            onTap: () => _open(context, t),
            pressedScale: 0.95,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
              decoration: BoxDecoration(
                color: t.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Text(t.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(t.title,
                        style: AppTheme.baloo(
                            size: 13.5,
                            weight: FontWeight.w700,
                            color: t.color)),
                  ),
                ],
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Play a game',
            style: AppTheme.baloo(size: 19, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(children: [tile(GameType.matching), const SizedBox(width: 10), tile(GameType.listening)]),
        const SizedBox(height: 10),
        Row(children: [tile(GameType.typing), const SizedBox(width: 10), tile(GameType.quiz)]),
      ],
    );
  }

  Future<void> _open(BuildContext context, GameType t) async {
    // Pick what to practise first.
    final source =
        await showModalBottomSheet<FutureProvider<List<ReviewCard>>>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _GameSourceSheet(),
    );
    if (source == null || !context.mounted) return;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, a, _) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: kEaseSmooth)),
          child: GameScreen(type: t, cards: source),
        ),
      ),
    ));
  }
}

/// Bottom sheet to choose what a game practises: all words, weak words, due
/// words, or a specific deck. Pops the chosen card-source provider.
class _GameSourceSheet extends ConsumerWidget {
  const _GameSourceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);
    Widget tile(String emoji, String label,
            FutureProvider<List<ReviewCard>> source) =>
        BouncePress(
          onTap: () => Navigator.of(context).pop(source),
          pressedScale: 0.98,
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.bgSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: AppTheme.baloo(
                          size: 15,
                          weight: FontWeight.w700,
                          color: AppColors.ink)),
                ),
              ],
            ),
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.inkFaint,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text('Practise…',
                  style: AppTheme.baloo(size: 18, weight: FontWeight.w700)),
            ),
            tile('📚', 'All my words', allCardsProvider),
            tile('💪', 'Weak words', weakReviewProvider),
            tile('⏰', 'Due words', dueCardsProvider),
            for (final d
                in (decks.value ?? <Deck>[]).where((d) => !d.isSystemDeck))
              tile('🗂️', d.name, deckReviewProvider(d.id)),
          ],
        ),
      ),
    );
  }
}

/// Short text shown for a card's meaning. The English definition is the focus;
/// a translation is only a last-resort fallback. Capped so it fits option/match
/// tiles.
String meaningOf(ReviewCard c) {
  final d = c.definitionEn?.trim();
  if (d != null && d.isNotEmpty) return d.length > 80 ? '${d.substring(0, 80)}…' : d;
  final t = c.translation?.trim();
  if (t != null && t.isNotEmpty) return t;
  return c.exampleEn?.trim().isNotEmpty == true ? c.exampleEn!.trim() : c.headword;
}

// ---------------------------------------------------------------- game host
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.type, required this.cards});
  final GameType type;

  /// Which pool the game practises (all words / weak / due / a deck).
  final FutureProvider<List<ReviewCard>> cards;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  int _index = 0; // current question (choice/typing)
  int _correct = 0;
  bool _finished = false;

  Future<void> _submit(ReviewCard card, bool correct) async {
    correct ? Sfx.correct() : Sfx.wrong();
    if (correct) _correct++;
    if (card.wordId != 0) {
      try {
        await ref
            .read(apiClientProvider)
            .submit(card.wordId, correct ? 'good' : 'again', gameType: widget.type.tag);
        ref.invalidate(statsProvider);
      } catch (_) {/* offline demo — ignore */}
    }
  }

  @override
  Widget build(BuildContext context) {
    // The pool is chosen by the source picker (all / weak / due / a deck).
    final due = ref.watch(widget.cards);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [widget.type.color, widget.type.color.withValues(alpha: 0.78)],
          ),
        ),
        child: SafeArea(
          // Shrink above the keyboard so the typing game's field + Check button
          // stay visible when the keyboard opens.
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: due.when(
              loading: () => Center(
                  child: CircularProgressIndicator(color: AppColors.onAccent)),
              error: (_, _) => _message('Could not load words'),
              data: (cards) => _content(cards),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(List<ReviewCard> all) {
    if (all.length < 2) return _message('Add a few words first 🙂');

    if (widget.type == GameType.matching) {
      final pool = all.take(4).toList();
      return Column(children: [
        _chrome(progress: _finished ? 1 : 0),
        Expanded(
          child: _finished
              ? _summary(pool.length)
              : _MatchingBoard(
                  cards: pool,
                  onResult: _submit,
                  onDone: () => setState(() => _finished = true),
                ),
        ),
      ]);
    }

    // Choice / typing: one card per question.
    final pool = all.take(6).toList();
    if (_index >= pool.length) _finished = true;
    return Column(children: [
      _chrome(progress: _finished ? 1 : _index / pool.length),
      Expanded(
        child: _finished
            ? _summary(pool.length)
            : (widget.type == GameType.typing
                ? _TypingQuestion(
                    key: ValueKey(_index),
                    card: pool[_index],
                    onAnswer: _answer,
                  )
                : _ChoiceQuestion(
                    key: ValueKey(_index),
                    card: pool[_index],
                    pool: pool,
                    listening: widget.type == GameType.listening,
                    onAnswer: _answer,
                  )),
      ),
    ]);
  }

  Future<void> _answer(ReviewCard card, bool correct) async {
    await _submit(card, correct);
    await Future.delayed(const Duration(milliseconds: 650));
    if (mounted) setState(() => _index++);
  }

  Widget _summary(int total) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_correct == total ? '🎉' : '👏', style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text('$_correct / $total correct',
              style: AppTheme.baloo(
                  size: 26, weight: FontWeight.w800, color: AppColors.onAccent)),
          const SizedBox(height: 24),
          BouncePress(
            onTap: () => Navigator.of(context).pop(),
            pressedScale: 0.94,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text('Done',
                  style: AppTheme.baloo(
                      size: 15, weight: FontWeight.w700, color: widget.type.color)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String text) => Column(children: [
        _chrome(progress: 0),
        Expanded(
          child: Center(
            child: Text(text,
                textAlign: TextAlign.center,
                style: AppTheme.baloo(
                    size: 19, weight: FontWeight.w700, color: AppColors.onAccent)),
          ),
        ),
      ]);

  Widget _chrome({required double progress}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(children: [
        BouncePress(
          onTap: () => Navigator.of(context).pop(),
          pressedScale: 0.88,
          child: GlassSurface(
            radius: 12,
            tint: AppColors.onAccent,
            opacity: 0.18,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.close_rounded, size: 18, color: AppColors.onAccent),
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.onAccent.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: LayoutBuilder(
                builder: (context, c) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: c.maxWidth * progress.clamp(0, 1),
                  decoration: BoxDecoration(
                    color: AppColors.onAccent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
          ),
        ),
        Text('${widget.type.emoji} ${widget.type.title}',
            style: AppTheme.baloo(
                size: 13, weight: FontWeight.w700, color: AppColors.onAccent)),
      ]),
    );
  }
}

// ------------------------------------------------------- choice / listening
class _ChoiceQuestion extends StatefulWidget {
  const _ChoiceQuestion({
    super.key,
    required this.card,
    required this.pool,
    required this.listening,
    required this.onAnswer,
  });
  final ReviewCard card;
  final List<ReviewCard> pool;
  final bool listening;
  final void Function(ReviewCard, bool) onAnswer;

  @override
  State<_ChoiceQuestion> createState() => _ChoiceQuestionState();
}

class _ChoiceQuestionState extends State<_ChoiceQuestion> {
  late final List<ReviewCard> _options;
  String? _picked;

  @override
  void initState() {
    super.initState();
    // Right answer + up to 3 distractors from the pool, shuffled.
    final others = widget.pool.where((c) => c.headword != widget.card.headword).toList()
      ..shuffle();
    _options = [widget.card, ...others.take(3)]..shuffle();
  }

  void _pick(ReviewCard opt) {
    if (_picked != null) return;
    setState(() => _picked = opt.headword);
    widget.onAnswer(widget.card, opt.headword == widget.card.headword);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: widget.listening
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      PlayButton(word: widget.card.headword, size: 72),
                      const SizedBox(height: 16),
                      Text('Tap to hear it, then pick the meaning',
                          style: AppTheme.quick(
                              size: 13,
                              weight: FontWeight.w600,
                              color: AppColors.onAccent.withValues(alpha: 0.85))),
                    ])
                  : Text(widget.card.headword,
                      textAlign: TextAlign.center,
                      style: AppTheme.baloo(
                          size: 38, weight: FontWeight.w800, color: AppColors.onAccent)),
            ),
          ),
          for (final o in _options) ...[
            _optionTile(o),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _optionTile(ReviewCard o) {
    final isAnswer = o.headword == widget.card.headword;
    Color bg = AppColors.white;
    Color fg = AppColors.ink;
    if (_picked != null) {
      if (isAnswer) {
        bg = AppColors.mint;
        fg = AppColors.onAccent;
      } else if (o.headword == _picked) {
        bg = AppColors.coral;
        fg = AppColors.onAccent;
      } else {
        bg = AppColors.white.withValues(alpha: 0.6);
      }
    }
    return BouncePress(
      onTap: () => _pick(o),
      pressedScale: 0.97,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Text(meaningOf(o),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style:
                AppTheme.quick(size: 14.5, weight: FontWeight.w600, color: fg)),
      ),
    );
  }
}

// ------------------------------------------------------------------ typing
class _TypingQuestion extends StatefulWidget {
  const _TypingQuestion({super.key, required this.card, required this.onAnswer});
  final ReviewCard card;
  final void Function(ReviewCard, bool) onAnswer;

  @override
  State<_TypingQuestion> createState() => _TypingQuestionState();
}

class _TypingQuestionState extends State<_TypingQuestion> {
  final _ctrl = TextEditingController();
  bool? _correct;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _check() {
    if (_correct != null) return;
    final ok = _ctrl.text.trim().toLowerCase() == widget.card.headword.toLowerCase();
    setState(() => _correct = ok);
    widget.onAnswer(widget.card, ok);
  }

  @override
  Widget build(BuildContext context) {
    final border = _correct == null
        ? AppColors.white
        : (_correct! ? AppColors.mint : AppColors.coral);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Type the English word for:',
                    style: AppTheme.quick(
                        size: 13,
                        weight: FontWeight.w600,
                        color: AppColors.onAccent.withValues(alpha: 0.85))),
                const SizedBox(height: 12),
                Text(meaningOf(widget.card),
                    textAlign: TextAlign.center,
                    style: AppTheme.baloo(
                        size: 24, weight: FontWeight.w700, color: AppColors.onAccent)),
                if (_correct == false) ...[
                  const SizedBox(height: 14),
                  Text('→ ${widget.card.headword}',
                      style: AppTheme.baloo(
                          size: 17,
                          weight: FontWeight.w700,
                          color: AppColors.onAccent)),
                ],
              ]),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border, width: 3),
            ),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              enabled: _correct == null,
              onSubmitted: (_) => _check(),
              textAlign: TextAlign.center,
              style: AppTheme.baloo(size: 20, weight: FontWeight.w700),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
                hintText: 'type here…',
              ),
            ),
          ),
          const SizedBox(height: 12),
          BouncePress(
            onTap: _check,
            pressedScale: 0.96,
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text('Check',
                  style: AppTheme.baloo(
                      size: 15,
                      weight: FontWeight.w700,
                      color: AppColors.coral)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- matching
class _MatchingBoard extends StatefulWidget {
  const _MatchingBoard({
    required this.cards,
    required this.onResult,
    required this.onDone,
  });
  final List<ReviewCard> cards;
  final void Function(ReviewCard, bool) onResult;
  final VoidCallback onDone;

  @override
  State<_MatchingBoard> createState() => _MatchingBoardState();
}

class _MatchingBoardState extends State<_MatchingBoard> {
  late final List<int> _meaningOrder; // shuffled card indices for right column
  final _matched = <int>{};
  int? _selWord; // selected left card index
  int? _selMeaning; // selected right card index
  int? _flash; // card index briefly flashing red

  @override
  void initState() {
    super.initState();
    _meaningOrder = List.generate(widget.cards.length, (i) => i)..shuffle(math.Random());
  }

  void _tapWord(int i) {
    if (_matched.contains(i) || _flash != null) return;
    setState(() => _selWord = i);
    _resolve();
  }

  void _tapMeaning(int i) {
    if (_matched.contains(i) || _flash != null) return;
    setState(() => _selMeaning = i);
    _resolve();
  }

  void _resolve() {
    if (_selWord == null || _selMeaning == null) return;
    final w = _selWord!, m = _selMeaning!;
    if (w == m) {
      widget.onResult(widget.cards[w], true);
      setState(() {
        _matched.add(w);
        _selWord = null;
        _selMeaning = null;
      });
      if (_matched.length == widget.cards.length) {
        Future.delayed(const Duration(milliseconds: 350), widget.onDone);
      }
    } else {
      Sfx.wrong();
      setState(() => _flash = m);
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
            _flash = null;
            _selWord = null;
            _selMeaning = null;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        children: [
          Text('Tap a word, then its meaning',
              style: AppTheme.quick(
                  size: 13,
                  weight: FontWeight.w600,
                  color: AppColors.onAccent.withValues(alpha: 0.85))),
          const SizedBox(height: 16),
          // One row per pair so the word box and meaning box share a height
          // (IntrinsicHeight + stretch) — keeps the two columns aligned even
          // though meanings are much longer than headwords.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < widget.cards.length; i++) ...[
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _cell(i, true)),
                          const SizedBox(width: 12),
                          Expanded(child: _cell(_meaningOrder[i], false)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(int cardIndex, bool isWord) {
    final matched = _matched.contains(cardIndex);
    final selected =
        isWord ? _selWord == cardIndex : _selMeaning == cardIndex;
    final flashing = !isWord && _flash == cardIndex;

    Color bg = AppColors.white;
    Color fg = AppColors.ink;
    if (matched) {
      bg = AppColors.mint.withValues(alpha: 0.85);
      fg = AppColors.onAccent;
    } else if (flashing) {
      bg = AppColors.coral;
      fg = AppColors.onAccent;
    } else if (selected) {
      bg = AppColors.white;
      fg = AppColors.violet;
    } else {
      bg = AppColors.white.withValues(alpha: 0.88);
    }

    return BouncePress(
      onTap: () => isWord ? _tapWord(cardIndex) : _tapMeaning(cardIndex),
      pressedScale: 0.96,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: matched ? 0.55 : 1,
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(color: AppColors.violet, width: 2.5)
                : null,
          ),
          child: Text(
            isWord ? widget.cards[cardIndex].headword : meaningOf(widget.cards[cardIndex]),
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.quick(
                size: isWord ? 15 : 12.5, weight: FontWeight.w700, color: fg),
          ),
        ),
      ),
    );
  }
}
