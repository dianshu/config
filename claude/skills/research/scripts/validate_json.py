#!/usr/bin/env python3
"""Validate entity JSON files against fields.yaml schema."""
import json
import sys

import yaml


def load_field_names(fields_yaml: dict) -> list[str]:
    """Extract all field names from fields.yaml structure."""
    names = []
    for category in fields_yaml.get("categories", []):
        for field in category.get("fields", []):
            names.append(field["name"])
    return names


def validate_entity_json(data: dict, fields_yaml: dict) -> dict:
    """Validate a single entity JSON against the fields schema.

    Returns: {"valid": bool, "coverage": float, "errors": list, "warnings": list}
    """
    errors = []
    warnings = []
    expected_fields = load_field_names(fields_yaml)

    if "entity" not in data:
        errors.append("Missing 'entity' key")
    if "fields" not in data:
        errors.append("Missing 'fields' key")
        return {
            "valid": False,
            "coverage": 0.0,
            "errors": errors,
            "warnings": warnings
        }

    present = 0
    for field_name in expected_fields:
        if field_name not in data["fields"]:
            errors.append(f"Missing field: {field_name}")
        else:
            entry = data["fields"][field_name]
            if entry.get("uncertain") or entry.get("value") == "[uncertain]":
                warnings.append(f"Uncertain value for field: {field_name}")
            present += 1

    coverage = present / len(expected_fields) if expected_fields else 1.0
    valid = len(errors) == 0
    return {
        "valid": valid,
        "coverage": coverage,
        "errors": errors,
        "warnings": warnings
    }


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: validate_json.py <entity.json> <fields.yaml>")
        sys.exit(1)
    with open(sys.argv[1]) as f:
        data = json.load(f)
    with open(sys.argv[2]) as f:
        fields = yaml.safe_load(f)
    result = validate_entity_json(data, fields)
    for e in result["errors"]:
        print(f"ERROR: {e}")
    for w in result["warnings"]:
        print(f"WARN: {w}")
    print(f"Coverage: {result['coverage']:.0%}")
    sys.exit(0 if result["valid"] else 1)