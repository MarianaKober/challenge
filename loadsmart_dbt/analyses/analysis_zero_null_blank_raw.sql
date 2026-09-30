with report as (
    {{ zero_null_blank_report(source('raw', 'loads'), 'loadsmart_id, ctid::text as raw_row_ref') }}
)
select *, cardinality(problem_columns) as n_problems
from report
where cardinality(problem_columns) > 0
order by n_problems desc, loadsmart_id