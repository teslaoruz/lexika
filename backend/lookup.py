"""Word lookup: cache-check -> Free Dictionary API -> word_metadata join -> cache write.
Shared by the /words/lookup endpoint and seed.py so demo decks get real data.

ponytail: live RU/KK translation deferred (needs a billing key) — translation_*
columns stay null, exactly as CONTRACT.md says.
"""
import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session
from models import Word, WordMetadata
from translate import translate

DICT_API = "https://api.dictionaryapi.dev/api/v2/entries/en/{word}"


class WordNotFound(Exception):
    pass


def _parse_dict_response(headword: str, data: list) -> dict:
    """Flatten the Free Dictionary API shape into our Word columns.
    Takes the first non-empty value for each field across entries/meanings."""
    phonetic = None
    audio_url = None
    part_of_speech = None
    definition_en = None
    example_en = None
    synonyms: list[str] = []
    antonyms: list[str] = []

    for entry in data:
        if not phonetic:
            phonetic = entry.get("phonetic")
        for ph in entry.get("phonetics", []):
            if not phonetic and ph.get("text"):
                phonetic = ph["text"]
            if not audio_url and ph.get("audio"):
                audio_url = ph["audio"]
        for meaning in entry.get("meanings", []):
            if not part_of_speech:
                part_of_speech = meaning.get("partOfSpeech")
            synonyms.extend(meaning.get("synonyms", []))
            antonyms.extend(meaning.get("antonyms", []))
            for d in meaning.get("definitions", []):
                if not definition_en and d.get("definition"):
                    definition_en = d["definition"]
                if not example_en and d.get("example"):
                    example_en = d["example"]
                synonyms.extend(d.get("synonyms", []))
                antonyms.extend(d.get("antonyms", []))

    # dedupe, preserve order, cap to keep the payload tidy
    def uniq(xs):
        seen, out = set(), []
        for x in xs:
            if x not in seen:
                seen.add(x)
                out.append(x)
        return out[:10]

    return {
        "headword": headword,
        "phonetic": phonetic,
        "audio_url": audio_url or None,
        "part_of_speech": part_of_speech,
        "definition_en": definition_en,
        "example_en": example_en,
        "synonyms_json": uniq(synonyms),
        "antonyms_json": uniq(antonyms),
    }


def get_or_fetch_word(db: Session, raw_word: str, client: httpx.Client | None = None) -> Word:
    """Return a cached Word, fetching + caching from the Dictionary API on miss.
    Raises WordNotFound if the dictionary API 404s (not a real word)."""
    headword = raw_word.strip().lower()
    if not headword:
        raise WordNotFound(raw_word)

    cached = db.scalar(select(Word).where(Word.headword == headword))
    if cached:
        return cached

    own_client = client is None
    client = client or httpx.Client(timeout=15)
    try:
        resp = client.get(DICT_API.format(word=headword))
    finally:
        if own_client:
            client.close()

    if resp.status_code == 404:
        raise WordNotFound(headword)
    resp.raise_for_status()

    fields = _parse_dict_response(headword, resp.json())

    meta = db.get(WordMetadata, headword)
    word = Word(
        cefr_level=meta.cefr_level if meta else None,
        is_academic=bool(meta.is_academic) if meta else False,
        # Translate the headword only (cheap, one word). None on failure — never
        # blocks the lookup. Cached on this row, so re-lookups don't re-translate.
        translation_ru=translate(headword, "ru"),
        translation_kk=translate(headword, "kk"),
        source="dictionaryapi.dev",
        **fields,
    )
    db.add(word)
    db.commit()
    db.refresh(word)
    return word


def _selfcheck():
    """Cache hit/miss sanity check against the live DB. Run after seeding:
    `uv run python lookup.py`. First call may fetch; second must be a pure cache
    hit (same row id, zero network calls)."""
    from db import SessionLocal
    db = SessionLocal()
    try:
        calls = {"n": 0}
        real_get = httpx.Client.get

        def counting_get(self, *a, **k):
            calls["n"] += 1
            return real_get(self, *a, **k)

        httpx.Client.get = counting_get
        try:
            w1 = get_or_fetch_word(db, "Ubiquitous")  # mixed case -> normalized
            before = calls["n"]
            w2 = get_or_fetch_word(db, "ubiquitous")  # must be a cache hit
            after = calls["n"]
        finally:
            httpx.Client.get = real_get

        assert w1.id == w2.id, (w1.id, w2.id)
        assert after == before, f"cache miss on second lookup: {before} -> {after}"
        assert w1.headword == "ubiquitous"
        print(f"lookup cache self-check: passed (cache hit made {after - before} network calls).")
    finally:
        db.close()


if __name__ == "__main__":
    _selfcheck()
