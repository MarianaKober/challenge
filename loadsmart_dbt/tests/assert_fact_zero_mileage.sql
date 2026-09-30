{{ config(severity='warn') }}
select
    loadsmart_id,
    lane_id,
    load_was_cancelled,
    mileage,
    mileage_unresolved_flag
from {{ ref('fact_load') }}
where coalesce(mileage, 0) = 0