#!/usr/bin/env python3
"""Tests for validate_json.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from validate_json import validate_entity_json

FIELDS_YAML = {
    "categories": [{
        "name": "Core",
        "fields": [
            {"name": "stars", "description": "GitHub stars", "detail_level": "brief"},
            {"name": "license", "description": "License type", "detail_level": "brief"},
        ]
    }]
}

def test_valid_json():
    data = {
        "entity": "TestProject",
        "fields": {
            "stars": {
                "value": "1234",
                "sources": ["https://github.com/test"],
                "uncertain": False
            },
            "license": {
                "value": "MIT",
                "sources": ["https://github.com/test"],
                "uncertain": False
            },
        },
        "uncertain_fields": [],
        "sources": [
            {
                "url": "https://github.com/test",
                "title": "Test",
                "accessed": "2026-04-10"
            }
        ],
    }
    result = validate_entity_json(data, FIELDS_YAML)
    assert result["valid"], f"Expected valid, got errors: {result['errors']}"
    assert result["coverage"] == 1.0

def test_missing_field():
    data = {
        "entity": "TestProject",
        "fields": {
            "stars": {
                "value": "1234",
                "sources": ["https://github.com/test"],
                "uncertain": False
            },
        },
        "uncertain_fields": [],
        "sources": [],
    }
    result = validate_entity_json(data, FIELDS_YAML)
    assert not result["valid"]
    assert result["coverage"] < 1.0
    assert any("license" in e for e in result["errors"])

def test_uncertain_field():
    data = {
        "entity": "TestProject",
        "fields": {
            "stars": {"value": "[uncertain]", "sources": [], "uncertain": True},
            "license": {
                "value": "MIT",
                "sources": ["https://github.com/test"],
                "uncertain": False
            },
        },
        "uncertain_fields": ["stars"],
        "sources": [],
    }
    result = validate_entity_json(data, FIELDS_YAML)
    assert result["valid"]
    assert len(result["warnings"]) > 0

if __name__ == "__main__":
    test_valid_json()
    test_missing_field()
    test_uncertain_field()
    print("All validate_json tests passed.")