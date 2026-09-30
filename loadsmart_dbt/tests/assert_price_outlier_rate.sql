-- WARN: share of flagged loads per metric, over the loads with a non-zero value.
-- With P1/P99 bounds about 2% is expected. Warns at 0% (flags not working) or above
-- var outlier_rate_warn_max (default 4%; bounds ignore excluded loads, so the fact can flag a bit more).
{{ config(severity='warn') }}
{% set metrics = ['book_price', 'source_price', 'pnl'] %}
with rates as (
    {%- for m in metrics %}
    select
        '{{ m }}'::text                                      as metric,
        count(*) filter (where coalesce({{ m }}, 0) <> 0)    as n_non_zero,
        count(*) filter (where {{ m }}_outlier_flag)         as n_flagged
    from {{ ref('fact_load') }}
    {%- if not loop.last %}
    union all
    {%- endif %}
    {%- endfor %}
)
select
    metric,
    n_non_zero,
    n_flagged,
    round(n_flagged::numeric / nullif(n_non_zero, 0), 4) as flagged_share
from rates
where n_flagged = 0
   or n_flagged::numeric / nullif(n_non_zero, 0) > {{ var('outlier_rate_warn_max', 0.04) }}
