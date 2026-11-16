"""Keep publications.yml up to date.

Runs twice a week on GitHub (workflow "Update publications") and can be
started by hand under Actions.

What it does
  1. Searches PubMed by author name and appends papers not yet listed.
  2. Looks each paper up in OpenAlex by DOI to add a link to a legal
     open-access PDF where one exists.
Entries are never removed, and fields filled in by hand (pdf, open_data,
open_code, preregistration, preclinical, hide ...) are never overwritten.
Titles listed in scripts/skip.txt (one per line) are never imported.
"""

import json
import re
import sys
import time
import urllib.parse
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

import yaml

PUBMED_QUERY = "Jensen KHR[Author] OR Reveles Jensen KH[Author] OR Reveles Jensen K[Author]"
PUBS_FILE = Path("publications.yml")
SKIP_FILE = Path("scripts/skip.txt")
EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/"


def get_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "academic-site-updater"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def key(title):
    return re.sub(r"[^a-z0-9]", "", str(title).lower())


def same_title(a, b):
    return SequenceMatcher(None, a, b).ratio() >= 0.9


def main():
    text = PUBS_FILE.read_text(encoding="utf-8")
    header = [line for line in text.splitlines() if line.startswith("#")]
    pubs = yaml.safe_load(text)
    skip = {key(t) for t in SKIP_FILE.read_text(encoding="utf-8").splitlines()} if SKIP_FILE.exists() else set()
    before = yaml.safe_dump(pubs, allow_unicode=True, sort_keys=False)

    # 1. New papers from PubMed. A failure here stops the run with an error.
    found = get_json(EUTILS + "esearch.fcgi?db=pubmed&retmode=json&retmax=500&term=" + urllib.parse.quote(PUBMED_QUERY))
    pmids = found["esearchresult"]["idlist"]
    known = {str(p.get("pmid", "")) for p in pubs}
    new_pmids = [i for i in pmids if i not in known]
    print(f"PubMed lists {len(pmids)} paper(s); {len(new_pmids)} not yet on the site.")
    if not pmids:
        sys.exit("PubMed returned no papers at all, which is unexpected. Nothing was changed.")

    added = 0
    if new_pmids:
        summaries = get_json(EUTILS + "esummary.fcgi?db=pubmed&retmode=json&id=" + ",".join(new_pmids))["result"]
        for pmid in new_pmids:
            r = summaries.get(pmid, {})
            title = str(r.get("title", "")).rstrip(".")
            if not title or key(title) in skip:
                continue
            doi = next((a["value"] for a in r.get("articleids", []) if a.get("idtype") == "doi"), None)

            match = None
            for p in pubs:
                if (doi and str(p.get("doi", "")).lower() == doi.lower()) or same_title(key(p["title"]), key(title)):
                    match = p
                    break
            if match is not None:  # already listed, for example added by hand
                match["pmid"] = pmid
                if doi and not match.get("doi"):
                    match["doi"] = doi
                continue

            date = str(r.get("sortpubdate", ""))[:10].replace("/", "-")
            entry = {
                "title": title,
                "author": ", ".join(a["name"] for a in r.get("authors", [])),
                "journal": r.get("fulljournalname", ""),
                "year": int(date[:4]),
                "date": date,
                "pmid": pmid,
            }
            if doi:
                entry["doi"] = doi
            entry["url"] = f"https://doi.org/{doi}" if doi else f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/"
            pubs.append(entry)
            added += 1
            print("New:", title)

    # 2. Open-access PDF links from OpenAlex. Failures here are skipped.
    for p in pubs:
        if not p.get("doi") or p.get("pdf") or p.get("oa_url"):
            continue
        try:
            w = get_json("https://api.openalex.org/works/doi:" + urllib.parse.quote(str(p["doi"])) + "?select=best_oa_location,open_access")
        except Exception:
            continue
        pdf = (w.get("best_oa_location") or {}).get("pdf_url")
        oa = w.get("open_access") or {}
        if pdf:
            p["pdf"] = pdf
        elif oa.get("is_oa") and oa.get("oa_url"):
            p["oa_url"] = oa["oa_url"]
        time.sleep(0.2)

    pubs.sort(key=lambda p: str(p.get("date", "1900-01-01")), reverse=True)
    after = yaml.safe_dump(pubs, allow_unicode=True, sort_keys=False)
    if after != before:
        PUBS_FILE.write_text("\n".join(header) + "\n" + yaml.safe_dump(pubs, allow_unicode=True, sort_keys=False, width=1000), encoding="utf-8")
    print(f"Done. {added} new paper(s); {len(pubs)} in total.")


if __name__ == "__main__":
    main()
