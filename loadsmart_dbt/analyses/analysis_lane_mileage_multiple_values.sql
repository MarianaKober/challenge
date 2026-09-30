with base as (
    select l.lane, f.mileage
    from {{ ref('fact_load') }} f
    join {{ ref('dim_lane') }} l using (lane_id)
    where f.load_was_cancelled is false
      and f.mileage is not null
),
counts as (
    select lane, mileage, count(*) as freq
    from base
    group by lane, mileage
),
agg as (
    select
        lane,
        array_agg(mileage order by mileage) filter (where mileage <> 0)              as mileage_values,
        count(*) filter (where mileage <> 0)                                         as n_values,
        jsonb_object_agg(mileage::text, freq order by mileage) filter (where mileage <> 0) as value_counts,
        sum(freq)                                                                    as total_count,
        coalesce(bool_or(mileage = 0), false)                                        as has_zero,
        max(mileage) filter (where mileage <> 0)
          - min(mileage) filter (where mileage <> 0)                                 as spread
    from counts
    group by lane
)
select lane, mileage_values, n_values, value_counts, total_count, has_zero, spread
from agg
where n_values > 1
  and spread > {{ var('mileage_spread_threshold') }}
order by spread desc