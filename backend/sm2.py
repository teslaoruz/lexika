"""SM-2 spaced-repetition scheduler — money/logic-critical, keep it here and tested.

Grade mapping (per CONTRACT.md):
  again -> reset reps, interval 0 (≈ <1 min, surfaces again immediately)
  hard  -> interval * 1.2, ease - 0.15
  good  -> standard SM-2 sequence: rep1=1d, rep2=6d, then interval * ease
  easy  -> interval * ease * 1.3, ease + 0.15
Ease floor is 1.3 (classic SM-2). Ease starts at 2.5.

`schedule()` is pure: it takes the current state and a grade and returns the new
state. Persistence/now-injection live in main.py so this stays trivially testable.
"""
from dataclasses import dataclass

EASE_FLOOR = 1.3
EASE_START = 2.5
GRADES = ("again", "hard", "good", "easy")


@dataclass
class SM2State:
    ease_factor: float = EASE_START
    interval_days: float = 0.0
    repetitions: int = 0


def schedule(state: SM2State, grade: str) -> SM2State:
    if grade not in GRADES:
        raise ValueError(f"bad grade {grade!r}; expected one of {GRADES}")

    ease = state.ease_factor
    interval = state.interval_days
    reps = state.repetitions

    if grade == "again":
        # Lapse: forget progress, show again in the same session.
        return SM2State(ease_factor=max(EASE_FLOOR, ease - 0.20), interval_days=0.0, repetitions=0)

    if grade == "hard":
        ease = max(EASE_FLOOR, ease - 0.15)
        # Penalize the interval but never below ~1 day once it's a real card.
        interval = max(1.0, interval * 1.2) if interval > 0 else 1.0
        return SM2State(ease_factor=ease, interval_days=interval, repetitions=reps + 1)

    if grade == "good":
        if reps == 0:
            interval = 1.0
        elif reps == 1:
            interval = 6.0
        else:
            interval = interval * ease
        return SM2State(ease_factor=ease, interval_days=interval, repetitions=reps + 1)

    # easy
    ease = ease + 0.15
    if reps == 0:
        interval = 1.0 * 1.3
    elif reps == 1:
        interval = 6.0 * 1.3
    else:
        interval = interval * ease * 1.3
    return SM2State(ease_factor=ease, interval_days=interval, repetitions=reps + 1)


def _selfcheck():
    # again resets and floors interval at 0
    s = schedule(SM2State(ease_factor=2.5, interval_days=10, repetitions=4), "again")
    assert s.interval_days == 0.0 and s.repetitions == 0, s
    assert s.ease_factor >= EASE_FLOOR

    # good, fresh card -> 1 day, ease unchanged
    s = schedule(SM2State(), "good")
    assert s.interval_days == 1.0 and s.repetitions == 1 and s.ease_factor == 2.5, s

    # good, second rep -> 6 days
    s = schedule(SM2State(interval_days=1.0, repetitions=1), "good")
    assert s.interval_days == 6.0 and s.repetitions == 2, s

    # good, third rep -> interval * ease (6 * 2.5 = 15)
    s = schedule(SM2State(ease_factor=2.5, interval_days=6.0, repetitions=2), "good")
    assert s.interval_days == 15.0 and s.repetitions == 3, s

    # hard -> ease drops 0.15, interval * 1.2
    s = schedule(SM2State(ease_factor=2.5, interval_days=10.0, repetitions=3), "hard")
    assert abs(s.ease_factor - 2.35) < 1e-9, s
    assert abs(s.interval_days - 12.0) < 1e-9, s

    # easy -> ease up 0.15, bigger interval than good
    easy = schedule(SM2State(ease_factor=2.5, interval_days=10.0, repetitions=3), "easy")
    good = schedule(SM2State(ease_factor=2.5, interval_days=10.0, repetitions=3), "good")
    assert easy.interval_days > good.interval_days, (easy, good)
    assert abs(easy.ease_factor - 2.65) < 1e-9, easy

    # ease never drops below floor even after many hard/again grades
    s = SM2State(ease_factor=1.4)
    for _ in range(10):
        s = schedule(s, "hard")
    assert s.ease_factor == EASE_FLOOR, s

    # bad grade rejected
    try:
        schedule(SM2State(), "nope")
        raise AssertionError("expected ValueError")
    except ValueError:
        pass

    print("SM-2 self-check: all assertions passed.")


if __name__ == "__main__":
    _selfcheck()
