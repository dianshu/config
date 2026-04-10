# Evaluation Report: {{ topic }}

## Executive Summary

{{ executive_summary }}

## Scorecard

| Dimension | Score | Assessment |
|---|---|---|
{% for dim in dimensions %}
| {{ dim.name }} | {{ dim.score }}/100 | {{ dim.assessment }} |
{% endfor %}

**Overall Score: {{ overall_score }}/100**

{% for dim in dimensions %}
## {{ dim.name }}

{{ dim.details }}

{% endfor %}

## Risk Assessment

{{ risk_assessment }}

## Verdict: {{ verdict }}

{{ verdict_rationale }}

## Alternatives Considered

{{ alternatives }}

## Bibliography

{% for source in sources %}
[{{ loop.index }}] {{ source.title }}. {{ source.url }}
{% endfor %}
