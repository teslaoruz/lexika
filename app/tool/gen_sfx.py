"""Generate Lexika's short UI sound effects as 16-bit mono WAVs.

ponytail: synthesized tones, not downloaded clips — no licensing, no binary
blobs of unknown origin, reproducible from this script. Run from `app/`:
    python tool/gen_sfx.py
All clips are <1s per build-plan 5.8. Re-run to tweak; commit the WAVs.
"""
import math
import os
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")


def _write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(
            struct.pack("<h", max(-32767, min(32767, int(s * 32767))))
            for s in samples
        )
        w.writeframes(frames)
    print(f"  wrote {name} ({len(samples)/RATE:.2f}s)")


def tone(freq, dur, amp=0.35, attack=0.005, release=0.06):
    """A sine note with a short attack and exponential-ish release."""
    n = int(dur * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        env = 1.0
        if t < attack:
            env = t / attack
        rem = dur - t
        if rem < release:
            env = rem / release
        out.append(amp * env * math.sin(2 * math.pi * freq * t))
    return out


def noise(dur, amp=0.3):
    """A short filtered-ish noise swoosh for the card flip."""
    import random
    n = int(dur * RATE)
    out = []
    prev = 0.0
    for i in range(n):
        env = math.sin(math.pi * i / n)  # smooth in-out
        x = random.uniform(-1, 1)
        prev = 0.6 * prev + 0.4 * x  # cheap low-pass -> swoosh not hiss
        out.append(amp * env * prev)
    return out


def main():
    print("Generating SFX ->", os.path.normpath(OUT))
    # correct: bright two-note rise (G5 -> C6)
    _write("correct.wav", tone(784, 0.11) + tone(1047, 0.16))
    # wrong: soft low blip, never harsh (build-plan 5.8)
    _write("wrong.wav", tone(196, 0.18, amp=0.3) + tone(165, 0.16, amp=0.25))
    # flip: quick paper-ish swoosh
    _write("flip.wav", noise(0.12))
    # xp: coin-ish tick (two fast high notes)
    _write("xp.wav", tone(1568, 0.05, amp=0.3) + tone(2093, 0.07, amp=0.3))
    print("Done.")


if __name__ == "__main__":
    main()
