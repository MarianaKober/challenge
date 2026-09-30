-- Data-quality counts per lane, over the loads that are in fact_load.
-- Reads int_loads_unique because the date-order flags and the mileage flags are not columns of fact_load.
with f as (
    select
        i.*,
        (i.zero_entry_count > 0 or i.date_order_flag_count > 0) as any_quality_issue_flag
    from {{ ref('int_loads_unique') }} i
    where not i.exclude_from_fact_flag
)
select
    l.lane,
    count(*)                                                  as loads_total,

    -- zeros
    count(*) filter (where f.zero_book_price_flag)            as zero_book_price,
    count(*) filter (where f.zero_source_price_flag)          as zero_source_price,
    count(*) filter (where f.zero_pnl_flag)                   as zero_pnl,
    count(*) filter (where f.zero_mileage_flag)               as zero_mileage,
    count(*) filter (where f.mileage_imputed_flag)            as mileage_imputed,
    count(*) filter (where f.mileage_unresolved_flag)         as mileage_unresolved,
    sum(f.zero_entry_count)                                   as zero_entries_total,

    -- date order (pickup_after_delivery is always 0 here: those loads are excluded from the fact)
    count(*) filter (where f.quote_after_book_flag)           as quote_after_book,
    count(*) filter (where f.quote_after_source_flag)         as quote_after_source,
    count(*) filter (where f.book_after_pickup_flag)          as book_after_pickup,
    count(*) filter (where f.quote_after_pickup_flag)         as quote_after_pickup,
    count(*) filter (where f.source_after_pickup_flag)        as source_after_pickup,
    count(*) filter (where f.pickup_after_delivery_flag)      as pickup_after_delivery,
    count(*) filter (where f.book_after_source_flag)          as book_after_source,
    count(*) filter (where f.quote_after_delivery_flag)       as quote_after_delivery,
    count(*) filter (where f.book_after_delivery_flag)        as book_after_delivery,
    count(*) filter (where f.source_after_delivery_flag)      as source_after_delivery,
    sum(f.date_order_flag_count)                              as date_order_mismatches_total,

    -- consolidated
    sum(f.zero_entry_count + f.date_order_flag_count)         as mismatches_and_zeros_total,
    count(*) filter (where f.any_quality_issue_flag)          as loads_with_any_error,
    round(100.0 * count(*) filter (where f.any_quality_issue_flag) / count(*), 2)
                                                              as pct_loads_with_error
from f
join {{ ref('dim_lane') }} l using (lane_id)
group by l.lane
order by loads_with_any_error desc, loads_total desc
