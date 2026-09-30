{{ config(severity='warn') }}
select loadsmart_id, book_price, source_price, pnl, pnl_calculated
from {{ ref('fact_load') }}
where pnl_mismatch_flag