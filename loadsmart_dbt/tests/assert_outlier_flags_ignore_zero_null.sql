-- ERROR: an outlier flag can never be true on a zero or NULL value.
select
    loadsmart_id,
    book_price, book_price_outlier_flag,
    source_price, source_price_outlier_flag,
    pnl, pnl_outlier_flag
from {{ ref('fact_load') }}
where (book_price_outlier_flag   and coalesce(book_price, 0)   = 0)
   or (source_price_outlier_flag and coalesce(source_price, 0) = 0)
   or (pnl_outlier_flag          and coalesce(pnl, 0)          = 0)
