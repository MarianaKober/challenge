{% set metrics = ['book_price', 'source_price', 'pnl'] %}
{% set lo = var('outlier_lower_quantile', 0.01) %}
{% set hi = var('outlier_upper_quantile', 0.99) %}

with base as (
    select book_price, source_price, pnl
    from {{ ref('int_loads_unique') }}
    where not exclude_from_fact_flag
      and not price_analysis_exclude_flag
)

select
    {{ lo }}::numeric as lower_quantile,
    {{ hi }}::numeric as upper_quantile,
    {%- for m in metrics %}
    count(*) filter (where {{ m }} <> 0) as {{ m }}_n,
    (percentile_cont({{ lo }}) within group (order by {{ m }}) filter (where {{ m }} <> 0))::numeric as {{ m }}_lower,
    (percentile_cont({{ hi }}) within group (order by {{ m }}) filter (where {{ m }} <> 0))::numeric as {{ m }}_upper
    {{- "," if not loop.last }}
    {%- endfor %}
from base