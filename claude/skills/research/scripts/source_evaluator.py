#!/usr/bin/env python3
"""Source credibility scoring. Weighted average of 4 dimensions (0-100)."""
import re
from datetime import datetime, timezone
from urllib.parse import urlparse

HIGH_AUTHORITY = {
    "arxiv.org": 90, "nature.com": 90, "ieee.org": 90, "acm.org": 90,
    "nih.gov": 90, "docs.python.org": 90, "docs.microsoft.com": 90,
    "learn.microsoft.com": 90, "developer.mozilla.org": 90, "go.dev": 90,
    "docs.rs": 90, "reactjs.org": 90, "nextjs.org": 90,
}
MODERATE_AUTHORITY = {
    "stackoverflow.com": 70, "stackexchange.com": 70, "wikipedia.org": 70,
    "techcrunch.com": 70, "forbes.com": 70, "github.com": 70,
    "dev.to": 65, "hackernews.com": 65, "infoq.com": 70, "theregister.com": 70,
}
LOW_AUTHORITY = {
    "blogspot.com": 40, "wordpress.com": 40, "wix.com": 40,
    "substack.com": 45, "medium.com": 50, "csdn.net": 50, "juejin.cn": 50,
}
SENSATIONALIST = re.compile(
    r"(?i)(you won't believe|shocking|mind.?blowing|game.?changer|!!|clickbait)",
)
BALANCED = re.compile(
    r"(?i)(however|although|on the other hand|nevertheless|conversely)"
)
ACADEMIC_DOMAINS = {
    "arxiv.org", "nature.com", "ieee.org", "acm.org", "nih.gov", "scholar.google.com"
}


class SourceEvaluator:
    def evaluate(self, url: str, title: str = "", date: str | None = None) -> dict:
        domain = self._extract_domain(url)
        authority = self._domain_authority(domain)
        recency = self._recency_score(date)
        expertise = self._expertise_score(domain, title)
        bias = self._bias_score(domain, title)
        overall = round(
            authority * 0.35 + recency * 0.20 + expertise * 0.25 + bias * 0.20
        )
        recommendation = (
            "high_trust" if overall >= 80 else
            "moderate_trust" if overall >= 60 else
            "low_trust" if overall >= 40 else
            "verify"
        )
        return {
            "overall": overall,
            "domain_authority": authority,
            "recency": recency,
            "expertise": expertise,
            "bias": bias,
            "recommendation": recommendation,
        }

    def _extract_domain(self, url: str) -> str:
        parsed = urlparse(url)
        host = parsed.hostname or ""
        parts = host.split(".")
        if len(parts) >= 2:
            return ".".join(parts[-2:])
        return host

    def _domain_authority(self, domain: str) -> int:
        if domain in HIGH_AUTHORITY:
            return HIGH_AUTHORITY[domain]
        if domain in MODERATE_AUTHORITY:
            return MODERATE_AUTHORITY[domain]
        if domain in LOW_AUTHORITY:
            return LOW_AUTHORITY[domain]
        return 55

    def _recency_score(self, date: str | None) -> int:
        if not date:
            return 50
        try:
            pub = datetime.strptime(date[:10], "%Y-%m-%d").replace(tzinfo=timezone.utc)
            now = datetime.now(timezone.utc)
            days = (now - pub).days
            if days < 90:
                return 100
            if days < 365:
                return 85
            if days < 730:
                return 70
            if days < 1825:
                return 50
            return 30
        except (ValueError, TypeError):
            return 50

    def _expertise_score(self, domain: str, title: str) -> int:
        score = 50
        if domain in ACADEMIC_DOMAINS:
            score += 30
        elif domain.endswith(".gov"):
            score += 25
        elif "docs" in domain or "developer" in domain:
            score += 20
        if re.search(r"(?i)(ph\.?d|dr\.|professor|研究员)", title):
            score += 15
        return min(score, 100)

    def _bias_score(self, domain: str, title: str) -> int:
        score = 70
        if domain in ACADEMIC_DOMAINS:
            score += 20
        if SENSATIONALIST.search(title):
            score -= 10
        if BALANCED.search(title):
            score += 10
        return max(0, min(score, 100))


if __name__ == "__main__":
    import json
    import sys

    if len(sys.argv) < 2:
        print("Usage: source_evaluator.py <url> [title] [date]")
        sys.exit(1)
    e = SourceEvaluator()
    title = sys.argv[2] if len(sys.argv) > 2 else ""
    date = sys.argv[3] if len(sys.argv) > 3 else None
    result = e.evaluate(sys.argv[1], title, date)
    print(json.dumps(result, indent=2))