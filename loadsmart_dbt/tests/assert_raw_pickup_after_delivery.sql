{{ config(severity='warn') }}

select
    loadsmart_id,
    lane,
    pickup_date,
    delivery_date,
    (delivery_date - pickup_date) as delivery_minus_pickup
from {{ source('raw', 'loads') }}
where pickup_date > delivery_date
order by delivery_date - pickup_date