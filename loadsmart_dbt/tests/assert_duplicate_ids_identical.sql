-- WARN: raw ids whose duplicated rows are NOT identical in every column.
-- Proves that the arbitrary pick made by DISTINCT ON in stg_loads is harmless.
{{ config(severity='warn') }}

select
    nullif(trim(t.loadsmart_id), '')  as loadsmart_id,
    count(*)                          as copies,
    count(distinct t::text)           as distinct_versions
from {{ source('raw', 'loads') }} t
where nullif(trim(t.loadsmart_id), '') is not null
group by nullif(trim(t.loadsmart_id), '')
having count(*) > 1
   and count(distinct t::text) > 1
