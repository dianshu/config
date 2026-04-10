#!/usr/bin/env python3
"""9-point structural validation for research reports."""
import re
import sys


def validate_report(content: str) -> dict:
    """Run 9 structural checks on a report.

    Returns dict with valid, errors, warnings keys.
    """
    errors = []
    warnings = []
    lines = content.strip().split("\n")

    # 1. Has a title/heading
    if not lines or not lines[0].startswith("#"):
        errors.append("Check 1: Report has no title heading")

    # 2. Executive summary exists and is 200-400 words
    summary_match = re.search(
        r"(?i)##\s*executive\s+summary\s*\n(.*?)(?=\n##\s|\Z)",
        content,
        re.DOTALL,
    )
    if not summary_match:
        errors.append(
            "Check 2: Missing Executive Summary section"
        )
    else:
        wc = len(summary_match.group(1).split())
        if wc < 200:
            errors.append(
                f"Check 2: Executive Summary too short"
                f" ({wc} words, need 200+)"
            )
        elif wc > 400:
            warnings.append(
                f"Check 2: Executive Summary long"
                f" ({wc} words, target 200-400)"
            )

    # 3. Expected sections present
    headings = re.findall(
        r"^##\s+(.+)", content, re.MULTILINE
    )
    heading_lower = [h.lower().strip() for h in headings]
    intro_kw = ("introduction", "背景")
    end_kw = ("conclusion", "结论", "summary", "总结")
    if not any(
        any(k in h for k in intro_kw)
        for h in heading_lower
    ):
        warnings.append(
            "Check 3: Missing Introduction section"
        )
    if not any(
        any(k in h for k in end_kw)
        for h in heading_lower
    ):
        warnings.append(
            "Check 3: Missing Conclusion section"
        )

    # 4. Citations with matching bibliography
    citations = set(re.findall(r"\[(\d+)\]", content))
    bib_pat = (
        r"(?i)##\s*(bibliography|references|参考文献)"
        r"\s*\n(.*)"
    )
    bib_section = re.search(bib_pat, content, re.DOTALL)
    if bib_section:
        bib_entries = set(
            re.findall(
                r"^\[(\d+)\]",
                bib_section.group(2),
                re.MULTILINE,
            )
        )
    else:
        bib_entries = set()
        if citations:
            errors.append(
                "Check 4: Citations found but no"
                " Bibliography section"
            )

    # 5. No placeholder text
    placeholders = re.findall(
        r"(?i)\b(TBD|TODO|FIXME|fill in|add later)\b",
        content,
    )
    if placeholders:
        joined = ", ".join(set(placeholders))
        errors.append(
            f"Check 5: Placeholder text: {joined}"
        )

    # 6. No truncation patterns
    truncation = re.findall(
        r"(?i)(content continues|due to length"
        r"|sections? \d+-\d+|additional citations)",
        content,
    )
    if truncation:
        joined = ", ".join(set(truncation))
        errors.append(
            f"Check 6: Truncation patterns: {joined}"
        )

    # 7. Word count >= 500
    word_count = len(content.split())
    if word_count < 500:
        errors.append(
            f"Check 7: Report too short"
            f" ({word_count} words, need 500+)"
        )

    # 8. Minimum 5 sources
    src_count = max(len(bib_entries), len(citations))
    if src_count < 5:
        errors.append(
            f"Check 8: Too few sources"
            f" ({src_count}, need 5+)"
        )

    # 9. No orphan citations
    if citations and bib_entries:
        orphan_cite = citations - bib_entries
        orphan_bib = bib_entries - citations
        if orphan_cite:
            errors.append(
                "Check 9: Citations without bib"
                f" entry: {orphan_cite}"
            )
        if orphan_bib:
            warnings.append(
                "Check 9: Bib entries never"
                f" cited: {orphan_bib}"
            )

    return {
        "valid": len(errors) == 0,
        "errors": errors,
        "warnings": warnings,
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: validate_report.py <report.md>")
        sys.exit(1)
    with open(sys.argv[1]) as f:
        content = f.read()
    result = validate_report(content)
    for e in result["errors"]:
        print(f"ERROR: {e}")
    for w in result["warnings"]:
        print(f"WARN: {w}")
    status = "PASS" if result["valid"] else "FAIL"
    print(f"\nResult: {status}")
    sys.exit(0 if result["valid"] else 1)
