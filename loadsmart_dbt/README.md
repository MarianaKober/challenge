# loadsmart_dbt

dbt project (Postgres) that turns the raw loads export into a star schema: `fact_load` plus five dimensions.

## Quickstart

```bash
pip install "dbt-core>=1.10,<2.0" "dbt-postgres>=1.10,<2.0"
dbt deps && dbt build
dbt docs generate && dbt docs serve
```

`dbt build` runs the seed, the models and the tests in dependency order. Prefer it over `dbt run && dbt test`.

---

## Connection

`profiles.yml` (project root) defines the profile `loadsmart_dbt` with three Postgres targets:

| Target | Database | Schema |
|---|---|---|
| `dev` (default) | `loadsmart_dev` | `analytics` |
| `ci` | `loadsmart_dev` | `DBT_CI_SCHEMA_PREFIX` (default `ci_local`) |
| `prod` | `loadsmart_prod` | `analytics` |

`macros/generate_schema_name.sql` uses the custom schema name as it is (`+schema: staging` creates a schema called
`staging`, not `analytics_staging`). Only the `ci` target prefixes it with the target schema. Environments are therefore
isolated by database, not by schema: never point two targets at the same database.

The source is the table `raw.loads` (see `models/staging/_staging_sources.yml`).

---

## Architecture

```
raw.loads (source)
    |
stg_loads               view,  schema staging       dedup, lane parsing, every quality flag
    |
int_loads_unique        view,  schema intermediate  keys, mileage imputation, fact exclusion reasons
int_price_outlier_bounds view, schema intermediate  p1 / p99 bounds (one row)
    |
fact_load, dim_*        table, schema analytics     business decisions applied
```

- **Staging** deduplicates (`DISTINCT ON loadsmart_id`), drops rows with a null or blank `loadsmart_id`, splits the lane
  into city and state, and computes all the flags. Values are not changed: zeros in `book_price`, `source_price` and
  `pnl` are kept (`book_price` = `book_price_raw`, and so on).
- **Intermediate** builds the surrogate keys, imputes mileage, and decides which loads leave the fact
  (`fact_exclusion_reasons`, `exclude_from_fact_flag`). It does not delete rows, so excluded loads stay in
  `int_loads_unique` for audit.
- **Marts** read the intermediate layer. `fact_load` keeps only loads with `exclude_from_fact_flag = false`; the
  dimensions are built from the same rows. Keys are `dbt_utils.generate_surrogate_key` hashes.

`dim_date` has no foreign key in `fact_load`. Join it on the date you mean:

```sql
select d.year_month, count(*)
from analytics.fact_load f
join analytics.dim_date d on f.delivery_date::date = d.date_day
where f.is_delivered
group by 1
order by 1;
```

---

## Data-quality decisions

The full trail (choice, reasoning, tests) is the spreadsheet *Post Data Quality Analysis - Decision Trail*. Summary:

| Topic | Decision | Where |
|---|---|---|
| Duplicate ids | One row per `loadsmart_id`; copies are identical, so the pick is arbitrary | `stg_loads` |
| `has_mobile_app_tracking_1` | Only in raw (Postgres rejects two columns with the same name) | raw |
| Constant / low-value columns | Nine columns stay in staging and are not carried to the fact (see below) | `stg_loads` -> `fact_load` |
| Missing values | Not imputed (except mileage 0); warn-level `not_null` tests; warning in the column descriptions | `fact_load` |
| Zero prices | Zeros **kept**, flagged (`zero_*_flag`); `price_analysis_exclude_flag` leaves them out of price statistics | `stg_loads`, `fact_load` |
| Cancelled load with a price | Flag `cancelled_nonzero_price_flag`; also in `price_analysis_exclude_flag` | `stg_loads`, `fact_load` |
| `pickup_date > delivery_date` | **Excluded** from the fact (reason `pickup_after_delivery`); strict `>`, equal timestamps stay | `int_loads_unique` |
| Other date-order anomalies | Ten flags, strict `>`; rows stay; flags are **not** in the fact | `stg_loads`, `int_loads_unique` |
| Lane out of format | **Excluded** from the fact (reason `lane_format_invalid`) | `int_loads_unique` |
| Mileage = 0 | Non-cancelled loads get the lane median (non-cancelled, mileage > 0); else `mileage_unresolved_flag` | `int_loads_unique` |
| Several mileages per lane | Report only (warn test, analysis, script) | tests / analyses / scripts |
| Price outliers | Flag only (p1 / p99 of non-zero values); zeros and NULLs never flagged | `int_price_outlier_bounds`, `fact_load` |
| `pnl` vs `book_price - source_price` | Flag `pnl_mismatch_flag`; nothing recalculated | `stg_loads`, `fact_load` |

**Dropped from the fact** (still in `stg_loads` and raw): `has_mobile_app_tracking`, `has_macropoint_tracking`,
`has_edi_tracking`, `contracted_load`, `carrier_on_time_to_pickup`, `carrier_on_time_to_delivery`,
`carrier_on_time_overall`, `pickup_appointment_time`, `delivery_appointment_time`.

**Flags that reach `fact_load`:** `zero_book_price_flag`, `zero_source_price_flag`, `zero_pnl_flag`, `zero_mileage_flag`,
`mileage_imputed_flag`, `mileage_unresolved_flag`, `pnl_mismatch_flag`, `cancelled_nonzero_price_flag`,
`zero_price_active_flag`, `price_analysis_exclude_flag`, `book_price_outlier_flag`, `source_price_outlier_flag`,
`pnl_outlier_flag`. Everything else (duplicate flags, date-order flags, `lane_format_invalid_flag`,
`mileage_raw`) stays in staging or intermediate.

Things worth knowing when you query the fact:

- **Zeros are in the price columns.** `book_price`, `source_price`, `pnl` and `pnl_calculated` can be 0. For averages use
  `price_analysis_exclude_flag = false` and `<> 0`.
- **Outliers:** before averaging a price metric, decide whether to include or exclude the outliers (default include).
  Excluding means filtering the metric flag (`book_price_outlier_flag`, ...) = false.
- **`is_delivered`** means "not cancelled", not "has a delivery date".
- **`equipment_id` is never NULL.** An unknown equipment type gets the surrogate hash of NULL, which has no row in
  `dim_equipment`.
- **Mileage 0 or NULL** must be ignored in averages; `book_price_per_mile` is NULL in that case.
- **Null is not imputed.** Aggregates ignore NULL, so the effective n can be smaller than the row count.

### Variables (`dbt_project.yml`)

| Var | Default | Used by |
|---|---|---|
| `mileage_spread_threshold` | 100 | `assert_lane_mileage_spread`, `analysis_lane_mileage_multiple_values`, script |
| `outlier_lower_quantile` | 0.01 | `int_price_outlier_bounds` |
| `outlier_upper_quantile` | 0.99 | `int_price_outlier_bounds` |
| `outlier_rate_warn_max` | 0.04 | `assert_price_outlier_rate` |
| `outliers_mode` | `include` | `analysis_lane_price_stats` (`include` or `exclude`) |

---

## Testing

```bash
dbt test                          # everything
dbt build --select fact_load+     # a model and its downstream, with tests
```

Generic tests sit next to the columns in the `_*_models.yml` files (`unique`, `not_null`, `relationships`,
`accepted_values`, `accepted_range`). Singular tests in `tests/`:

| Test | Severity | Asserts |
|---|---|---|
| `assert_duplicate_ids_identical` | warn | Raw ids that repeat have identical rows (the arbitrary pick is harmless) |
| `assert_raw_pickup_after_delivery` | warn | Raw rows with pickup after delivery |
| `assert_raw_lane_format` | warn | Raw lanes that do not match `City,ST -> City,ST` |
| `assert_fact_no_pickup_after_delivery` | error | Guard: no pickup after delivery in `fact_load` |
| `assert_lane_format` | error | Guard: every lane in `fact_load` has a valid format |
| `assert_fact_zero_mileage` | warn | Loads left with mileage 0 or NULL |
| `assert_lane_mileage_spread` | warn | Lanes whose non-zero mileage spread exceeds the threshold |
| `assert_pnl_matches_raw` | warn | Reported `pnl` differs from raw `book_price - source_price` |
| `assert_price_outlier_bounds_valid` | error | Bounds exist, are ordered and have data behind them |
| `assert_outlier_flags_ignore_zero_null` | error | No outlier flag on a zero or NULL value |
| `assert_price_outlier_rate` | warn | Flag rate per metric is not 0% and not above `outlier_rate_warn_max` |

The warn-level tests are deliberate: the rows they report are allowed to exist, so an error would fail every build and
train everyone to ignore the suite. They surface a count on each run instead.

---

## Analyses (`analyses/`, compile with `dbt compile`)

| Analysis | What it shows |
|---|---|
| `analysis_zero_null_blank_raw` / `_fact` | Rows with zero, NULL or blank values, per column |
| `analysis_fact_exclusions_by_reason` | Loads left out of the fact, by reason |
| `analysis_lane_quality_summary` | Per lane: zero entries, mileage imputation, date-order flags (over loads in the fact) |
| `analysis_lane_mileage_multiple_values` | Lanes with more than one mileage and their frequencies |
| `analysis_lane_price_stats` | Per lane price statistics; respects `price_analysis_exclude_flag` and `outliers_mode` |
| `analysis_price_outliers` | Outlier bounds and the flagged loads |

Example: `dbt compile -s analysis_lane_price_stats --vars '{outliers_mode: exclude}'`.

## Scripts

`scripts/lane_mileage_inconsistency.py` is the pandas version of the multiple-mileage check, on the raw data
(`--csv` export or `--dsn` for `raw.loads`). Report only; it changes nothing.

---

## Conventions

- **Layers:** `stg_` staging, `int_` intermediate, `fact_` / `dim_` marts.
- **Schema files:** one `_<layer>_models.yml` per directory (`_staging_sources.yml` for sources), leading underscore.
  One `models:` key per file: to add a model, extend the existing list. A second `models:` key silently replaces the first.
- **Grain in the description.** Every model states its grain in the first lines.
- **Flags are `_flag`-suffixed booleans.** Staging and intermediate never drop a flagged row; only
  `int_loads_unique.exclude_from_fact_flag` decides what leaves the fact.
- **Naming:** the fact is `fact_load` (singular); renaming would break downstream consumers.

## Layout

```
analyses/      seven analyses (see the table above)
macros/        generate_schema_name, nonzero_stats, outlier_clause, zero_null_blank_report
models/
  staging/       stg_loads.sql, _staging_models.yml, _staging_sources.yml
  intermediate/  int_loads_unique.sql, int_price_outlier_bounds.sql, _intermediate_models.yml
  marts/         fact_load.sql, dim_*.sql, _marts_models.yml
scripts/       lane_mileage_inconsistency.py
seeds/         state_names.csv
tests/         eleven singular tests
```
