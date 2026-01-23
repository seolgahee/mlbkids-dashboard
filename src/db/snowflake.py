# src/db/snowflake.py
import streamlit as st
import snowflake.connector
import pandas as pd
from pathlib import Path

# ✅ 핵심: Snowflake 파라미터 스타일을 qmark로 고정
snowflake.connector.paramstyle = "qmark"


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
    """
    SQL 파일을 읽어서 Snowflake에 실행 후 pandas DataFrame 반환 (qmark 방식)
    SQL 안에는 ? 를 사용하고, params는 [start_date, end_date] 로 전달
    """
    sql = Path(sql_path).read_text(encoding="utf-8")

    conn = get_conn()
    cur = conn.cursor()
    try:
        # ✅ qmark는 ? 순서대로 바인딩
        cur.execute(sql, (params["start_date"], params["end_date"]))
        return cur.fetch_pandas_all()
    finally:
        cur.close()
        conn.close()
