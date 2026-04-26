#!/usr/bin/env python3
"""Tests for validate_report.py"""
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))

from validate_report import validate_report

FIXTURES = Path(__file__).parent / "test_fixtures"


def _load_fixture(name: str) -> str:
    return (FIXTURES / name).read_text()


def test_good_report_passes():
    report = _load_fixture("good_report.md")
    result = validate_report(report)
    assert result["valid"], (
        f"Good report should pass: {result['errors']}"
    )


def test_missing_summary_fails():
    report = (
        "# Report\n\n"
        "## Introduction\n\n"
        "Some content here.\n"
    )
    result = validate_report(report)
    assert not result["valid"]
    assert any(
        "executive summary" in e.lower()
        for e in result["errors"]
    )


def test_placeholder_fails():
    report = _load_fixture("good_report.md")
    report += "\n\nTODO: add more content\n"
    result = validate_report(report)
    assert not result["valid"]
    assert any(
        "placeholder" in e.lower()
        for e in result["errors"]
    )


if __name__ == "__main__":
    test_good_report_passes()
    test_missing_summary_fails()
    test_placeholder_fails()
    print("All validate_report tests passed.")
