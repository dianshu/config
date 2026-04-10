#!/usr/bin/env python3
"""Citation verification: hallucination pattern detection + URL reachability."""
import json
import re
import sys
from dataclasses import dataclass
from datetime import UTC, datetime

import requests

GENERIC_TITLES = re.compile(
    r"(?i)^(a study of|recent advances in|a comprehensive (review|survey|analysis) of|"
    r"towards|an overview of|a novel approach)"
)
ANACHRONISTIC_TERMS = re.compile(r"(?i)(llm|gpt|transformer|chatgpt|claude|copilot)")


@dataclass
class CitationEntry:
    title: str
    url: str
    date: str | None
    doi: str | None = None


def check_hallucination_patterns(entry: CitationEntry) -> list[str]:
    """Check a single citation for hallucination patterns. Returns list of issues."""
    issues = []

    if GENERIC_TITLES.search(entry.title):
        issues.append(f"Generic academic title pattern: '{entry.title[:60]}...'")

    if entry.date:
        try:
            pub_year = int(entry.date[:4])
            current_year = datetime.now(UTC).year
            if pub_year > current_year:
                issues.append(f"Future publication year: {pub_year}")
            if pub_year < 2017 and ANACHRONISTIC_TERMS.search(entry.title):
                issues.append("Anachronistic: pre-2017 paper mentions modern AI terms")
        except (ValueError, TypeError):
            pass

    if not entry.url and not entry.doi:
        issues.append("Entry has neither URL nor DOI")

    return issues


def check_url_reachability(url: str, timeout: int = 10) -> dict:
    """Check if a URL is reachable. Returns {"reachable": bool, "status": int|None}."""
    if not url:
        return {"reachable": False, "status": None}
    try:
        resp = requests.head(
            url,
            timeout=timeout,
            allow_redirects=True,
            headers={"User-Agent": "Mozilla/5.0 (research-validator)"},
        )
        return {"reachable": resp.status_code < 400, "status": resp.status_code}
    except requests.RequestException:
        return {"reachable": False, "status": None}


def verify_citations(entries: list[CitationEntry], check_urls: bool = False) -> dict:
    """Verify a list of citations. Returns summary with per-entry results."""
    results = []
    for entry in entries:
        issues = check_hallucination_patterns(entry)
        url_check = (
            check_url_reachability(entry.url)
            if check_urls and entry.url
            else None
        )
        if url_check and not url_check["reachable"]:
            issues.append(f"URL unreachable (status: {url_check['status']})")
        results.append({
            "title": entry.title,
            "url": entry.url,
            "issues": issues,
            "suspicious": len(issues) > 0,
        })
    suspicious_count = sum(1 for r in results if r["suspicious"])
    return {
        "total": len(entries),
        "suspicious": suspicious_count,
        "clean": len(entries) - suspicious_count,
        "pass": suspicious_count <= len(entries) * 0.5,
        "entries": results,
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: verify_citations.py <sources.json> [--check-urls]")
        sys.exit(1)
    with open(sys.argv[1]) as f:
        sources = json.load(f)
    entries = [
        CitationEntry(
            title=s.get("title", ""),
            url=s.get("url", ""),
            date=s.get("date") or s.get("accessed"),
            doi=s.get("doi"),
        )
        for s in sources
    ]
    result = verify_citations(entries, check_urls="--check-urls" in sys.argv)
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["pass"] else 1)
