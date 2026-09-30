select 
    f.loadsmart_id, 
    l.lane,
    l.pickup_city,
    l.pickup_state,
    l.delivery_city,
    l.delivery_state
from {{ ref('fact_load') }} f
join {{ ref('dim_lane') }} l on f.lane_id = l.lane_id
where l.pickup_state !~ '^[A-Z]{2}$' 
   or l.delivery_state !~ '^[A-Z]{2}$'
    or coalesce(pickup_city,    '')  ~ '[0-9]'
    or coalesce(delivery_city,  '')  ~ '[0-9]'
    or coalesce(pickup_city,   '') = ''
    or coalesce(delivery_city, '') = ''