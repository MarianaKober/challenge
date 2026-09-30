with loads as (
    select * from {{ ref('int_loads_unique') }}
    where not exclude_from_fact_flag
),

bounds as (
    select * from {{ ref('int_price_outlier_bounds') }}
),

scored as (
    select
        l.loadsmart_id,

        l.shipper_id,
        l.carrier_id,
        l.lane_id,
        l.equipment_id,
     
        l.quote_date,
        l.book_date,
        l.source_date,
        l.pickup_date,
        l.delivery_date,

        l.book_price,
        l.source_price,
        l.pnl,
        l.pnl_calculated,
        l.mileage_final                                        as mileage,
        (l.book_price / nullif(l.mileage_final, 0))            as book_price_per_mile,

        l.sourcing_channel,
        l.load_booked_autonomously,
        l.load_sourced_autonomously,
        l.load_was_cancelled,
        (l.load_was_cancelled is false)                        as is_delivered,

        l.zero_book_price_flag,
        l.zero_source_price_flag,
        l.zero_pnl_flag,
        l.zero_mileage_flag,
        l.mileage_imputed_flag,
        l.mileage_unresolved_flag,
        l.pnl_mismatch_flag,
        l.cancelled_nonzero_price_flag,
        l.zero_price_active_flag,
        l.price_analysis_exclude_flag,

        -- zeros and NULLs are never flagged (bounds are also computed on non-zero values only)
        coalesce(l.book_price   <> 0 and (l.book_price   < b.book_price_lower   or l.book_price   > b.book_price_upper),   false) as book_price_outlier_flag,
        coalesce(l.source_price <> 0 and (l.source_price < b.source_price_lower or l.source_price > b.source_price_upper), false) as source_price_outlier_flag,
        coalesce(l.pnl          <> 0 and (l.pnl          < b.pnl_lower          or l.pnl          > b.pnl_upper),          false) as pnl_outlier_flag,

    
        l.zero_entry_count
    from loads l
    cross join bounds b
)

select
    s.*
from scored s