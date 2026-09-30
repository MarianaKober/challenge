-- Outlier bounds and the loads flagged by them (one row per load and metric).
-- Flags never change or remove values; this is the list to review before choosing outliers_mode.
{% set metrics = ['book_price', 'source_price', 'pnl'] %}
with bounds as (
    select * from {{ ref('int_price_outlier_bounds') }}
),
flagged as (
    {%- for m in metrics %}
    select
        f.loadsmart_id,
        '{{ m }}'::text as metric,
        f.{{ m }}       as value,
        b.{{ m }}_lower as lower_bound,
        b.{{ m }}_upper as upper_bound,
        b.{{ m }}_n     as n_non_zero_used_for_bounds,
        case when f.{{ m }} < b.{{ m }}_lower then 'below' else 'above' end as side,
        f.lane_id,
        f.load_was_cancelled
    from {{ ref('fact_load') }} f
    cross join bounds b
    where f.{{ m }}_outlier_flag
    {%- if not loop.last %}
    union all
    {%- endif %}
    {%- endfor %}
)
select
    fl.loadsmart_id,
    fl.metric,
    fl.value,
    fl.lower_bound,
    fl.upper_bound,
    fl.side,
    fl.n_non_zero_used_for_bounds,
    l.lane,
    fl.load_was_cancelled
from flagged fl
left join {{ ref('dim_lane') }} l using (lane_id)
order by fl.metric, fl.side, abs(fl.value) desc
