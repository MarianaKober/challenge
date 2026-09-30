-- Loads left out of fact_load, by exclusion reason (set in int_loads_unique.fact_exclusion_reasons).
-- A load can have more than one reason, so the reasons can add up to more than the distinct total.
select
    reason,
    count(*) as loads_excluded
from {{ ref('int_loads_unique') }},
     unnest(fact_exclusion_reasons) as reason
where exclude_from_fact_flag
group by reason

union all

select
    'any reason (distinct loads)' as reason,
    count(*)                      as loads_excluded
from {{ ref('int_loads_unique') }}
where exclude_from_fact_flag

order by loads_excluded desc
