#!/usr/bin/env python3
"""Tests for source_evaluator.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from source_evaluator import SourceEvaluator


def test_high_trust_academic():
    evaluator = SourceEvaluator()
    score = evaluator.evaluate(
        url="https://arxiv.org/abs/2401.12345",
        title="Attention Is All You Need",
        date="2026-01-15"
    )
    assert score["overall"] >= 80, f"Expected high_trust, got {score['overall']}"
    assert score["recommendation"] == "high_trust"

def test_low_trust_blog():
    evaluator = SourceEvaluator()
    score = evaluator.evaluate(
        url="https://myblog.blogspot.com/ai-thoughts",
        title="YOU WON'T BELIEVE This AI Trick!!!",
        date="2020-03-01"
    )
    assert score["overall"] < 60, f"Expected low_trust, got {score['overall']}"

def test_unknown_domain():
    evaluator = SourceEvaluator()
    score = evaluator.evaluate(
        url="https://randomsite.xyz/article",
        title="A balanced review of MCP protocol",
        date=None
    )
    assert 40 <= score["overall"] <= 70

def test_moderate_trust_stackoverflow():
    evaluator = SourceEvaluator()
    score = evaluator.evaluate(
        url="https://stackoverflow.com/questions/12345",
        title="How to use FastMCP with async handlers",
        date="2026-03-01"
    )
    assert score["recommendation"] in ("moderate_trust", "high_trust")

if __name__ == "__main__":
    test_high_trust_academic()
    test_low_trust_blog()
    test_unknown_domain()
    test_moderate_trust_stackoverflow()
    print("All source_evaluator tests passed.")