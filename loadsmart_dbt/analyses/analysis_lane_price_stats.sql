-- Price statistics per lane.
--   * zeros and NULLs are ignored (nonzero_stats)
--   * loads with price_analysis_exclude_flag are left out of every price metric
--   * var outliers_mode = 'exclude' also drops the metric's outlier flag
--     (dbt compile --select analysis_lane_price_stats --vars '{outliers_mode: exclude}')
with base as (
    select
        f.lane_id,
        f.book_price_outlier_flag,
        f.source_price_outlier_flag,
        f.pnl_outlier_flag,
        case when not f.price_analysis_exclude_flag then f.book_price         end as book_price,
        case when not f.price_analysis_exclude_flag then f.source_price       end as source_price,
        case when not f.price_analysis_exclude_flag then f.pnl                end as pnl,
        case when not f.price_analysis_exclude_flag then f.book_price_per_mile end as book_price_per_mile
    from {{ ref('fact_load') }} f
)
select
    l.lane,
    count(*) as loads_total,
    {{ nonzero_stats('b.book_price', 'book_price', 'b.book_price_outlier_flag') }},
    {{ nonzero_stats('b.source_price', 'source_price', 'b.source_price_outlier_flag') }},
    {{ nonzero_stats('b.pnl', 'pnl', 'b.pnl_outlier_flag') }},
    {{ nonzero_stats('b.book_price_per_mile', 'book_per_mile', 'b.book_price_outlier_flag') }}
from base b
join {{ ref('dim_lane') }} l using (lane_id)
group by l.lane
order by loads_total desc
