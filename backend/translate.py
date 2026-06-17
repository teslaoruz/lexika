"""Free EN->RU/KK translation via deep-translator's GoogleTranslator (no API key).

ponytail: unofficial Google web endpoint — can rate-limit or break. Mitigated by
caching every result in the `words` table (see lookup.py), so at ~100 users this is
hit a few hundred times total, then ~never. Upgrade path: deep-translator also ships
YandexTranslator (better Kazakh) — swap the class + add a free Yandex key, no other
change. Translation must never break a lookup: any failure returns None.
"""
import logging

from deep_translator import GoogleTranslator

log = logging.getLogger("lexika.translate")

_SUPPORTED = {"ru", "kk"}


def translate(text: str, target: str) -> str | None:
    """EN -> target ('ru' or 'kk'). Returns None on empty input or any failure."""
    text = (text or "").strip()
    if not text or target not in _SUPPORTED:
        return None
    try:
        out = GoogleTranslator(source="en", target=target).translate(text)
        return out or None
    except Exception as exc:  # network / endpoint hiccup — degrade gracefully
        log.warning("translate(%r -> %s) failed: %s", text, target, exc)
        return None


def _selfcheck():
    ru = translate("house", "ru")
    assert ru and ru.lower() != "house", f"ru translation looks wrong: {ru!r}"
    assert translate("", "ru") is None
    assert translate("house", "fr") is None  # unsupported target
    print(f"translate self-check: passed (house -> ru = {ru!r}).")


if __name__ == "__main__":
    _selfcheck()
