#!/usr/bin/env python3
"""Lanes with more than one mileage value (pandas version, reads the RAW data).

Same rule as tests/assert_lane_mileage_spread.sql and analyses/analysis_lane_mileage_multiple_values.sql,
but applied to the raw export instead of fact_load (so nothing is imputed, excluded or deduplicated by dbt):

  * only non-cancelled loads (load_was_cancelled is false)
  * only mileage > 0
  * a lane is listed when max(mileage) - min(mileage) > threshold
  * exact duplicate rows of the export are dropped first, so a duplicated load is not counted twice
  * nothing is changed or removed: this is a report only

Usage (source is either a CSV export or the raw.loads table):
  python scripts/lane_mileage_inconsistency.py --csv path/to/loads.csv
  python scripts/lane_mileage_inconsistency.py --dsn postgresql://user:pass@localhost:5432/loadsmart_dev
  python scripts/lane_mileage_inconsistency.py --csv loads.csv --threshold 50 --out lanes.csv

Needs pandas; --dsn also needs sqlalchemy and psycopg2-binary.
The default threshold is the dbt var mileage_spread_threshold (dbt_project.yml).
"""
import argparse
import sys

import pandas as pd

DEFAULT_THRESHOLD = 100  # keep in sync with vars.mileage_spread_threshold in dbt_project.yml


def load(args) -> pd.DataFrame:
    if args.csv:
        return pd.read_csv(args.csv)
    from sqlalchemy import create_engine  # imported here so --csv works without it

    engine = create_engine(args.dsn)
    return pd.read_sql(f"select * from {args.table}", engine)


def to_bool(s: pd.Series) -> pd.Series:
    """load_was_cancelled may be bool or text ('True'/'False'); anything else counts as not cancelled."""
    if s.dtype == bool:
        return s
    return s.astype(str).str.strip().str.lower().isin(["true", "t", "1", "yes"])


def find_lanes(df: pd.DataFrame, threshold: float) -> pd.DataFrame:
    df = df.drop_duplicates().copy()
    df["lane"] = df["lane"].astype(str).str.strip()
    df["mileage"] = pd.to_numeric(df["mileage"], errors="coerce")
    df["cancelled"] = to_bool(df["load_was_cancelled"])

    base = df[(~df["cancelled"]) & (df["mileage"] > 0)]
    if base.empty:
        return pd.DataFrame(columns=["lane", "n_values", "min_mileage", "max_mileage", "spread", "value_counts"])

    g = base.groupby("lane")["mileage"]
    out = pd.DataFrame(
        {
            "n_values": g.nunique(),
            "min_mileage": g.min(),
            "max_mileage": g.max(),
        }
    )
    out["spread"] = out["max_mileage"] - out["min_mileage"]
    out["value_counts"] = g.apply(lambda s: s.value_counts().sort_index().to_dict())
    out = out[(out["n_values"] > 1) & (out["spread"] > threshold)]
    return out.sort_values("spread", ascending=False).reset_index()


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--csv", help="CSV export of the loads")
    src.add_argument("--dsn", help="SQLAlchemy URL of the Postgres database that holds raw.loads")
    p.add_argument("--table", default="raw.loads", help="table to read with --dsn (default raw.loads)")
    p.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD, help="miles (default %(default)s)")
    p.add_argument("--out", help="also write the result to this CSV file")
    args = p.parse_args()

    result = find_lanes(load(args), args.threshold)
    print(f"{len(result)} lane(s) with spread > {args.threshold:g} miles")
    if not result.empty:
        with pd.option_context("display.max_colwidth", 120, "display.width", 200):
            print(result.to_string(index=False))
    if args.out:
        result.to_csv(args.out, index=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
