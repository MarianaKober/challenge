select
    carrier_id,
    carrier_name
from {{ ref('int_loads_unique') }}
group by carrier_id, carrier_name