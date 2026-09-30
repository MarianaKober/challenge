{% macro outlier_clause(flag_column) -%}
    {%- if flag_column is not none and var('outliers_mode', 'include') == 'exclude' -%}
        and not coalesce({{ flag_column }}, false)
    {%- endif -%}
{%- endmacro %}