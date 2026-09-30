{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set base = (custom_schema_name | trim) if custom_schema_name is not none else target.schema -%}
    {%- if target.name == 'ci' -%}
        {{ target.schema }}_{{ base }}
    {%- else -%}
        {{ base }}
    {%- endif -%}
{%- endmacro %}