-- tests/assert_raw_lane_format.sql
-- WARN: raw.loads rows whose lane is not in the format "City,ST -> City,ST".
-- Same rule used by stg_loads.lane_format_invalid_flag, applied directly to the raw table.
{{ config(severity='warn') }}

with parsed as (
    select
        loadsmart_id,
        lane,
        trim(split_part(trim(lane), ' -> ', 1)) as pickup_part,
        trim(split_part(trim(lane), ' -> ', 2)) as delivery_part
    from {{ source('raw', 'loads') }}
),

split as (
    select
        loadsmart_id,
        lane,
        trim(split_part(pickup_part, ',', 1))          as pickup_city,
        upper(trim(split_part(pickup_part, ',', 2)))   as pickup_state,
        trim(split_part(delivery_part, ',', 1))        as delivery_city,
        upper(trim(split_part(delivery_part, ',', 2))) as delivery_state
    from parsed
)

select
    loadsmart_id,
    lane,
    pickup_city,
    pickup_state,
    delivery_city,
    delivery_state,
    case
        when lane is null or trim(lane) = ''         then 'lane is null or blank'
        when trim(lane) not like '% -> %'            then 'missing " -> " separator'
        when pickup_city = '' or delivery_city = ''  then 'empty city'
        when pickup_state   !~ '^[A-Z]{2}$'          then 'pickup state is not 2 letters'
        when delivery_state !~ '^[A-Z]{2}$'          then 'delivery state is not 2 letters'
    end as problem
from split
where lane is null
   or trim(lane) = ''
   or trim(lane) not like '% -> %'
   or pickup_city = '' or delivery_city = ''
   or pickup_state   !~ '^[A-Z]{2}$'
   or delivery_state !~ '^[A-Z]{2}$'
    or coalesce(pickup_city,    '')  ~ '[0-9]'
    or coalesce(delivery_city,  '')  ~ '[0-9]'
    or coalesce(pickup_city,   '') = ''
    or coalesce(delivery_city, '') = ''