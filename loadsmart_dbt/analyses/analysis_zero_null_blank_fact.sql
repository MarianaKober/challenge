with report as (
    {{ zero_null_blank_report(ref('fact_load'), 'loadsmart_id') }}
)
select *, cardinality(problem_columns) as n_problems
from report
where cardinality(problem_columns) > 0
order by n_problems desc, loadsmart_id