"""Free EN->many translation via deep-translator's GoogleTranslator (no API key).

Translations are an *extra*, not the focus — the English definition is the primary
content everywhere. To add a language later (e.g. Persian), add its ISO code to
TARGET_LANGS — one line, no schema change (translations live in a JSON map on the
`words` row, see models.py), then run backfill_translations.py for existing rows.

ponytail: unofficial Google web endpoint — can rate-limit or break. Mitigated by
caching every result in the `words` table (see lookup.py), so at ~100 users this is
hit a few hundred times total, then ~never. Translation must never break a lookup:
any failure returns None.
"""
import logging
from concurrent.futures import ThreadPoolExecutor

from deep_translator import GoogleTranslator

log = logging.getLogger("lexika.translate")

# Languages auto-translated on each new lookup. Add "fa" (Persian), "tr", "ar"…
# GoogleTranslator accepts ISO 639-1 codes; a bad code just yields None.
TARGET_LANGS = ["ru", "kk", "fa"]


def translate(text: str, target: str) -> str | None:
    """EN -> target ISO code. Returns None on empty input or any failure."""
    text = (text or "").strip()
    if not text:
        return None
    try:
        out = GoogleTranslator(source="en", target=target).translate(text)
        return out or None
    except Exception as exc:  # network / endpoint hiccup / bad code — degrade
        log.warning("translate(%r -> %s) failed: %s", text, target, exc)
        return None


def translate_all(text: str) -> dict[str, str]:
    """{lang: translation} for every TARGET_LANGS that succeeds (others omitted).
    The per-language calls run concurrently — they're network-bound, so a cold
    lookup waits ~one call instead of three. ponytail: a thread pool, not an
    async rewrite of the whole stack."""
    with ThreadPoolExecutor(max_workers=len(TARGET_LANGS)) as ex:
        pairs = ex.map(lambda lang: (lang, translate(text, lang)), TARGET_LANGS)
    return {lang: t for lang, t in pairs if t}


def _selfcheck():
    ru = translate("house", "ru")
    assert ru and ru.lower() != "house", f"ru translation looks wrong: {ru!r}"
    assert translate("", "ru") is None
    assert translate("house", "zz9") is None  # invalid code -> None, no throw
    allm = translate_all("house")
    assert set(allm) <= set(TARGET_LANGS) and "ru" in allm, allm
    print(f"translate self-check: passed (house -> {allm}).")


if __name__ == "__main__":
    _selfcheck()
