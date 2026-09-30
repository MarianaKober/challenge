with base as (
    select
        *,
        {{ dbt_utils.generate_surrogate_key(['shipper_name']) }}   as shipper_id,
        {{ dbt_utils.generate_surrogate_key(['carrier_name']) }}   as carrier_id,
        {{ dbt_utils.generate_surrogate_key(['equipment_type']) }} as equipment_id,
        {{ dbt_utils.generate_surrogate_key(
            ['pickup_city', 'pickup_state', 'delivery_city', 'delivery_state']) }} as lane_id
    from {{ ref('stg_loads') }}
),

lane_median as (
    select
        lane_id,
        round((percentile_cont(0.5) within group (order by mileage))::numeric, 2) as lane_median_mileage,
        count(*) as lane_nonzero_mileage_count
    from base
    where mileage > 0
      and load_was_cancelled is false
    group by lane_id
),

enriched as (
    select
        b.*,
        b.mileage as mileage_raw,
        case
            when b.zero_mileage_active_flag and m.lane_median_mileage is not null
                then m.lane_median_mileage
            else b.mileage
        end as mileage_final,
        (b.zero_mileage_active_flag and m.lane_median_mileage is not null) as mileage_imputed_flag,
        (b.zero_mileage_active_flag and m.lane_median_mileage is null)     as mileage_unresolved_flag,
        (b.date_order_flag_count > 0)                                      as any_date_order_flag,

        array_remove(array[
            case when b.pickup_gt_delivery_flag then 'pickup_after_delivery' end,
            case when b.lane_format_invalid_flag then 'lane_format_invalid' end
        ]::text[], null) as fact_exclusion_reasons
    from base b
    left join lane_median m using (lane_id)
)

select
    *,
    (cardinality(fact_exclusion_reasons) > 0) as exclude_from_fact_flag
from enriched