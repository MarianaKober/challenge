# Loadsmart Analytics Engineering Challenge

Hello Load! 🙋

My name is Mariana and this repository contains my submission for the Loadsmart analytics engineering challenge.
Thanks for the opportunity to participate!

Below you will find details on this repository, the project specifications and the setup instructions.

---

## Table of contents

1. [Repo structure](#repo-structure)
2. [How the pieces fit together](#how-the-pieces-fit-together)
3. [Project specifications](#project-specifications)
   - [PostgreSQL](#postgresql)
   - [dbt](#dbt)
   - [Ollama (the AI)](#ollama-the-ai)
   - [Python (the notebooks)](#python-the-notebooks)
   - [Power BI](#power-bi)
4. [Setup instructions](#setup-instructions)
5. [CI/CD: planned, not delivered](#cicd-planned-not-delivered)
6. [Known limitations](#known-limitations)

---

## Repo structure

Deliverables are ordered by number, as in the section *"Here's what you'll need to deliver in the github repository"*
of the challenge PDF, plus a `0` folder that contains the data quality analysis and the CSV *Post Data Quality
Analysis Decision Trail*, which correlates the findings to the project choices.

```
.
├── 0_data_quality/                 Data quality analysis + decision trail
│   └── Post_Data_Quality_Analysis_Decision_Trail_-_Data_Exploration_-_Page1_completed.csv
├── loadsmart_dbt/                  Deliverable 1: the dbt project (Postgres)
│   ├── models/                     staging -> intermediate -> marts
│   ├── tests/                      singular data tests
│   ├── analyses/                   exploratory / audit queries
│   ├── macros/  seeds/  scripts/
│   └── README.md                   dbt deep-dive (decisions, tests, vars)
├── 2_ai_script/                    Deliverable 2: text-to-SQL with a local LLM
│   ├── 2_ai_script.ipynb
│   └── results_table.csv           question, generated SQL, answer and error of each run
├── 3_python_csv/                   Deliverable 3: Python export to CSV
│   └── 3_python_csv.ipynb
├── 5_power_bi/                     Deliverable 5: Power BI report
│   └── <report_name>.pbix          (also sent by email)
└── README.md                       Deliverable 4: this README (project documentation)
```

> Deliverable 4 is this very README, which documents the whole repository: structure, specifications and setup.
>
> `0_data_quality/` is the "why", `loadsmart_dbt/` is the "what", and the notebooks and the Power BI report consume
> what dbt builds.
> The notebook in `2_ai_script/` reads `../loadsmart_dbt/target/manifest.json`, so keep `loadsmart_dbt/` and the
> notebook folders as siblings.

---

## How the pieces fit together

```
  loads CSV
     |  \copy (positional)
     v
  PostgreSQL  raw.loads
     |
     |  dbt   (staging -> intermediate -> marts)
     v
  PostgreSQL  analytics.fact_load + dim_shipper / dim_carrier / dim_lane / dim_equipment / dim_date
     |                         |
     |                         +--> dbt docs generate --> target/manifest.json + catalog.json
     |                                                          |
     +--------------------+                                     |
     |                    |                                     |
     v                    v                                     v
  3_python_csv.ipynb   5_power_bi (report)              2_ai_script.ipynb
  (SQL -> pandas -> CSV)                     (schema context -> Ollama -> SQL -> Postgres -> results_table.csv)
```

1. The raw export is loaded, untouched, into `raw.loads`.
2. dbt cleans it, applies the data quality decisions recorded in `0_data_quality/` and publishes a star schema in
   the `analytics` schema.
3. The notebook in `3_python_csv` queries the star schema and writes a CSV.
4. The notebook in `2_ai_script` uses dbt's own metadata (descriptions, `meta.ai_hint`, synonyms, column types and
   `relationships` tests) as the context for a local LLM that writes the SQL.
5. The Power BI report in `5_power_bi` is built on the same star schema.

---

## Project specifications

### PostgreSQL

| Item | Value |
|---|---|
| Engine | PostgreSQL, local instance on port `5432` |
| Databases | `loadsmart_dev` (default target), `loadsmart_prod` |
| User | `postgres` by default (override with `DBT_PG_USER`) |
| Source table | `raw.loads` (one row per raw export row, duplicates included) |
| Schemas built by dbt | `staging` (views), `intermediate` (views), `analytics` (tables) |
| Seed | `staging.state_names` (state code to state name) |

Environments are isolated by **database**, not by schema: both `dev` and `prod` write the same schema names.
The macro `generate_schema_name` uses the custom schema as it is (`+schema: analytics` creates a schema called
`analytics`, not `analytics_analytics`).

SQL features used by the project: `DISTINCT ON`, `percentile_cont ... WITHIN GROUP`, `FILTER (WHERE ...)`,
array functions (`unnest`, `array_remove`, `cardinality`) and regular expressions (`~`).

**`raw.loads` load rule.** The export has two columns named `has_mobile_app_tracking`. PostgreSQL rejects two
columns with the same name and `\copy` is positional, so the second one is loaded as `has_mobile_app_tracking_1`.
It only holds `False`, so it never leaves the raw layer.

### dbt

| Item | Value |
|---|---|
| Adapter | `dbt-postgres` (`>=1.10,<2.0`) |
| Core | `dbt-core` (`>=1.10,<2.0`) |
| Packages | `dbt-labs/dbt_utils` (`>=1.0.0,<2.0.0`, locked at `1.4.1`) |
| Profile | `loadsmart_dbt`, targets `dev` (default), `ci`, `prod` |
| Layers | staging (view) -> intermediate (view) -> marts (table) |
| Marts | `fact_load` + `dim_shipper`, `dim_carrier`, `dim_lane`, `dim_equipment`, `dim_date` |
| Tests | generic tests in the YAML files + 11 singular tests in `tests/` |
| Analyses | 7 files in `analyses/` (compile with `dbt compile`) |
| Script | `scripts/lane_mileage_inconsistency.py` (pandas check on the raw data) |

The connection is configured **only through environment variables** (no credentials in the repository):

| Variable | Default | Required |
|---|---|---|
| `DBT_PG_HOST` | `localhost` | no |
| `DBT_PG_PORT` | `5432` | no |
| `DBT_PG_USER` | `postgres` | no |
| `DBT_PG_PASSWORD` | none | **yes** |
| `DBT_CI_SCHEMA_PREFIX` | `ci_local` | only for the `ci` target |

Data quality decisions in short: duplicated ids are collapsed in staging; zeros in prices are **kept** and flagged;
loads with `pickup_date` after `delivery_date` or with a lane out of the `City,ST -> City,ST` format are excluded from
the fact (with the reason recorded); mileage 0 is imputed with the lane median; price outliers are flagged, never
removed. The full reasoning is in `0_data_quality/` and the details, tests and variables are in
[`loadsmart_dbt/README.md`](loadsmart_dbt/README.md).

### Ollama (the AI)

The AI deliverable runs a **local** model through [Ollama](https://ollama.com), so no data leaves the machine
and no API key is needed.

| Item | Value |
|---|---|
| Runtime | Ollama, local server |
| Endpoint | `http://localhost:11434/api/generate` |
| Model | `llama3.1:8b` |
| Generation options | `temperature: 0`, `stream: false`, request timeout 600 s |
| Download size | about 5 GB for the model; 8 GB of RAM or more is recommended |

How the script works (`2_ai_script/2_ai_script.ipynb`):

1. **Schema context.** It reads `target/manifest.json` and `target/catalog.json` from the dbt project and builds a
   text description of every model in the `analytics` schema: table description, `meta` (grain, synonyms and the
   `ai_hint` query rules written in the YAML), column descriptions, column types and the relationships taken from the
   `relationships` tests.
2. **Prompt.** The question, a block of SQL-writing rules and the schema context are sent to the model, which must
   answer with a single `SELECT`.
3. **Extraction.** The first `SELECT ... ;` is pulled out of the response.
4. **Execution.** The SQL runs on PostgreSQL with `search_path` set to `analytics`, and the result comes back as a
   pandas DataFrame (capped at 200 rows).
5. **Output.** Question, generated SQL, answer and error (if any) are written to `results_table.csv`. The copy
   delivered in `2_ai_script/` is the result of the run submitted with this challenge.

Because the context comes from dbt's metadata, **improving the YAML descriptions and `ai_hint` improves the AI
answers**; that is why the marts YAML is written with short, self-contained descriptions.

### Python (the notebooks)

| Item | Value |
|---|---|
| Python | 3.14.7 (the version used to run the notebooks, on Windows) |
| Environment | virtualenv in `.venv` |
| Notebook server | Jupyter (`ipykernel`, kernel "Python 3") |
| Data | `pandas`, `sqlalchemy` |
| Postgres drivers | `psycopg2` (used by `2_ai_script`), `psycopg[binary]` 3.x (installed by `3_python_csv`) |
| HTTP | `requests` (calls to Ollama) |

| Notebook | Variables it reads | What it does |
|---|---|---|
| `2_ai_script.ipynb` | `DBT_PG_PASSWORD` | Text-to-SQL pipeline described above; writes `results_table.csv` |
| `3_python_csv.ipynb` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT` | Queries the delivered loads of the last month available in `fact_load` (`is_delivered = TRUE`) and writes `delivered_loads_last_available_month.csv` |

The CSV from `3_python_csv` has these columns: `loadsmart_id`, `shipper_name`, `delivery_date`, `pickup_city`,
`pickup_state`, `delivery_city`, `delivery_state`, `book_price`, `carrier_name`. Both notebooks hard-code the database
name `loadsmart_dev`; `3_python_csv` also has a `SCHEMA_NAME` constant that must be the schema where dbt builds the
marts (`analytics`).

### Power BI

| Item | Value |
|---|---|
| Tool | Power BI Desktop (Windows) |
| File | `5_power_bi/5_power_bi>.pbix` |
| Data source | PostgreSQL database `loadsmart_dev`, star schema published by dbt in the `analytics` schema (`fact_load` and the `dim_*` tables) |
| Delivery | Sent by email **and** committed to this repository |

The report reads the marts, not `raw.loads`: every data quality decision (exclusions, flags, imputed mileage) is
already applied by dbt, so the numbers in the report reconcile with the dbt models and with the CSVs of the other
deliverables.

---

## Setup instructions

The steps are in order. Commands are shown for PowerShell (Windows, where the project was developed); the bash
equivalent is given where it differs.

### 1. Prerequisites

- PostgreSQL running locally, with a user that can create databases and schemas
- Python 3.14 (other versions were not tested)
- [Ollama](https://ollama.com/download) (only needed for `2_ai_script`)
- The challenge data file (the loads CSV)

### 2. Python environment

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1          # bash: source .venv/bin/activate

pip install "dbt-core>=1.10,<2.0" "dbt-postgres>=1.10,<2.0"
pip install pandas sqlalchemy psycopg2-binary "psycopg[binary]" requests jupyterlab
```

### 3. Environment variables

```powershell
$env:DBT_PG_PASSWORD   = "<your postgres password>"   # required by dbt and by 2_ai_script
$env:POSTGRES_PASSWORD = "<your postgres password>"   # read by 3_python_csv
# optional, defaults in parentheses:
# $env:DBT_PG_HOST ("localhost")  $env:DBT_PG_PORT ("5432")  $env:DBT_PG_USER ("postgres")
# $env:POSTGRES_USER ("postgres") $env:POSTGRES_HOST ("localhost") $env:POSTGRES_PORT ("5432")
```

```bash
export DBT_PG_PASSWORD="<your postgres password>"
export POSTGRES_PASSWORD="<your postgres password>"
```

Never commit passwords; everything above is read from the environment.

### 4. Database and raw table

```sql
CREATE DATABASE loadsmart_dev;
-- connect to loadsmart_dev, then:
CREATE SCHEMA raw;
```

Create `raw.loads` with **one column per field of the CSV, in the same order as the CSV header** (`\copy` is
positional), renaming the second `has_mobile_app_tracking` column to `has_mobile_app_tracking_1`. Then load it:

```sql
\copy raw.loads FROM '<path/to/loads.csv>' WITH (FORMAT csv, HEADER true)
```

The dbt project expects these columns in `raw.loads`:

| Type | Columns |
|---|---|
| text | `loadsmart_id`, `lane`, `equipment_type`, `sourcing_channel`, `carrier_name`, `shipper_name` |
| timestamp | `quote_date`, `book_date`, `source_date`, `pickup_date`, `delivery_date`, `pickup_appointment_time`, `delivery_appointment_time` |
| numeric | `book_price`, `source_price`, `pnl`, `mileage`, `carrier_rating`, `carrier_dropped_us_count` |
| boolean | `vip_carrier`, `carrier_on_time_to_pickup`, `carrier_on_time_to_delivery`, `carrier_on_time_overall`, `has_mobile_app_tracking`, `has_mobile_app_tracking_1`, `has_macropoint_tracking`, `has_edi_tracking`, `contracted_load`, `load_booked_autonomously`, `load_sourced_autonomously`, `load_was_cancelled` |

### 5. Build the dbt project

```powershell
cd loadsmart_dbt
dbt deps
dbt build            # seed + models + tests
dbt docs generate    # writes target/manifest.json and target/catalog.json (needed by 2_ai_script)
```

`dbt build` finishes with warnings by design: the warn-level tests report known data quality issues (missing values,
mileage inconsistencies, `pnl` mismatches, raw rows that were excluded) without blocking the run. Errors are only
raised by the guard tests.

Optional: `dbt docs serve` opens the documentation site with descriptions and lineage.

### 6. Deliverable 3: CSV export

```powershell
cd ..\3_python_csv
jupyter lab
```

Open `3_python_csv.ipynb`, confirm that `SCHEMA_NAME` is the marts schema (`analytics`) and run all cells. The output is
`delivered_loads_last_available_month.csv` in the notebook folder.

### 7. Deliverable 2: AI script

```powershell
ollama pull llama3.1:8b
ollama serve                      # skip if the Ollama app is already running in the tray
```

```powershell
cd ..\2_ai_script
jupyter lab
```

Open `2_ai_script.ipynb` and run all cells. Change the `questions` list in the second to last cell to ask something
else. The first run of the model can be slow; the request timeout is 600 seconds. Each run overwrites
`results_table.csv` in the notebook folder.

### 8. Deliverable 5: Power BI report

The report was sent by email and is also in this repository (`5_power_bi/`).

1. Open the `.pbix` file in Power BI Desktop.
2. If the data is imported into the file, the report opens with its data and no database is needed. To refresh it, go to
   *Transform data > Data source settings* and point the PostgreSQL source to your server (`localhost`) and the
   database `loadsmart_dev`, then enter your credentials in Power BI (they are not stored in the repository).
3. Make sure `dbt build` was run first, so the `analytics` tables exist and are up to date.

---

## CI/CD: planned, not delivered

This project was **built to implement a CI/CD workflow, but the workflow itself was not implemented because time ran
out** (the pipeline ran out of time before the pipelines did 🙈).

What exists because of that plan:

- a dedicated `ci` target in `profiles.yml`, with its own schema prefix (`DBT_CI_SCHEMA_PREFIX`)
- `generate_schema_name`, which prefixes schemas only on the `ci` target so that runs never collide
- every connection setting read from environment variables, so a runner can inject secrets
- warn-level tests designed to surface counts in CI without failing the build, and error-level guard tests that
  are meant to block it

What is missing, and would have been the next steps:

1. A GitHub Actions workflow on every pull request: `dbt deps`, `dbt parse`, then `dbt build --target ci`
   against an ephemeral PostgreSQL service container.
2. A small fixture of `raw.loads` so the build can run without the real data.
3. A static check that every model and column has a description (the AI script depends on them).
4. A deploy job for the `prod` target.

---

## Known limitations

- **Generated SQL runs as-is.** `2_ai_script` executes whatever the model returns. For anything beyond a local
  demo, point it to a read-only database user.
- **An 8B local model is not perfect.** The prompt rules and the `ai_hint` in the YAML reduce wrong joins and
  filters, but the generated SQL should still be reviewed; `results_table.csv` stores the SQL next to each answer for
  that reason.
- **No CI/CD** (see above).
- **Manual raw load.** Loading `raw.loads` is a manual `\copy`; it is not part of the dbt project.
