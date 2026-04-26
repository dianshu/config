# {{ topic }}

## Executive Summary

{{ executive_summary }}

## Comparison Overview

{{ comparison_table }}

{% for dimension in dimensions %}
## {{ dimension.name }}

{% for entity in entities %}
### {{ entity.name }}

{{ entity.fields[dimension.field_name].value }}

{% endfor %}
{% endfor %}

## Recommendation

{{ recommendation }}

## Bibliography

{% for source in sources %}
[{{ loop.index }}] {{ source.title }}. {{ source.url }}
{% endfor %}
