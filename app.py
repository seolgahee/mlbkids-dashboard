import streamlit as st
from datetime import date
from src.db.snowflake import run_sql_file
import pandas as pd

st.set_page_config(
    page_title="MLB 키즈 공식몰 분석 대시보드",
    layout="wide"
)

# ======================
# 🔐 로그인 체크
# ======================
def check_password():
    if "authenticated" not in st.session_state:
        st.session_state.authenticated = False

    if st.session_state.authenticated:
        return True

    # 로그인 화면 제목
    st.markdown("## 👶🏻MLB 키즈 공식몰 분석 대시보드👶🏻")
    st.caption("내부 전용 대시보드 · 무단 공유 금지")
    st.markdown("---")

    st.markdown("## 🔒 로그인")
    pwd = st.text_input(
        "비밀번호를 입력하세요",
        type="password",
        placeholder="비밀번호 입력"
    )

    if st.button("로그인"):
        if pwd == st.secrets["auth"]["password"]:
            st.session_state.authenticated = True
            st.rerun()
        else:
            st.error("비밀번호가 올바르지 않습니다.")

    return False


if not check_password():
    st.stop()

st.title("MLB 키즈 공식몰 분석 대시보드")

# ======================
# 기간 선택
# ======================
c1, c2 = st.columns(2)
start_dt = c1.date_input("시작일", value=date.today().replace(day=1))
end_dt = c2.date_input("종료일", value=date.today())

st.caption("대량 데이터 조회 시 로딩 지연이 발생할 수 있습니다.")

params = {
    "start_date": start_dt.strftime("%Y%m%d"),
    "end_date": end_dt.strftime("%Y%m%d"),
}

# ======================
# SQL 로더 (캐시)
# ======================
@st.cache_data(ttl=600)
def load_users(p):
    return run_sql_file("src/sql/section1_users_split.sql", p)

@st.cache_data(ttl=600)
def load_purchase_qty(p):
    return run_sql_file("src/sql/section1_purchase_qty_split.sql", p)

@st.cache_data(ttl=600)
def load_revenue(p):
    return run_sql_file("src/sql/section1_revenue_split.sql", p)

@st.cache_data(ttl=600)
def load_kids_source_medium_top10(p):
    return run_sql_file("src/sql/section2_kids_conversion_source_medium_top10.sql", p)

@st.cache_data(ttl=600)
def load_kids_top10_product_performance(p):
    return run_sql_file("src/sql/section3_kids_top10_product_performance.sql", p)

@st.cache_data(ttl=600)
def load_kids_top10_product_views(p):
    return run_sql_file("src/sql/section3_kids_top10_product_views.sql", p)

@st.cache_data(ttl=600)
def load_kids_revenue_top10_category(p):
    return run_sql_file("src/sql/section4_kids_revenue_top10_category.sql", p)

@st.cache_data(ttl=600)
def load_kids_promo_top10(p):
    return run_sql_file("src/sql/section4_kids_promo_top10.sql", p)

# ✅ 섹션5 (교차 구매 비중) - 키즈/성인 매출 분리
@st.cache_data(ttl=600)
def load_kids_cross_revenue(p):
    return run_sql_file("src/sql/section5_kids_revenue_cross.sql", p)

@st.cache_data(ttl=600)
def load_adult_cross_revenue(p):
    return run_sql_file("src/sql/section5_adult_revenue_cross.sql", p)

# ======================
# KPI 표시용 함수
# ======================
def render_kpi(df, value_col, order):
    if df is None or df.empty:
        for k in order:
            st.write(f"{k} 0% (0)")
        return

    cols = {c.lower(): c for c in df.columns}
    bcol = cols.get("bucket", "bucket")
    vcol = cols.get(value_col.lower(), value_col)

    total = df[vcol].sum()
    value_map = {r[bcol]: r[vcol] for _, r in df.iterrows()}

    for k in order:
        val = int(value_map.get(k, 0))
        pct = round((val / total) * 100) if total > 0 else 0
        st.write(f"{k} {pct}% ({val:,})")

# ======================
# 표 포맷 유틸
# ======================
def fmt_int(x):
    try:
        return f"{int(x):,}"
    except Exception:
        return x

def fmt_won(x):
    try:
        return f"₩{int(round(float(x))):,}"
    except Exception:
        return x

def fmt_pct(x):
    try:
        return f"{float(x):.0f}%"
    except Exception:
        return x

def format_df_for_display(df: pd.DataFrame, money_cols=None, int_cols=None, pct_cols=None):
    if df is None or df.empty:
        return df

    out = df.copy()

    if money_cols:
        for c in money_cols:
            if c in out.columns:
                out[c] = out[c].apply(fmt_won)

    if int_cols:
        for c in int_cols:
            if c in out.columns:
                out[c] = out[c].apply(fmt_int)

    if pct_cols:
        for c in pct_cols:
            if c in out.columns:
                out[c] = out[c].apply(fmt_pct)

    return out


# ======================
# 섹션5 카드 출력(비중 + 괄호 매출)
# ======================
def render_cross_box(title: str, df: pd.DataFrame):
    st.markdown(f"### {title}")

    if df is None or df.empty:
        st.info("데이터가 없습니다.")
        return

    cols = {c.lower(): c for c in df.columns}
    ad_col = cols.get("ad_type", "ad_type")
    pct_col = cols.get("pct", "pct")
    rev_col = cols.get("revenue", "revenue")

    order = ["키즈 광고", "성인 광고"]
    m = {r[ad_col]: {"pct": r[pct_col], "rev": r[rev_col]} for _, r in df.iterrows()}

    for k in order:
        pct = m.get(k, {}).get("pct", 0)
        rev = m.get(k, {}).get("rev", 0)
        st.write(f"{k} {fmt_pct(pct)} ({fmt_won(rev)})")

  

# ======================
# 실행
# ======================
if st.button("조회"):
    with st.spinner("데이터 조회 중..."):
        users_df = load_users(params)
        qty_df = load_purchase_qty(params)
        revenue_df = load_revenue(params)

        kids_sm_df = load_kids_source_medium_top10(params)

        kids_perf_df = load_kids_top10_product_performance(params)
        kids_views_df = load_kids_top10_product_views(params)

        kids_cat_df = load_kids_revenue_top10_category(params)
        kids_promo_df = load_kids_promo_top10(params)

        kids_cross_df = load_kids_cross_revenue(params)
        adult_cross_df = load_adult_cross_revenue(params)

    col1, col2, col3 = st.columns(3)

    with col1:
        st.subheader("총 사용자수")
        render_kpi(users_df, value_col="USERS", order=["Non-paid", "키즈 광고", "성인 광고"])
       

    with col2:
        st.subheader("구매한 상품 (구매수)")
        render_kpi(qty_df, value_col="PURCHASE_QTY", order=["키즈 광고가 아닌것", "키즈 광고"])
      

    with col3:
        st.subheader("상품 수익 (매출)")
        render_kpi(revenue_df, value_col="REVENUE", order=["키즈 광고가 아닌것", "키즈 광고"])
      

    st.divider()
    st.subheader("키즈 전환 상품 기준 상세 유입 소스/매체 TOP 10")
    kids_sm_show = format_df_for_display(
        kids_sm_df,
        money_cols=["REVENUE", "revenue"],
        int_cols=["SESSIONS", "sessions"]
    )
    st.dataframe(kids_sm_show, use_container_width=True, hide_index=True)

    st.divider()
    left, right = st.columns(2)

    with left:
        st.subheader("키즈 Top10 상품 성과")
        kids_perf_show = format_df_for_display(
            kids_perf_df,
            money_cols=["REVENUE", "revenue"],
            int_cols=["QUANTITY", "quantity", "RANK", "rank"]
        )
        st.dataframe(kids_perf_show, use_container_width=True, hide_index=True)
       

    with right:
        st.subheader("키즈 상품 조회수 Top10")
        kids_views_show = format_df_for_display(
            kids_views_df,
            int_cols=["VIEW_COUNT", "view_count", "RANK", "rank"]
        )
        st.dataframe(kids_views_show, use_container_width=True, hide_index=True)
        

    st.divider()
    left2, right2 = st.columns(2)

    with left2:
        st.subheader("키즈 매출 Top10 카테고리")
        kids_cat_show = format_df_for_display(
            kids_cat_df,
            money_cols=["REVENUE", "revenue"],
            int_cols=["QUANTITY", "quantity", "RANK", "rank"]
        )
        st.dataframe(kids_cat_show, use_container_width=True, hide_index=True)
       

    with right2:
        st.subheader("키즈 기획전 Top10")
        kids_promo_show = format_df_for_display(
            kids_promo_df,
            money_cols=["REVENUE", "revenue"],
            int_cols=[
                "PAGEVIEWS", "pageviews",
                "VIEW_ITEM_EVENTS", "view_item_events",
                "PURCHASE_EVENTS", "purchase_events",
                "RANK", "rank"
            ],
            pct_cols=["PURCHASE_CVR_PCT", "purchase_cvr_pct"]
        )
        st.dataframe(kids_promo_show, use_container_width=True, hide_index=True)
      

    st.divider()
    st.subheader("키즈/성인 광고 통한 교차 구매 비중")

    box_l, box_r = st.columns(2)

    with box_l:
        render_cross_box("키즈 매출", kids_cross_df)

    with box_r:
        render_cross_box("성인 매출", adult_cross_df)

else:
    st.info("기간 선택 후 ‘조회’를 눌러주세요.")
