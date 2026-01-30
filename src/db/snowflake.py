# src/db/snowflake.py

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


def _safe_replace_params(sql: str, params: dict) -> str:
    """
    Snowflake connector pyformat(%(name)s) 대신
    문자열 치환 방식으로 % 관련 오류를 원천 차단

    ⚠️ 전제
    - start_date / end_date 는 YYYYMMDD 숫자 8자리
    """
    if not params:
        return sql

    if "start_date" in params:
        sd = str(params["start_date"])
        if not (sd.isdigit() and len(sd) == 8):
            raise ValueError("start_date must be YYYYMMDD digits")
        sql = sql.replace("%(start_date)s", f"'{sd}'")

    if "end_date" in params:
        ed = str(params["end_date"])
        if not (ed.isdigit() and len(ed) == 8):
            raise ValueError("end_date must be YYYYMMDD digits")
        sql = sql.replace("%(end_date)s", f"'{ed}'")

    return sql


def run_sql_file(sql_path: str, params: dict) -> pd.DataFrame:
    """
    SQL 파일을 읽어서 Snowflake에 실행 후 pandas DataFrame 반환

    ✔ params 직접 execute에 넘기지 않음
    ✔ %(start_date)s / %(end_date)s 미치환 시 즉시 에러
    """
    sql = Path(sql_path).read_text(encoding="utf-8")
    sql = _safe_replace_params(sql, params)

    # ✅ 파라미터 치환 누락 방어 (여기 걸리면 SQL 파일 문제)
    if "%(start_date)s" in sql or "%(end_date)s" in sql:
        raise ValueError(
            "SQL params were not replaced. "
            "Check %(start_date)s / %(end_date)s placeholders in SQL file."
        )

    conn = get_conn()
    cur = conn.cursor()
    try:
        cur.execute(sql)  # ❌ params 전달 금지
        return cur.fetch_pandas_all()
    finally:
        cur.close()
        conn.close()