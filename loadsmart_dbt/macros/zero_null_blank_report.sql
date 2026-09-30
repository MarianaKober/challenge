{% macro zero_null_blank_report(relation, id_columns, exclude=[]) -%}
{%- set cols = adapter.get_columns_in_relation(relation) -%}
select
    {{ id_columns }},
    array_remove(array[
        {%- for c in cols if c.name not in exclude %}
        {%- if c.is_string() %}
        case when "{{ c.name }}" is null then '{{ c.name }}:null'
             when trim("{{ c.name }}") = '' then '{{ c.name }}:blank' end
        {%- elif c.is_number() %}
        case when "{{ c.name }}" is null then '{{ c.name }}:null'
             when "{{ c.name }}" = 0 then '{{ c.name }}:zero' end
        {%- else %}
        case when "{{ c.name }}" is null then '{{ c.name }}:null' end
        {%- endif %}{{ "," if not loop.last }}
        {%- endfor %}
    ]::text[], null) as problem_columns
from {{ relation }}
{%- endmacro %}