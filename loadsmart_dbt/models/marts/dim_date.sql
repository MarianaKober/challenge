with bounds as (
    select
        min(least(quote_date, book_date, source_date, pickup_date, delivery_date))::date as min_d,
        max(greatest(quote_date, book_date, source_date, pickup_date, delivery_date))::date as max_d
    from {{ ref('int_loads_unique') }}
     where not exclude_from_fact_flag
),
spine as (
    select generate_series(min_d, max_d, interval '1 day')::date as date_day
    from bounds
)
select
    date_day,
    extract(year from date_day)::int  as year,
    extract(month from date_day)::int as month,
    to_char(date_day, 'YYYY-MM')      as year_month,
    extract(dow from date_day)::int   as day_of_week
from spine