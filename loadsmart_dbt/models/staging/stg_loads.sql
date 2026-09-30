with source as (
    select * from {{ source('raw', 'loads') }}
),

-- types, trims, drop columns
cleaned as (
    select
        nullif(trim(loadsmart_id), '')            as loadsmart_id,
        trim(lane)                                as lane,
        trim(split_part(lane, ' -> ', 1))         as pickup_part,
        trim(split_part(lane, ' -> ', 2))         as delivery_part,

        quote_date,
        book_date,
        source_date,
        pickup_date,
        delivery_date,

        -- zeros are kept as they come (no cast to NULL); zero_*_flag and price_analysis_exclude_flag track them
        book_price::numeric                       as book_price_raw,
        source_price::numeric                     as source_price_raw,
        pnl::numeric                              as pnl_raw,
        mileage::numeric                          as mileage,

        nullif(trim(equipment_type), '')          as equipment_type,
        carrier_rating,                           -- exceção: zero NÃO vira NULL
        nullif(trim(sourcing_channel), '')        as sourcing_channel,
        vip_carrier,
        carrier_dropped_us_count,
        trim(carrier_name)                        as carrier_name,
        trim(shipper_name)                        as shipper_name,

        carrier_on_time_to_pickup,
        carrier_on_time_to_delivery,
        carrier_on_time_overall,
        pickup_appointment_time,
        delivery_appointment_time,
        has_mobile_app_tracking,
        has_macropoint_tracking,
        has_edi_tracking,
        contracted_load,
        load_booked_autonomously,
        load_sourced_autonomously,
        load_was_cancelled
    from source
    where nullif(trim(loadsmart_id), '') is not null
),

-- lane
parsed as (
    select
        *,
        trim(split_part(pickup_part, ',', 1))            as pickup_city,
        upper(trim(split_part(pickup_part, ',', 2)))     as pickup_state,
        trim(split_part(delivery_part, ',', 1))          as delivery_city,
        upper(trim(split_part(delivery_part, ',', 2)))   as delivery_state
    from cleaned
),

-- flags
flagged as (
    select
        *,

        
        count(*) over (partition by loadsmart_id) as dup_id_copies,

       
        coalesce(quote_date  >  book_date,     false) as quote_after_book_flag,
        coalesce(quote_date  >  source_date,   false) as quote_after_source_flag,
        coalesce(book_date   > pickup_date,   false) as book_after_pickup_flag,
        coalesce(quote_date  > pickup_date,   false) as quote_after_pickup_flag,
        coalesce(source_date > pickup_date,   false) as source_after_pickup_flag,
        coalesce(pickup_date > delivery_date, false) as pickup_after_delivery_flag,
        coalesce(book_date   >  source_date,   false) as book_after_source_flag,
        coalesce(quote_date  > delivery_date, false) as quote_after_delivery_flag,
        coalesce(book_date   > delivery_date, false) as book_after_delivery_flag,
        coalesce(source_date > delivery_date, false) as source_after_delivery_flag,

        
        coalesce(pickup_date > delivery_date, false)  as pickup_gt_delivery_flag,

     
        coalesce(book_price_raw   = 0, false) as zero_book_price_flag,
        coalesce(source_price_raw = 0, false) as zero_source_price_flag,
        coalesce(pnl_raw          = 0, false) as zero_pnl_flag,
        coalesce(mileage          = 0, false) as zero_mileage_flag,
        coalesce(mileage = 0 and load_was_cancelled is false, false) as zero_mileage_active_flag,

        
        coalesce(load_was_cancelled
                 and (coalesce(book_price_raw, 0)   <> 0
                   or coalesce(source_price_raw, 0) <> 0
                   or coalesce(pnl_raw, 0)          <> 0), false) as cancelled_nonzero_price_flag,

        
        coalesce(load_was_cancelled is false
                 and (book_price_raw = 0 or source_price_raw = 0 or pnl_raw = 0), false)
                 as zero_price_active_flag,

        coalesce(lane not like '% -> %'
              or pickup_city   = '' 
              or pickup_state !~ '^[A-Z]{2}$' 
   or delivery_state !~ '^[A-Z]{2}$'
    or coalesce(pickup_city,    '')  ~ '[0-9]'
    or coalesce(delivery_city,  '')  ~ '[0-9]'
    or coalesce(pickup_city,   '') = ''
    or coalesce(delivery_city, '') = ''
              , true) as lane_format_invalid_flag,


        (pnl_raw is distinct from (book_price_raw - source_price_raw)) as pnl_mismatch_flag
    from parsed
)

-- 
select distinct on (f.loadsmart_id)
    f.*,
    (f.dup_id_copies > 1)                             as dup_id_flag,

    f.book_price_raw                      as book_price,
    f.source_price_raw                    as source_price,
    f.pnl_raw                             as pnl,
    f.book_price_raw - f.source_price_raw as pnl_calculated,

    (f.cancelled_nonzero_price_flag or f.zero_price_active_flag) as price_analysis_exclude_flag,

    (  f.quote_after_book_flag::int   + f.quote_after_source_flag::int
     + f.book_after_pickup_flag::int  + f.quote_after_pickup_flag::int
     + f.source_after_pickup_flag::int + f.pickup_after_delivery_flag::int
     + f.book_after_source_flag::int  + f.quote_after_delivery_flag::int
     + f.book_after_delivery_flag::int + f.source_after_delivery_flag::int
    ) as date_order_flag_count,

    (  f.zero_book_price_flag::int + f.zero_source_price_flag::int
     + f.zero_pnl_flag::int        + f.zero_mileage_flag::int
    ) as zero_entry_count
from flagged f
order by f.loadsmart_id