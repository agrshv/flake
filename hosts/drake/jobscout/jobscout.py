"""Nightly job-ad scout: scrape, dedupe, hard-filter, score with a local LLM, notify.

Configured entirely by the environment (see ./default.nix). State is one SQLite
file in $STATE_DIRECTORY: every ad that reached a verdict is remembered, so it is
scored and sent once. An ad whose scoring (or LinkedIn description fetch) failed
is not stored and is retried the next night.
"""

import base64
import json
import logging
import os
import random
import re
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import jobspy.glassdoor
import requests
from bs4 import BeautifulSoup
from jobspy import scrape_jobs
from markdownify import markdownify

log = logging.getLogger("jobscout")

# JobSpy's README says Google Jobs is currently unavailable.
SITES = ["indeed", "glassdoor", "linkedin"]
COUNTRIES = [("Germany", "germany"), ("Netherlands", "netherlands")]
TERMS = [
    "DevOps Engineer",
    "Site Reliability Engineer",
    "Platform Engineer",
    "Kubernetes Engineer",
    "Cloud Infrastructure Engineer",
]
# Overlaps the 24 h between runs; the dedupe absorbs the overlap.
HOURS_OLD = 36
RESULTS_PER_SEARCH = 30
SEND_THRESHOLD = 6

# LinkedIn (logged-out guest API, so no account is involved) answers bursts
# with 429s that clear within about a minute. JobSpy fetches every result's
# description back to back, which tripped 429 on 7 of 15 jobs even at 2–4 s
# spacing (2026-10-13). So LinkedIn is searched without descriptions, and only
# ads not already in the database get theirs fetched here, slowly.
LINKEDIN_PACE = (8, 14)  # seconds between job pages
LINKEDIN_BACKOFF = 75  # seconds to wait out a 429
LINKEDIN_PAUSE = (20, 40)  # seconds between LinkedIn searches


def _safari_session(*args, **kwargs):
    # Cloudflare in front of Glassdoor challenges the Chrome fingerprint of the
    # curl-impersonate in nixpkgs (403; pip's bundled build passes) but lets
    # Safari through — on both 26.05 and unstable, tested 2026-10-13. JobSpy
    # does the same for ZipRecruiter.
    session = _create_session(*args, **kwargs)
    session.impersonate = "safari"
    return session


_create_session = jobspy.glassdoor.create_session
jobspy.glassdoor.create_session = _safari_session

TITLE_SKIP = re.compile(
    r"\b(junior|intern|internship|praktikum|praktikant|werkstudent|working student|"
    r"trainee|ausbildung|apprentice|student)\b",
    re.I,
)

# The hand-triage rules from the wiki's job-market-map, as regexes. Cheap and
# certain, so they run before the model; the model only sees what survives.
# A language match is waived when "a plus"-style wording follows it closely:
# "fluent English, German is a plus" must not read as "German required".
LANGUAGE_WAIVER = re.compile(
    r"\b(plus|nice|advantage|advantageous|bonus|benefit|preferred|desirable|"
    r"von vorteil|wünschenswert|wuenschenswert|ein plus)\b", re.I)
BLOCKERS = [
    ("German required", True, re.compile(
        r"(fluent|fließend|fliessend|business[- ]fluent|excellent|proficient|sehr gute)"
        r"\W+(\w+\W+){0,3}(german|deutsch)"
        r"|(german|deutsch)\w*\W+(\w+\W+){0,3}(c1|c2|b2|fluent|verhandlungssicher|"
        r"fließend|fliessend|muttersprach)"
        r"|verhandlungssicher", re.I)),
    ("Dutch required", True, re.compile(
        r"(fluent|proficient)\W+(\w+\W+){0,3}dutch|dutch\W+(\w+\W+){0,3}(c1|c2|b2|fluent|native)"
        r"|vloeiend nederlands", re.I)),
    ("security vetting", False, re.compile(
        r"sicherheitsüberprüfung|sicherheitsueberpruefung|security clearance|\bsü ?[23]\b", re.I)),
    ("temp agency / freelance", False, re.compile(
        r"arbeitnehmerüberlassung|arbeitnehmerueberlassung|\banü\b|zeitarbeit|freiberuf|"
        r"\bfreelance\b", re.I)),
    ("existing work permit required", False, re.compile(
        r"(no|not able to|unable to|cannot|can't|do not|don't)\s+(offer\s+|provide\s+)?"
        r"(visa\s+)?sponsor"
        r"|(valid|existing|eu|german|dutch)\s+(work|residence)\s+permit\b[^.]{0,30}\b(required|mandatory)"
        r"|residence\s+in\s+(germany|the\s+netherlands)\s+is\s+(required|mandatory)"
        r"|must\s+(already\s+)?(have|hold|possess)\s+(the\s+)?(right|permission)\s+to\s+work"
        r"|arbeitserlaubnis\s+(ist\s+)?(erforderlich|voraussetzung)", re.I)),
]

# An ad written in German (or Dutch) almost always wants that language at work. Counting a few
# function words is crude but cheap, and robust to the odd German phrase in an
# English ad.
DUTCH_WORDS = re.compile(r"\b(en|het|een|wij|je|jouw|voor|met|van|zijn|bij|ons)\b", re.I)
GERMAN_WORDS = re.compile(r"\b(und|der|die|das|wir|sie|mit|für|bei|eine?|du|dein|deine|ihre?)\b", re.I)
ENGLISH_WORDS = re.compile(r"\b(and|the|we|you|with|for|our|your|a|an|of|to)\b", re.I)

# The model rates fit; it does not get to declare blockers on its own say-so.
# Tested on qwen3:4b (2026-10-13): asked for "blockers", it marked nearly every
# ad "German required" and treated a missing sponsorship line as a blocker.
# So a requirement only counts when the model quotes the ad and the quote is
# really there (see verified()).
VERDICT_SCHEMA = {
    "type": "object",
    "properties": {
        "role_match": {"type": "boolean"},
        "score": {"type": "integer", "minimum": 0, "maximum": 10},
        "language_required": {"type": "string", "enum": ["none", "german", "dutch"]},
        "language_quote": {"type": "string"},
        "permit_required": {"type": "boolean"},
        "permit_quote": {"type": "string"},
        "reason": {"type": "string"},
    },
    "required": ["role_match", "score", "language_required", "language_quote",
                 "permit_required", "permit_quote", "reason"],
}

INSTRUCTIONS = """Answer about the job ad above.
- role_match: true if the job is mainly DevOps, SRE, platform, infrastructure or cloud operations work.
- score: 0-10, fit of the role's stack and seniority with the candidate. Ignore language and visa.
- language_required: "german" or "dutch" only if the ad itself demands that language at a working level.
  "none" if the ad doesn't mention it, or calls it a plus or nice to have.
- language_quote: the exact sentence from the ad that demands it, copied verbatim; "" when none.
- permit_required: true only if the ad itself says applicants must already have the right to work,
  or that it offers no visa sponsorship. An ad that simply doesn't mention visas is false.
- permit_quote: the exact sentence from the ad, copied verbatim; "" when false.
- reason: one short sentence on fit."""



def env(name):
    value = os.environ.get(name)
    if not value:
        sys.exit(f"jobscout: {name} is not set")
    return value


INSERT = (
    "INSERT INTO ads VALUES (:url, :seen, :site, :title, :company, :location,"
    " :verdict, :blockers, :score, :reason, :notified)"
)


def job_key(title, company):
    # "(m/w/d)", "(all genders)" and punctuation differ between boards, and so
    # does the company's legal name ("Vantage" on Indeed, "Vantage Data Centers
    # Germany" on Glassdoor), hence only its first word.
    title = re.sub(r"\((m|f|w|d|x|all genders?|alle)[^)]*\)", "", title or "", flags=re.I)
    company = (squash(company or "").split() or [""])[0]
    return f"{squash(title)}|{company}"


def open_db(path):
    db = sqlite3.connect(path)
    db.execute(
        """CREATE TABLE IF NOT EXISTS ads (
             url TEXT PRIMARY KEY,
             seen TEXT NOT NULL,
             site TEXT, title TEXT, company TEXT, location TEXT,
             verdict TEXT NOT NULL,   -- skipped | duplicate | blocked | scored
             blockers TEXT, score INTEGER, reason TEXT,
             notified INTEGER NOT NULL DEFAULT 0
           )"""
    )
    return db


def scrape():
    """Every search, merged and deduped by URL. Returns (ads, searches_with_results)."""
    ads, productive = {}, 0
    for location, country in COUNTRIES:
        for site in SITES:
            for term in TERMS:
                try:
                    df = scrape_jobs(
                        site_name=[site],
                        search_term=term,
                        location=location,
                        country_indeed=country,
                        results_wanted=RESULTS_PER_SEARCH,
                        hours_old=HOURS_OLD,
                        fetch_description=site != "linkedin",
                        description_format="markdown",
                        verbose=0,
                    )
                except Exception:
                    log.exception("scrape failed: %s / %s / %s", site, location, term)
                    continue
                if df.empty:
                    continue
                productive += 1
                if site == "linkedin":
                    time.sleep(random.uniform(*LINKEDIN_PAUSE))
                for row in df.to_dict("records"):
                    url = row.get("job_url_direct") or row.get("job_url")
                    if url and url not in ads:
                        ads[url] = row
    return ads, productive


def linkedin_description(job_url):
    """The job page's description as markdown, waiting out one 429; None if it can't be read."""
    for attempt in range(2):
        time.sleep(random.uniform(*LINKEDIN_PACE))
        response = requests.get(job_url, headers={"User-Agent": LINKEDIN_UA}, timeout=15)
        if response.status_code == 429 and attempt == 0:
            log.info("LinkedIn 429, waiting %d s", LINKEDIN_BACKOFF)
            time.sleep(LINKEDIN_BACKOFF)
            continue
        if response.status_code != 200:
            log.warning("LinkedIn %d for %s", response.status_code, job_url)
            return None
        markup = BeautifulSoup(response.text, "html.parser").find(
            "div", class_="show-more-less-html__markup")
        return markdownify(str(markup)).strip() if markup else None
    return None


LINKEDIN_UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
               "Chrome/141.0.0.0 Safari/537.36")


def text(value):
    return "" if value is None or value != value else str(value)  # NaN != NaN


def rule_blockers(description):
    found = []
    for name, waivable, rx in BLOCKERS:
        for match in rx.finditer(description):
            if waivable and LANGUAGE_WAIVER.search(description, match.end(), match.end() + 40):
                continue
            found.append(name)
            break
    de, en = len(GERMAN_WORDS.findall(description)), len(ENGLISH_WORDS.findall(description))
    nl = len(DUTCH_WORDS.findall(description))
    if de > 20 and de > en:
        found.append("ad written in German")
    if nl > 20 and nl > en:
        found.append("ad written in Dutch")
    return found


def squash(value):
    return re.sub(r"[^a-z0-9äöüß]+", " ", value.lower()).strip()


# A quote must also be *about* the claim: qwen3:4b once "proved" German was
# required with a sentence about tech strategy that never mentioned German.
TOPIC = {
    "german": re.compile(r"german|deutsch", re.I),
    "dutch": re.compile(r"dutch|nederlands", re.I),
    "permit": re.compile(
        r"permit|visa|sponsor|right to work|authori[sz]|residen|relocat|located in|"
        r"arbeitserlaubnis|aufenthalt", re.I),
}


def verified(topic, quote, description):
    """True if the quote is about `topic` and really is in the ad (ignoring case and punctuation)."""
    if not TOPIC[topic].search(quote):
        return False
    if topic != "permit" and LANGUAGE_WAIVER.search(quote):
        return False  # "German is a significant advantage" is not a requirement
    quote = squash(quote)
    return len(quote) >= 12 and quote in squash(description)


def score(ollama_url, model, profile, ad):
    description = text(ad.get("description"))
    prompt = (
        f"{profile}\n\n# Job ad\n\n"
        f"Title: {text(ad.get('title'))}\nCompany: {text(ad.get('company'))}\n"
        f"Location: {text(ad.get('location'))}\n\n{description[:6000]}\n\n{INSTRUCTIONS}"
    )
    response = requests.post(
        f"{ollama_url}/api/chat",
        json={
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "format": VERDICT_SCHEMA,
            "stream": False,
            "think": False,
            "keep_alive": "10m",
            "options": {"temperature": 0, "num_ctx": 8192},
        },
        timeout=900,
    )
    response.raise_for_status()
    answer = json.loads(response.json()["message"]["content"])
    blockers = []
    language = answer["language_required"]
    if language != "none" and verified(language, answer["language_quote"], description):
        blockers.append(f"{language} required: {answer['language_quote']}")
    if answer["permit_required"] and verified("permit", answer["permit_quote"], description):
        blockers.append(f"permit required: {answer['permit_quote']}")
    if not answer["role_match"]:
        blockers.append("not a DevOps/SRE/platform role")
    return {
        "score": answer["score"],
        "blockers": blockers,
        "reason": answer["reason"],
        "sendable": not blockers,
    }


def notify(ntfy_url, token, ad, verdict):
    url = text(ad.get("job_url_direct")) or text(ad.get("job_url"))
    title = f"{verdict['score']}/10 · {text(ad.get('title'))} · {text(ad.get('company'))}"
    body = f"{text(ad.get('location'))} ({ad['site']})\n{verdict['reason']}"
    requests.post(
        ntfy_url,
        data=body.encode(),
        headers={
            "Authorization": f"Bearer {token}",
            # HTTP headers are latin-1; ntfy decodes RFC 2047 for non-ASCII titles.
            "Title": f"=?UTF-8?B?{base64.b64encode(title.encode()).decode()}?=",
            "Click": url,
            "Tags": "briefcase",
            "Priority": "default" if verdict["score"] < 8 else "high",
        },
        timeout=15,
    ).raise_for_status()


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    profile = Path(env("JOBSCOUT_PROFILE")).read_text()
    model, ollama_url = env("JOBSCOUT_MODEL"), env("OLLAMA_URL")
    ntfy_url, token = env("NTFY_URL"), env("NTFY_TOKEN")
    db = open_db(Path(env("STATE_DIRECTORY")) / "jobscout.db")
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    ads, productive = scrape()
    if productive == 0:
        # Every board empty is not a quiet night, it is a broken scraper.
        sys.exit("jobscout: every search returned nothing")

    known = {row[0] for row in db.execute("SELECT url FROM ads")}
    new = {url: ad for url, ad in ads.items() if url not in known}
    counts = {"skipped": 0, "duplicate": 0, "blocked": 0, "scored": 0, "sent": 0,
              "failed": 0, "unfetched": 0}
    # The same job turns up on Indeed, Glassdoor and LinkedIn under different
    # URLs; title + company catches the repeats so it's scored and sent once.
    seen_jobs = {job_key(t, c) for t, c in db.execute("SELECT title, company FROM ads")}

    for url, ad in new.items():
        record = dict(url=url, seen=now, site=ad["site"], title=text(ad.get("title")),
                      company=text(ad.get("company")), location=text(ad.get("location")),
                      blockers=None, score=None, reason=None, notified=0)
        key = job_key(record["title"], record["company"])
        if key in seen_jobs:
            record["verdict"] = "duplicate"
            counts["duplicate"] += 1
            db.execute(INSERT, record)
            db.commit()
            continue
        description = text(ad.get("description"))
        if not description and ad["site"] == "linkedin" and not TITLE_SKIP.search(record["title"]):
            description = linkedin_description(text(ad.get("job_url")))
            if description is None:
                counts["unfetched"] += 1  # not stored, so tried again next run
                continue
            ad["description"] = description

        if TITLE_SKIP.search(record["title"]):
            record["verdict"] = "skipped"
        elif blockers := rule_blockers(description):
            record.update(verdict="blocked", blockers=json.dumps(blockers))
        else:
            try:
                verdict = score(ollama_url, model, profile, ad)
            except Exception:
                log.exception("scoring failed, will retry next run: %s", url)
                counts["failed"] += 1
                continue
            record.update(verdict="scored", blockers=json.dumps(verdict["blockers"]),
                          score=verdict["score"], reason=verdict["reason"])
            if verdict["sendable"] and verdict["score"] >= SEND_THRESHOLD:
                notify(ntfy_url, token, ad, verdict)
                record["notified"] = 1
                counts["sent"] += 1

        counts[record["verdict"]] += 1
        seen_jobs.add(key)
        db.execute(INSERT, record)
        db.commit()

    log.info("scraped %d, new %d: %s", len(ads), len(new), counts)
    if counts["failed"] and not counts["scored"]:
        sys.exit("jobscout: every scoring call failed (is ollama up?)")


if __name__ == "__main__":
    main()
