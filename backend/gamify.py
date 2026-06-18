"""XP + streak rules (build-plan 5.4). Tunable knobs — exact formula is flagged
to finalize before Phase 4 (build-plan section 7), so keep it in one place.

ponytail: flat lookup tables, not a config system. They're values that change
maybe twice a year; edit them here.
"""
from datetime import date, timedelta

# XP per correct review by grade. 'again'/'hard' earn little/none (not mastery).
GRADE_XP = {"again": 0, "hard": 5, "good": 10, "easy": 15}

# Harder CEFR words are worth more (5.4: "C1 word = more XP than A1 word").
CEFR_MULT = {"A1": 1.0, "A2": 1.2, "B1": 1.5, "B2": 1.8, "C1": 2.2, "C2": 2.6}


def xp_for(grade: str, cefr_level: str | None) -> int:
    return round(GRADE_XP.get(grade, 0) * CEFR_MULT.get(cefr_level or "", 1.0))


def next_streak(current: int, last_active: date | None, today: date) -> int:
    """New streak length given the last active day and today."""
    if last_active == today:
        return current  # already counted today
    if last_active == today - timedelta(days=1):
        return current + 1  # consecutive day
    return 1  # first day ever, or the streak lapsed


def demo():
    assert xp_for("good", "B2") == 18
    assert xp_for("easy", "C2") == 39
    assert xp_for("again", "C2") == 0
    assert xp_for("good", None) == 10  # untagged word -> base XP
    t = date(2026, 6, 18)
    assert next_streak(5, t, t) == 5                       # same day, no change
    assert next_streak(5, t - timedelta(days=1), t) == 6   # consecutive
    assert next_streak(5, t - timedelta(days=3), t) == 1   # lapsed -> reset
    assert next_streak(0, None, t) == 1                    # first ever
    print("gamify ok")


if __name__ == "__main__":
    demo()
