{{ config(severity='warn') }}
select
    l.lane,
    count(distinct f.mileage)      as n_values,
    min(f.mileage)                 as min_mileage,
    max(f.mileage)                 as max_mileage,
    max(f.mileage) - min(f.mileage) as spread
from {{ ref('fact_load') }} f
join {{ ref('dim_lane') }} l using (lane_id)
where f.load_was_cancelled is false
  and f.mileage > 0
group by l.lane
having count(distinct f.mileage) > 1
   and max(f.mileage) - min(f.mileage) > {{ var('mileage_spread_threshold') }}