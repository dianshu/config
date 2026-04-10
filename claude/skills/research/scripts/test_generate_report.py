#!/usr/bin/env python3
"""Tests for generate_report.py"""
import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))

from generate_report import generate_comparison_report


def test_comparison_report():
    tmpdir = tempfile.mkdtemp()
    try:
        data_dir = os.path.join(tmpdir, "data")
        os.makedirs(data_dir)
        for name in ["alpha", "beta"]:
            path = os.path.join(data_dir, f"{name}.json")
            with open(path, "w") as f:
                json.dump(
                    {
                        "entity": name.capitalize(),
                        "fields": {
                            "stars": {
                                "value": (
                                    "100"
                                    if name == "alpha"
                                    else "200"
                                ),
                                "sources": [
                                    "https://example.com"
                                ],
                                "uncertain": False,
                            },
                            "license": {
                                "value": "MIT",
                                "sources": [
                                    "https://example.com"
                                ],
                                "uncertain": False,
                            },
                        },
                        "sources": [
                            {
                                "url": "https://example.com",
                                "title": f"{name} source",
                                "accessed": "2026-04-10",
                            }
                        ],
                    },
                    f,
                )

        tpl_dir = os.path.join(
            os.path.dirname(__file__), "..", "templates"
        )
        report = generate_comparison_report(
            topic="Alpha vs Beta",
            data_dir=data_dir,
            templates_dir=tpl_dir,
            field_names=["stars", "license"],
        )
        assert "Alpha vs Beta" in report
        assert "Alpha" in report
        assert "Beta" in report
        assert "MIT" in report
    finally:
        shutil.rmtree(tmpdir)


if __name__ == "__main__":
    test_comparison_report()
    print("All generate_report tests passed.")
