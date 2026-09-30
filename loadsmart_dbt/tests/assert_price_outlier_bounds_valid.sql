-- ERROR: int_price_outlier_bounds must be usable: quantiles ordered inside (0, 1),
-- bounds not NULL, lower <= upper, and at least one non-zero value behind each metric.
{% set metrics = ['book_price', 'source_price', 'pnl'] %}
select *
from {{ ref('int_price_outlier_bounds') }}
where lower_quantile < 0
   or upper_quantile > 1
   or lower_quantile >= upper_quantile
   {%- for m in metrics %}
   or {{ m }}_n = 0
   or {{ m }}_lower is null
   or {{ m }}_upper is null
   or {{ m }}_lower > {{ m }}_upper
   {%- endfor %}
