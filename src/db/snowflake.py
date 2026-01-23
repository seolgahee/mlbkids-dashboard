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
    Snowflake connector pyformat(%(name)s) 대신,
    우리가 직접 문자열 치환해서 % 관련 오류를 원천 제거.

    주의: params 값은 YYYYMMDD 숫자만 들어온다는 전제(현재 app.py 구조)
    """
    if not params:
        return sql

    # start_date / end_date가 없으면 그대로
    if "start_date" in params:
        sd = str(params["start_date"])
        # 숫자 8자리만 허용(안전장치)
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
    - % 포맷(pyformat) 사용 안 함 (재발 0)
    """
    sql = Path(sql_path).read_text(encoding="utf-8")
    sql = _safe_replace_params(sql, params)

    conn = get_conn()
    cur = conn.cursor()
    try:
        cur.execute(sql)  # ✅ params 전달 X
        return cur.fetch_pandas_all()
    finally:
        cur.close()
        conn.close()
