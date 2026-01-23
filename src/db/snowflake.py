import streamlit as st
import snowflake.connector
import pandas as pd
from pathlib import Path


def get_conn():
    cfg = st.secrets["snowflake"]
    return snowflake.connector.connect(
        account=cfg["account"],
        user=cfg["user"],
        password=cfg["password"],
        role=cfg.get("role"),
        warehouse=cfg["warehouse"],
        database=cfg["database"],
        schema=cfg["schema"],
    )


def run_sql_file(sql_path: str, params: dict) -> pd.DataFrame:
    sql = Path(sql_path).read_text(encoding="utf-8")

    conn = get_conn()
    cur = conn.cursor()
    try:
        # ✅ 반드시 params 전달
        cur.execute(sql, params)
        return cur.fetch_pandas_all()
    finally:
        cur.close()
        conn.close()
