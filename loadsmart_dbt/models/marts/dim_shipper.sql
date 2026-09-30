select shipper_id, shipper_name
from {{ ref('int_loads_unique') }}
group by shipper_id, shipper_name