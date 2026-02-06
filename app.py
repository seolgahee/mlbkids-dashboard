import streamlit as st
from datetime import date, timedelta
from src.db.snowflake import run_sql_file
import pandas as pd
import altair as alt

st.set_page_config(page_title="MLB 키즈 공식몰 분석 대시보드", layout="wide")

# ======================
# ✅ session_state 초기화
# ======================
if "loaded" not in st.session_state:
    st.session_state.loaded = False
if "data" not in st.session_state:
    st.session_state.data = {}
if "query_key" not in st.session_state:
    st.session_state.query_key = None
if "menu" not in st.session_state:
    st.session_state.menu = "요약"

# ======================
# 🎨 UI 공통 CSS (배경 + 섹션카드 + 서브카드 + 탭 스타일)
# ======================
st.markdown(
    """
    <style>
      /* 섹션 카드 */
      .section-card {
        background: #FBFBFD;
        border: 1px solid rgba(0,0,0,0.08);
        border-left: 8px solid var(--accent);
        border-radius: 14px;
        padding: 16px 18px 14px 18px;
        margin: 10px 0 14px 0;
        box-shadow: 0 2px 10px rgba(0,0,0,0.04);
      }
      .section-title {
        font-size: 20px;
        font-weight: 800;
        margin: 0 0 4px 0;
        line-height: 1.2;
      }
      .section-sub {
        color: rgba(0,0,0,0.55);
        font-size: 12px;
        margin: 0 0 10px 0;
      }

      /* KPI 서브카드 */
      .sub-card{
        background:#FFFFFF;
        border:1px solid rgba(0,0,0,0.08);
        border-radius:12px;
        padding:12px 14px;
        box-shadow: 0 1px 6px rgba(0,0,0,0.03);
      }

      /* 경고 문구 */
      .warn-text {
        color: #FF4B4B;
        font-weight: 800;
      }

      /* 탭 폰트 크게 + 선택 시 빨간색 + 볼드 */
      div[data-baseweb="tab"] > button {
        font-size: 18px !important;
        font-weight: 700 !important;
      }
      div[data-baseweb="tab"] > button[aria-selected="true"] {
        color: #FF4B4B !important;
        font-weight: 900 !important;
      }

      /* 탭 하단 라인도 빨간 느낌(가능한 범위) */
      div[data-baseweb="tabs"] div[role="tablist"] {
        border-bottom: 1px solid rgba(0,0,0,0.08);
      }
    </style>
    """,
    unsafe_allow_html=True
)

def section_start(title: str, subtitle: str = "", accent: str = "#4F81BD"):
    st.markdown(
        f"""
        <div class="section-card" style="--accent:{accent};">
          <div class="section-title">{title}</div>
          <div class="section-sub">{subtitle}</div>
        """,
        unsafe_allow_html=True
    )

def section_end():
    st.markdown("</div>", unsafe_allow_html=True)

def subcard_start():
    st.markdown("<div class='sub-card'>", unsafe_allow_html=True)

def subcard_end():
    st.markdown("</div>", unsafe_allow_html=True)

# ======================
# 🔐 로그인 체크
# ======================
def check_password():
    if "authenticated" not in st.session_state:
        st.session_state.authenticated = False

    if st.session_state.authenticated:
        return True

    st.markdown("## 👶🏻MLB 키즈 공식몰 분석 대시보드👶🏻")
    st.caption("내부 전용 대시보드 · 무단 공유 금지")
    st.markdown("---")

    st.markdown("## 🔒 로그인")
    pwd = st.text_input("비밀번호를 입력하세요", type="password", placeholder="비밀번호 입력")

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
# SQL 로더 (캐시)
# ======================
@st.cache_data(ttl=600)
def load_users(p, _cache_key): return run_sql_file("src/sql/section1_users_split.sql", p)

@st.cache_data(ttl=600)
def load_purchase_qty(p, _cache_key): return run_sql_file("src/sql/section1_purchase_qty_split.sql", p)

@st.cache_data(ttl=600)
def load_revenue(p, _cache_key): return run_sql_file("src/sql/section1_revenue_split.sql", p)

@st.cache_data(ttl=600)
def load_kids_source_medium_top10(p, _cache_key): return run_sql_file("src/sql/section2_kids_conversion_source_medium_top10.sql", p)

@st.cache_data(ttl=600)
def load_kids_top10_product_performance(p, _cache_key): return run_sql_file("src/sql/section3_kids_top10_product_performance.sql", p)

@st.cache_data(ttl=600)
def load_kids_top10_product_views(p, _cache_key): return run_sql_file("src/sql/section3_kids_top10_product_views.sql", p)

@st.cache_data(ttl=600)
def load_kids_revenue_top10_category(p, _cache_key): return run_sql_file("src/sql/section4_kids_revenue_top10_category.sql", p)

@st.cache_data(ttl=600)
def load_kids_promo_top10(p, _cache_key): return run_sql_file("src/sql/section4_kids_promo_top10.sql", p)

@st.cache_data(ttl=600)
def load_kids_cross_revenue(p, _cache_key): return run_sql_file("src/sql/section5_kids_revenue_cross.sql", p)

@st.cache_data(ttl=600)
def load_adult_cross_revenue(p, _cache_key): return run_sql_file("src/sql/section5_adult_revenue_cross.sql", p)

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

def fmt_pct2(x):
    try:
        return f"{float(x):.2f}%"
    except Exception:
        return x

def format_df_for_display(df: pd.DataFrame, money_cols=None, int_cols=None, pct_cols=None, pct_decimals=0):
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

    if pct_cols and pct_decimals == 2:
        for c in pct_cols:
            if c in out.columns:
                out[c] = out[c].apply(fmt_pct2)

    return out

# ======================
# ✅ KPI 100% 가로 누적 막대
# ======================
def render_kpi_100pct_bar(df, value_col, order, value_unit=""):
    if df is None or df.empty:
        st.info("데이터가 없습니다.")
        return

    cols = {c.lower(): c for c in df.columns}
    bcol = cols.get("bucket", "bucket")
    vcol = cols.get(value_col.lower(), value_col)

    total = float(df[vcol].sum())

    rows = []
    for k in order:
        val = float(df[df[bcol] == k][vcol].sum())
        pct = (val / total * 100) if total > 0 else 0
        rows.append({"구분": "전체", "유형": k, "비중": pct, "값": val})

    chart_df = pd.DataFrame(rows)
    default_palette = ["#D9D9D9", "#4F81BD", "#C0504D", "#9BBB59", "#8064A2"]
    palette = default_palette[:len(order)]

    chart = (
        alt.Chart(chart_df)
        .mark_bar(size=60)
        .encode(
            x=alt.X("비중:Q", stack="normalize", axis=alt.Axis(format="%")),
            y=alt.Y("구분:N", title=None),
            color=alt.Color("유형:N", scale=alt.Scale(domain=order, range=palette), legend=alt.Legend(title=None)),
            tooltip=[
                alt.Tooltip("유형:N", title="유형"),
                alt.Tooltip("비중:Q", title="비중(%)", format=".2f"),
                alt.Tooltip("값:Q", title="값", format=","),
            ],
        )
        .properties(height=160)
    )

    st.altair_chart(chart, use_container_width=True)

    for r in rows:
        if value_unit == "원":
            val_txt = f"{int(r['값']):,}원"
        else:
            val_txt = f"{int(r['값']):,}{value_unit}"
        st.write(f"• **{r['유형']}** : {r['비중']:.0f}% ({val_txt})")

# ======================
# ✅ 섹션5: 교차 구매 비중
# ======================
def render_cross_box(title: str, df: pd.DataFrame):
    st.markdown(f"### {title}")
    if df is None or df.empty:
        st.info("데이터가 없습니다.")
        return

    cols = {c.lower(): c for c in df.columns}
    ad_col = cols.get("ad_type", "ad_type")
    rev_col = cols.get("revenue", "revenue")

    order = ["키즈 광고", "성인 광고"]
    m = {str(r[ad_col]): float(r[rev_col]) for _, r in df.iterrows()}
    total = sum(m.get(k, 0) for k in order)

    rows = []
    for k in order:
        val = float(m.get(k, 0))
        pct = (val / total * 100) if total > 0 else 0
        rows.append({"구분": "전체", "유형": k, "비중": pct, "값": val})

    chart_df = pd.DataFrame(rows)
    palette = ["#4F81BD", "#C0504D"]

    chart = (
        alt.Chart(chart_df)
        .mark_bar(size=60)
        .encode(
            x=alt.X("비중:Q", stack="normalize", axis=alt.Axis(format="%")),
            y=alt.Y("구분:N", title=None),
            color=alt.Color("유형:N", scale=alt.Scale(domain=order, range=palette), legend=alt.Legend(title=None)),
            tooltip=[
                alt.Tooltip("유형:N", title="유형"),
                alt.Tooltip("비중:Q", title="비중(%)", format=".2f"),
                alt.Tooltip("값:Q", title="매출(원)", format=","),
            ],
        )
        .properties(height=160)
    )

    st.altair_chart(chart, use_container_width=True)

    for r in rows:
        st.write(f"• **{r['유형']}** : {r['비중']:.0f}% ({int(r['값']):,}원)")

# ======================
# 컬럼명 한글 매핑
# ======================
COLMAP_KIDS_SM = {
    "SOURCE_MEDIUM": "소스/매체",
    "INFLOW_TYPE": "유입 유형",
    "USERS": "사용자수",
    "SESSIONS": "세션수",
    "REVENUE": "매출",
}

COLMAP_KIDS_PERF = {
    "RANK": "순위",
    "ITEM_ID": "상품코드",
    "ITEM_NAME": "상품명",
    "QUANTITY": "구매수량",
    "REVENUE": "매출",
}

COLMAP_KIDS_VIEWS = {
    "RANK": "순위",
    "ITEM_ID": "상품코드",
    "ITEM_NAME": "상품명",
    "VIEW_COUNT": "조회수",
}

COLMAP_KIDS_CAT = {
    "RANK": "순위",
    "CATEGORY": "카테고리",
    "QUANTITY": "구매수량",
    "REVENUE": "매출",
}

COLMAP_KIDS_PROMO = {
    "RANK": "순위",
    "PROMO_NO": "구분",
    "PROMO_NAME": "기획전명",
    "PROMO_URL": "기획전 링크",
    "PROMO_SESSIONS": "유입",
    "VIEW_SESSIONS": "상품 조회",
    "PURCHASE_SESSIONS": "구매",
    "PURCHASE_CVR_PCT": "CVR",
    "REVENUE": "매출",
}

# ======================
# ✅ 사이드바: 날짜 선택 → 조회 버튼 → 메뉴(아래)
# ======================
with st.sidebar:
    st.markdown("### 기간 선택")

    start_dt = st.date_input("시작일", value=date.today(), key="sb_start")
    max_end = start_dt + timedelta(days=6)

    end_dt = st.date_input(
        "종료일",
        value=start_dt,
        min_value=start_dt,
        max_value=max_end,
        key="sb_end"
    )

    if end_dt < start_dt:
        end_dt = start_dt
    if end_dt > max_end:
        end_dt = max_end

    days = (end_dt - start_dt).days + 1
    st.caption(f"{start_dt} ~ {end_dt} (총 {days}일, 최대 7일)")
    st.markdown("<span class='warn-text'>※ BigQuery 데이터 반영 지연으로 인해, 최근 2~3일 데이터가 누락되었거나 조회가 어려움 </span>", unsafe_allow_html=True)

    params = {
        "start_date": start_dt.strftime("%Y%m%d"),
        "end_date": end_dt.strftime("%Y%m%d"),
    }
    cache_day_key = date.today().strftime("%Y%m%d")

    # 날짜 바뀌면 기존 조회 무효화
    query_key = f"{params['start_date']}_{params['end_date']}"
    if st.session_state.query_key != query_key:
        st.session_state.query_key = query_key
        st.session_state.loaded = False
        st.session_state.data = {}

    st.markdown("---")

    if st.button("조회", use_container_width=True):
        with st.spinner("데이터 조회 중..."):
            st.session_state.data = {
                "users_df": load_users(params, cache_day_key),
                "qty_df": load_purchase_qty(params, cache_day_key),
                "revenue_df": load_revenue(params, cache_day_key),
                "kids_sm_df": load_kids_source_medium_top10(params, cache_day_key),
                "kids_perf_df": load_kids_top10_product_performance(params, cache_day_key),
                "kids_views_df": load_kids_top10_product_views(params, cache_day_key),
                "kids_cat_df": load_kids_revenue_top10_category(params, cache_day_key),
                "kids_promo_df": load_kids_promo_top10(params, cache_day_key),
                "kids_cross_df": load_kids_cross_revenue(params, cache_day_key),
                "adult_cross_df": load_adult_cross_revenue(params, cache_day_key),
            }
            st.session_state.loaded = True

    st.markdown("---")
    st.markdown("### 메뉴")

    menu = st.radio(
        "이동",
        ["요약", "유입", "상품", "기획전", "교차구매"],
        key="menu",
        label_visibility="collapsed"
    )

# ======================
# 조회 전 가드
# ======================
if not st.session_state.loaded:
    st.info("좌측 사이드바에서 기간 선택 후 ‘조회’를 눌러주세요.")
    st.stop()

# ✅ 여기부터는 session_state 데이터로만 렌더
users_df = st.session_state.data.get("users_df")
qty_df = st.session_state.data.get("qty_df")
revenue_df = st.session_state.data.get("revenue_df")

kids_sm_df = st.session_state.data.get("kids_sm_df")
kids_perf_df = st.session_state.data.get("kids_perf_df")
kids_views_df = st.session_state.data.get("kids_views_df")
kids_cat_df = st.session_state.data.get("kids_cat_df")
kids_promo_df = st.session_state.data.get("kids_promo_df")

kids_cross_df = st.session_state.data.get("kids_cross_df")
adult_cross_df = st.session_state.data.get("adult_cross_df")

# ======================
# ✅ 메뉴 선택 시, 아래(메인 영역)에 해당 화면만 노출
# ======================

# 1) 요약 → 요약 KPI
if menu == "요약":
    section_start("요약 KPI", "전체/키즈 전환 기준 핵심 지표", accent="#4F81BD")
    c1, c2, c3 = st.columns(3)

    with c1:
        subcard_start()
        st.subheader("총 사용자수")
        st.caption("*전체 기준")
        render_kpi_100pct_bar(users_df, "USERS", ["Non-paid", "키즈 광고", "성인 광고"], "명")
        subcard_end()

    with c2:
        subcard_start()
        st.subheader("구매한 상품 (구매수)")
        st.caption("*키즈 전환 기준")
        render_kpi_100pct_bar(qty_df, "PURCHASE_QTY", ["키즈 광고가 아닌것", "키즈 광고"], "건")
        subcard_end()

    with c3:
        subcard_start()
        st.subheader("상품 수익 (매출)")
        st.caption("*키즈 전환 기준")
        render_kpi_100pct_bar(revenue_df, "REVENUE", ["키즈 광고가 아닌것", "키즈 광고"], "원")
        subcard_end()

    section_end()

# 2) 유입 → 소스/매체 TOP10
elif menu == "유입":
    section_start("키즈 상품 기준 소스/매체 성과 TOP 10", "키즈 상품(상품ID 7%)을 1회 이상 조회 또는 구매한 사용자 기준", accent="#9BBB59")

    kids_sm_show = format_df_for_display(
        kids_sm_df,
        money_cols=["REVENUE", "revenue"],
        int_cols=["USERS", "users", "SESSIONS", "sessions"]
    )
    if kids_sm_show is not None and not kids_sm_show.empty:
        kids_sm_show = kids_sm_show.rename(columns=COLMAP_KIDS_SM)

    st.dataframe(kids_sm_show, use_container_width=True, hide_index=True)
    section_end()

# 3) 상품 → 카테고리 TOP10, 상품 구매성과 TOP10, 상품 조회수 TOP10 (탭으로 아래에 나타나게)
elif menu == "상품":
    tab1, tab2, tab3 = st.tabs(["카테고리 TOP10", "상품 구매성과 TOP10", "상품 조회수 TOP10"])

    with tab1:
        section_start("키즈 매출 TOP 10 카테고리", "구매수량/매출 기준", accent="#8064A2")
        kids_cat_show = format_df_for_display(
            kids_cat_df,
            money_cols=["REVENUE", "revenue"],
            int_cols=["QUANTITY", "quantity", "RANK", "rank"]
        )
        if kids_cat_show is not None and not kids_cat_show.empty:
            kids_cat_show = kids_cat_show.rename(columns=COLMAP_KIDS_CAT)
        st.dataframe(kids_cat_show, use_container_width=True, hide_index=True)
        section_end()

    with tab2:
        section_start("키즈 TOP 10 상품 성과", "구매수량/매출 기준", accent="#8064A2")
        kids_perf_show = format_df_for_display(
            kids_perf_df,
            money_cols=["REVENUE", "revenue"],
            int_cols=["QUANTITY", "quantity", "RANK", "rank"]
        )
        if kids_perf_show is not None and not kids_perf_show.empty:
            kids_perf_show = kids_perf_show.rename(columns=COLMAP_KIDS_PERF)
        st.dataframe(kids_perf_show, use_container_width=True, hide_index=True)
        section_end()

    with tab3:
        section_start("키즈 상품 조회수 TOP 10", "상품 조회수 기준", accent="#8064A2")
        kids_views_show = format_df_for_display(
            kids_views_df,
            int_cols=["VIEW_COUNT", "view_count", "RANK", "rank"]
        )
        if kids_views_show is not None and not kids_views_show.empty:
            kids_views_show = kids_views_show.rename(columns=COLMAP_KIDS_VIEWS)
        st.dataframe(kids_views_show, use_container_width=True, hide_index=True)
        section_end()

# 4) 기획전 → 기획전 TOP10
elif menu == "기획전":
    section_start("키즈 기획전 TOP 10", "유입/상품조회/구매/CVR/매출", accent="#C0504D")

    kids_promo_show = format_df_for_display(
        kids_promo_df,
        money_cols=["REVENUE", "revenue"],
        int_cols=[
            "RANK", "rank",
            "PROMO_SESSIONS", "promo_sessions",
            "VIEW_SESSIONS", "view_sessions",
            "PURCHASE_SESSIONS", "purchase_sessions",
        ],
        pct_cols=["PURCHASE_CVR_PCT", "purchase_cvr_pct"],
        pct_decimals=2
    )

    if kids_promo_show is not None and not kids_promo_show.empty:
        kids_promo_show = kids_promo_show.rename(columns=COLMAP_KIDS_PROMO)

        st.data_editor(
            kids_promo_show,
            use_container_width=True,
            hide_index=True,
            disabled=True,
            column_config={
                "기획전 링크": st.column_config.LinkColumn(
                    label="기획전 링크",
                    help="클릭 시 해당 기획전으로 이동",
                    display_text="바로가기",
                    validate=r"^https?://.*",
                ),
            }
        )
    else:
        st.dataframe(kids_promo_show, use_container_width=True, hide_index=True)

    section_end()

# 5) 교차구매 → 유지
elif menu == "교차구매":
    tab1, tab2 = st.tabs(["키즈 매출", "성인 매출"])

    with tab1:
        section_start("키즈/성인 광고 통한 교차 구매 비중", "키즈 매출 기준", accent="#4F81BD")
        render_cross_box("키즈 매출", kids_cross_df)
        section_end()

    with tab2:
        section_start("키즈/성인 광고 통한 교차 구매 비중", "성인 매출 기준", accent="#4F81BD")
        render_cross_box("성인 매출", adult_cross_df)
        section_end()
