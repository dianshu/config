#!/usr/bin/env python3
"""Tests for verify_citations.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from verify_citations import CitationEntry, check_hallucination_patterns


def test_generic_title_flagged():
    entry = CitationEntry(
        title="A Study of Machine Learning Approaches", url="", date=None
    )
    issues = check_hallucination_patterns(entry)
    assert len(issues) > 0, "Generic title should be flagged"


def test_future_date_flagged():
    entry = CitationEntry(
        title="Real Paper", url="https://example.com", date="2030-01-01"
    )
    issues = check_hallucination_patterns(entry)
    assert any("future" in i.lower() for i in issues)


def test_normal_entry_clean():
    entry = CitationEntry(
        title="FastMCP: A Python framework for MCP servers",
        url="https://github.com/jlowin/fastmcp",
        date="2026-03-15",
    )
    issues = check_hallucination_patterns(entry)
    assert len(issues) == 0, f"Clean entry should have no issues, got: {issues}"


def test_no_url_no_doi_flagged():
    entry = CitationEntry(title="Some Paper", url="", date="2025-01-01")
    issues = check_hallucination_patterns(entry)
    assert any("neither URL nor DOI" in i for i in issues)


if __name__ == "__main__":
    test_generic_title_flagged()
    test_future_date_flagged()
    test_normal_entry_clean()
    test_no_url_no_doi_flagged()
    print("All verify_citations tests passed.")