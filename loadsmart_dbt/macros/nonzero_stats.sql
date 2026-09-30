{% macro nonzero_stats(expr, alias, outlier_flag=none) -%}
    {#- outlier_flag: name of a boolean outlier column; rows flagged are skipped when var outliers_mode = 'exclude' -#}
    {%- set cond = expr ~ ' <> 0 ' ~ outlier_clause(outlier_flag) -%}
    count(*) filter (where {{ cond }})                          as {{ alias }}_n,
    min({{ expr }}) filter (where {{ cond }})                   as {{ alias }}_min,
    max({{ expr }}) filter (where {{ cond }})                   as {{ alias }}_max,
    round((avg({{ expr }}) filter (where {{ cond }}))::numeric, 2) as {{ alias }}_avg,
    round((percentile_cont(0.5) within group (order by {{ expr }})
           filter (where {{ cond }}))::numeric, 2)              as {{ alias }}_median
{%- endmacro %}
