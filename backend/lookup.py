"""Word lookup: cache-check -> Free Dictionary API -> word_metadata join -> cache write.
Shared by the /words/lookup endpoint and seed.py so demo decks get real data.

The English definition is the primary content; translations are a cached extra
(see translate.py) stored in the word's `translations` JSON map.
"""
import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session
from models import Word, WordMetadata, WordFamily
from translate import translate_all

DICT_API = "https://api.dictionaryapi.dev/api/v2/entries/en/{word}"
DATAMUSE_API = "https://api.datamuse.com/words"

# How many synonyms/antonyms we consider "enough" before reaching for Datamuse.
_THIN = 2


class WordNotFound(Exception):
    pass


def _datamuse(client: httpx.Client, **params) -> list[dict]:
    """Single Datamuse call, never raises — enrichment is best-effort.
    ponytail: no retry/backoff; on any failure we just return [] and fall back
    to whatever the Dictionary API gave us. Add caching/retry if it gets hot."""
    try:
        r = client.get(DATAMUSE_API, params={"max": 10, **params})
        r.raise_for_status()
        return r.json()
    except Exception:
        return []


def _cefr_from_freq(f_per_million: float | None) -> str | None:
    """Coarse CEFR estimate from Datamuse word frequency (occurrences per
    million words). Higher frequency -> easier word -> lower CEFR band.
    ponytail: hand-tuned cutoffs, not corpus-calibrated. Upgrade path: replace
    with the `wordfreq` package (zipf score) or a CEFR-J lookup if accuracy
    matters; the band thresholds are the only thing to change."""
    if f_per_million is None:
        return None
    if f_per_million >= 100:
        return "A1"
    if f_per_million >= 20:
        return "A2"
    if f_per_million >= 5:
        return "B1"
    if f_per_million >= 1:
        return "B2"
    if f_per_million >= 0.2:
        return "C1"
    return "C2"


def _enrich(client: httpx.Client, headword: str, fields: dict) -> tuple[str | None, list[str]]:
    """Best-effort enrichment via Datamuse for words the Dictionary API left bare.
    Returns (cefr_estimate, word_family_relatives) and mutates fields' synonym/
    antonym lists in place. Frequency drives the CEFR estimate."""
    # Fill thin synonyms/antonyms from Datamuse.
    if len(fields["synonyms_json"]) < _THIN:
        fields["synonyms_json"] = _dedupe(
            fields["synonyms_json"] + [w["word"] for w in _datamuse(client, rel_syn=headword)]
        )
    if len(fields["antonyms_json"]) < _THIN:
        fields["antonyms_json"] = _dedupe(
            fields["antonyms_json"] + [w["word"] for w in _datamuse(client, rel_ant=headword)]
        )

    # Frequency tag (md=f) -> CEFR estimate.
    cefr = None
    rows = _datamuse(client, sp=headword, md="f", max=1)
    if rows:
        for tag in rows[0].get("tags", []):
            if tag.startswith("f:"):
                try:
                    cefr = _cefr_from_freq(float(tag[2:]))
                except ValueError:
                    pass

    # Word family: morphological relatives sharing a stem prefix.
    # ponytail: stem = first 4+ chars, filter Datamuse triggers/spelling-neighbours
    # to those that start with that stem. Crude but beats nothing; real morphology
    # (a stemmer like snowball, or an AWL word-family table) is the upgrade path.
    stem = headword[: max(4, len(headword) - 3)]
    cand = {w["word"] for w in _datamuse(client, rel_trg=headword)}
    cand |= {w["word"] for w in _datamuse(client, sp=headword + "*")}
    family = [
        w for w in _dedupe(sorted(cand))
        if w != headword and w.startswith(stem) and w.isalpha()
    ][:6]
    return cefr, family


def _dedupe(xs: list[str]) -> list[str]:
    seen, out = set(), []
    for x in xs:
        if x and x not in seen:
            seen.add(x)
            out.append(x)
    return out[:10]


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
        if resp.status_code == 404:
            raise WordNotFound(headword)
        resp.raise_for_status()

        fields = _parse_dict_response(headword, resp.json())

        meta = db.get(WordMetadata, headword)
        cefr = meta.cefr_level if meta else None

        # Enrich words that aren't already in the seeded metadata: fill thin
        # synonyms/antonyms, estimate a CEFR level, and derive a word family.
        # Reuses the same httpx client — no second connection pool.
        est_cefr, family = _enrich(client, headword, fields)
    finally:
        if own_client:
            client.close()
    if cefr is None:
        cefr = est_cefr

    word = Word(
        cefr_level=cefr,
        is_academic=bool(meta.is_academic) if meta else False,
        # Translate the headword into every TARGET_LANGS (cheap, one word each).
        # Failures are simply omitted — never blocks the lookup. Cached on this
        # row, so re-lookups don't re-translate.
        translations=translate_all(headword),
        source="dictionaryapi.dev",
        **fields,
    )
    db.add(word)

    # Persist enrichment so repeat lookups (and /relations) are cheap. word_metadata
    # caches the CEFR estimate; word_family caches the derived relatives as synonym
    # rows (the curated noun_form/verb_form/etc. rows still win when seeded).
    if meta is None and cefr is not None:
        db.add(WordMetadata(word=headword, cefr_level=cefr))
    if family and not db.scalar(select(WordFamily).where(WordFamily.base_word == headword)):
        for rel in family:
            db.add(WordFamily(base_word=headword, related_word=rel, relation_type="related"))

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
