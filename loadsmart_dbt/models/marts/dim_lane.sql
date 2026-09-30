
with lanes as (
    select
        lane_id,
        min(lane) as lane,
        pickup_city,
        pickup_state,
        delivery_city,
        delivery_state
    from {{ ref('int_loads_unique') }}
    where not exclude_from_fact_flag
    group by lane_id, pickup_city, pickup_state, delivery_city, delivery_state
)

select
    l.lane_id,
    l.lane,

    l.pickup_city,
    l.pickup_state,
    pickup_states.state_name   as pickup_state_name,

    l.delivery_city,
    l.delivery_state,
    delivery_states.state_name as delivery_state_name,
    case
        when l.pickup_state = l.delivery_state then 'intrastate'
        else 'interstate'
    end as lane_type
from lanes l
left join {{ ref('state_names') }} pickup_states
       on pickup_states.state_code = l.pickup_state
left join {{ ref('state_names') }} delivery_states
       on delivery_states.state_code = l.delivery_state