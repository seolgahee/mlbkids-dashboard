# =========================
# app.py (✅ 기획전명 하이퍼링크 적용 포함 / 전체 통째로)
# =========================
import streamlit as st
from datetime import date, timedelta
from src.db.snowflake import run_sql_file
import pandas as pd
import altair as alt

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
# 기간 선택 (✅ 시작일 기준 최대 7일, ✅ 하루치 기본)
# ======================
c1, c2 = st.columns(2)

start_dt = c1.date_input("시작일", value=date.today())
max_end = start_dt + timedelta(days=6)  # 포함 7일(시작일~+6)

end_dt = c2.date_input(
"종료일 (시작일과 같게 선택하면 하루치)",
    value=start_dt,          # ✅ 하루치 기본
    min_value=start_dt,      # ✅ 시작일 이전 선택 불가
    max_value=max_end        # ✅ 최대 7일 제한
    value=start_dt,
    min_value=start_dt,
    max_value=max_end
)

# 방어 로직
if end_dt < start_dt:
end_dt = start_dt
if end_dt > max_end:
end_dt = max_end

days = (end_dt - start_dt).days + 1

st.caption(f"조회 기간: {start_dt.strftime('%Y-%m-%d')} ~ {end_dt.strftime('%Y-%m-%d')} (총 {days}일, 최대 7일)")
st.caption("조회 기간은 최대 7일까지 설정할 수 있습니다. 데이터 양에 따라 조회 완료까지 최대 3분 정도 소요될 수 있으니 잠시만 기다려 주세요.")
st.caption("※ 최근 2일 데이터는 BigQuery 반영 지연으로 정확하지 않을 수 있습니다.")

params = {
"start_date": start_dt.strftime("%Y%m%d"),
"end_date": end_dt.strftime("%Y%m%d"),
}

# ✅ 캐시 키 분리: '오늘 날짜'가 바뀌면 캐시 자동 무효화
cache_day_key = date.today().strftime("%Y%m%d")

# ======================
# SQL 로더 (캐시)
# - cache_day_key를 추가 인자로 받아 캐시 key 분리
# ======================
@st.cache_data(ttl=600)
def load_users(p, _cache_key):
return run_sql_file("src/sql/section1_users_split.sql", p)

@st.cache_data(ttl=600)
def load_purchase_qty(p, _cache_key):
return run_sql_file("src/sql/section1_purchase_qty_split.sql", p)

@st.cache_data(ttl=600)
def load_revenue(p, _cache_key):
return run_sql_file("src/sql/section1_revenue_split.sql", p)

@st.cache_data(ttl=600)
def load_kids_source_medium_top10(p, _cache_key):
return run_sql_file("src/sql/section2_kids_conversion_source_medium_top10.sql", p)

@st.cache_data(ttl=600)
def load_kids_top10_product_performance(p, _cache_key):
return run_sql_file("src/sql/section3_kids_top10_product_performance.sql", p)

@st.cache_data(ttl=600)
def load_kids_top10_product_views(p, _cache_key):
return run_sql_file("src/sql/section3_kids_top10_product_views.sql", p)

@st.cache_data(ttl=600)
def load_kids_revenue_top10_category(p, _cache_key):
return run_sql_file("src/sql/section4_kids_revenue_top10_category.sql", p)

@st.cache_data(ttl=600)
def load_kids_promo_top10(p, _cache_key):
return run_sql_file("src/sql/section4_kids_promo_top10.sql", p)

@st.cache_data(ttl=600)
def load_kids_cross_revenue(p, _cache_key):
return run_sql_file("src/sql/section5_kids_revenue_cross.sql", p)

@st.cache_data(ttl=600)
def load_adult_cross_revenue(p, _cache_key):
return run_sql_file("src/sql/section5_adult_revenue_cross.sql", p)

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

def fmt_pct0(x):
try:
return f"{float(x):.0f}%"
except Exception:
return x

def fmt_pct1(x):
try:
return f"{float(x):.1f}%"
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

if pct_cols:
for c in pct_cols:
if c in out.columns:
if pct_decimals == 2:
out[c] = out[c].apply(fmt_pct2)
elif pct_decimals == 1:
out[c] = out[c].apply(fmt_pct1)
else:
out[c] = out[c].apply(fmt_pct0)

return out

# ======================
# ✅ KPI 100% 가로 누적 막대 (두께 업)
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
color=alt.Color(
"유형:N",
scale=alt.Scale(domain=order, range=palette),
legend=alt.Legend(title=None)
),
tooltip=[
alt.Tooltip("유형:N", title="유형"),
alt.Tooltip("비중:Q", title="비중(%)", format=".2f"),
alt.Tooltip("값:Q", title="값", format=",")
]
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
# ✅ 섹션5: 교차 구매 비중도 100% 가로 누적 막대로 시각화 + %/원 표시
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
color=alt.Color(
"유형:N",
scale=alt.Scale(domain=order, range=palette),
legend=alt.Legend(title=None)
),
tooltip=[
alt.Tooltip("유형:N", title="유형"),
alt.Tooltip("비중:Q", title="비중(%)", format=".2f"),
alt.Tooltip("값:Q", title="매출(원)", format=",")
]
)
.properties(height=160)
)

st.altair_chart(chart, use_container_width=True)

for r in rows:
st.write(f"• **{r['유형']}** : {r['비중']:.0f}% ({int(r['값']):,}원)")

# ======================
# 컬럼명 한글 매핑
# ✅ 변경: 소스/매체 TOP10 테이블에 사용자수(USERS) 추가
# ✅ 변경: 기획전 TOP10 테이블에 URL(PROMO_URL) 추가
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

# ✅ promo_url을 LinkColumn으로 쓸거라 컬럼 유지
COLMAP_KIDS_PROMO = {
"RANK": "순위",
"PROMO_NO": "구분",
"PROMO_NAME": "기획전명",
    "PROMO_URL": "기획전 URL",  # ✅ 추가
    "PROMO_URL": "기획전 링크",   # ✅ LinkColumn 대상
"PROMO_SESSIONS": "유입",
"VIEW_SESSIONS": "상품 조회",
"PURCHASE_SESSIONS": "구매",
"PURCHASE_CVR_PCT": "CVR",
"REVENUE": "매출",
}

# ======================
# 실행
# ======================
if st.button("조회"):
with st.spinner("데이터 조회 중..."):
users_df = load_users(params, cache_day_key)
qty_df = load_purchase_qty(params, cache_day_key)
revenue_df = load_revenue(params, cache_day_key)

kids_sm_df = load_kids_source_medium_top10(params, cache_day_key)
kids_perf_df = load_kids_top10_product_performance(params, cache_day_key)
kids_views_df = load_kids_top10_product_views(params, cache_day_key)
kids_cat_df = load_kids_revenue_top10_category(params, cache_day_key)
kids_promo_df = load_kids_promo_top10(params, cache_day_key)

kids_cross_df = load_kids_cross_revenue(params, cache_day_key)
adult_cross_df = load_adult_cross_revenue(params, cache_day_key)

col1, col2, col3 = st.columns(3)

with col1:
st.subheader("총 사용자수")
st.caption("*전체 기준")
render_kpi_100pct_bar(
users_df,
value_col="USERS",
order=["Non-paid", "키즈 광고", "성인 광고"],
value_unit="명"
)

with col2:
st.subheader("구매한 상품 (구매수)")
st.caption("*키즈 전환 기준")
render_kpi_100pct_bar(
qty_df,
value_col="PURCHASE_QTY",
order=["키즈 광고가 아닌것", "키즈 광고"],
value_unit="건"
)

with col3:
st.subheader("상품 수익 (매출)")
st.caption("*키즈 전환 기준")
render_kpi_100pct_bar(
revenue_df,
value_col="REVENUE",
order=["키즈 광고가 아닌것", "키즈 광고"],
value_unit="원"
)

    # 1) 키즈 상품 기준 소스/매체 성과 TOP 10
st.divider()
st.subheader("키즈 상품 기준 소스/매체 성과 TOP 10")
st.caption("*키즈 상품(상품ID 7%)을 1회 이상 조회 또는 구매한 사용자 기준")

kids_sm_show = format_df_for_display(
kids_sm_df,
money_cols=["REVENUE", "revenue"],
int_cols=["USERS", "users", "SESSIONS", "sessions"]
)
if kids_sm_show is not None and not kids_sm_show.empty:
kids_sm_show = kids_sm_show.rename(columns=COLMAP_KIDS_SM)
st.dataframe(kids_sm_show, use_container_width=True, hide_index=True)

    # 2) 키즈 Top10 상품 성과 / 3) 키즈 상품 조회수 Top10
st.divider()
left, right = st.columns(2)

with left:
st.subheader("키즈 TOP 10 상품 성과")
kids_perf_show = format_df_for_display(
kids_perf_df,
money_cols=["REVENUE", "revenue"],
int_cols=["QUANTITY", "quantity", "RANK", "rank"]
)
if kids_perf_show is not None and not kids_perf_show.empty:
kids_perf_show = kids_perf_show.rename(columns=COLMAP_KIDS_PERF)
st.dataframe(kids_perf_show, use_container_width=True, hide_index=True)

with right:
st.subheader("키즈 상품 조회수 TOP 10")
kids_views_show = format_df_for_display(
kids_views_df,
int_cols=["VIEW_COUNT", "view_count", "RANK", "rank"]
)
if kids_views_show is not None and not kids_views_show.empty:
kids_views_show = kids_views_show.rename(columns=COLMAP_KIDS_VIEWS)
st.dataframe(kids_views_show, use_container_width=True, hide_index=True)

    # 4) 키즈 매출 Top10 카테고리 / 5) 키즈 기획전 Top10 (✅ LinkColumn 적용)
st.divider()
left2, right2 = st.columns(2)

with left2:
st.subheader("키즈 매출 TOP 10 카테고리")
kids_cat_show = format_df_for_display(
kids_cat_df,
money_cols=["REVENUE", "revenue"],
int_cols=["QUANTITY", "quantity", "RANK", "rank"]
)
if kids_cat_show is not None and not kids_cat_show.empty:
kids_cat_show = kids_cat_show.rename(columns=COLMAP_KIDS_CAT)
st.dataframe(kids_cat_show, use_container_width=True, hide_index=True)

with right2:
st.subheader("키즈 기획전 TOP 10")

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

            # ✅ 기획전명에 행별 하이퍼링크 적용
            if "기획전 URL" in kids_promo_show.columns and "기획전명" in kids_promo_show.columns:
                kids_promo_show["기획전명"] = kids_promo_show.apply(
                    lambda r: f"[{r['기획전명']}]({r['기획전 URL']})"
                    if pd.notna(r["기획전 URL"]) and str(r["기획전 URL"]).strip() != ""
                    else r["기획전명"],
                    axis=1
                )
                # URL 컬럼은 표에서 숨김(원하면 drop 제거)
                kids_promo_show = kids_promo_show.drop(columns=["기획전 URL"])

        st.dataframe(kids_promo_show, use_container_width=True, hide_index=True)
            # ✅ 클릭 가능한 링크 컬럼 (새 탭/새 창은 브라우저 설정에 따름)
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

    # 교차 구매 비중
st.divider()
st.subheader("키즈/성인 광고 통한 교차 구매 비중")

box_l, box_r = st.columns(2)

with box_l:
render_cross_box("키즈 매출", kids_cross_df)

with box_r:
render_cross_box("성인 매출", adult_cross_df)

else:
st.info("기간 선택 후 ‘조회’를 눌러주세요.")