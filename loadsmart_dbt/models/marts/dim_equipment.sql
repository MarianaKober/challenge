select distinct equipment_id, equipment_type
from {{ ref('int_loads_unique') }}
where equipment_type is not null
and  not exclude_from_fact_flag