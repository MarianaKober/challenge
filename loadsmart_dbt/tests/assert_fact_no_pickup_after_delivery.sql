-- ERROR (guard): fact_load must not contain loads with pickup_date after delivery_date.
-- Those loads are excluded in int_loads_unique with reason pickup_after_delivery.
select
    loadsmart_id,
    pickup_date,
    delivery_date
from {{ ref('fact_load') }}
where pickup_date > delivery_date
