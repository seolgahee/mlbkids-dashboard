
return out

# ======================
# Raw Data 토글 출력
# ======================
def show_raw(df, label="Raw Data"):
    with st.expander(label, expanded=False):
        st.dataframe(df, use_container_width=True, hide_index=True)

# ======================
# 섹션5 카드 출력(비중 + 괄호 매출)
@@ -198,7 +192,7 @@ def render_cross_box(title: str, df: pd.DataFrame):
rev = m.get(k, {}).get("rev", 0)
st.write(f"{k} {fmt_pct(pct)} ({fmt_won(rev)})")

    show_raw(df, "Raw Data (교차 구매)")
  

# ======================
# 실행
@@ -225,17 +219,17 @@ def render_cross_box(title: str, df: pd.DataFrame):
with col1:
st.subheader("총 사용자수")
render_kpi(users_df, value_col="USERS", order=["Non-paid", "키즈 광고", "성인 광고"])
        show_raw(users_df, "Raw Data (총 사용자수)")
       

with col2:
st.subheader("구매한 상품 (구매수)")
render_kpi(qty_df, value_col="PURCHASE_QTY", order=["키즈 광고가 아닌것", "키즈 광고"])
        show_raw(qty_df, "Raw Data (구매수)")
      

with col3:
st.subheader("상품 수익 (매출)")
render_kpi(revenue_df, value_col="REVENUE", order=["키즈 광고가 아닌것", "키즈 광고"])
        show_raw(revenue_df, "Raw Data (매출)")
      

st.divider()
st.subheader("키즈 전환 상품 기준 상세 유입 소스/매체 TOP 10")
@@ -245,7 +239,6 @@ def render_cross_box(title: str, df: pd.DataFrame):
int_cols=["SESSIONS", "sessions"]
)
st.dataframe(kids_sm_show, use_container_width=True, hide_index=True)
    show_raw(kids_sm_df, "Raw Data (소스/매체 TOP10)")

st.divider()
left, right = st.columns(2)
@@ -258,7 +251,7 @@ def render_cross_box(title: str, df: pd.DataFrame):
int_cols=["QUANTITY", "quantity", "RANK", "rank"]
)
st.dataframe(kids_perf_show, use_container_width=True, hide_index=True)
        show_raw(kids_perf_df, "Raw Data (상품 성과 TOP10)")
       

with right:
st.subheader("키즈 상품 조회수 Top10")
@@ -267,7 +260,7 @@ def render_cross_box(title: str, df: pd.DataFrame):
int_cols=["VIEW_COUNT", "view_count", "RANK", "rank"]
)
st.dataframe(kids_views_show, use_container_width=True, hide_index=True)
        show_raw(kids_views_df, "Raw Data (상품 조회수 TOP10)")
        

st.divider()
left2, right2 = st.columns(2)
@@ -280,7 +273,7 @@ def render_cross_box(title: str, df: pd.DataFrame):
int_cols=["QUANTITY", "quantity", "RANK", "rank"]
)
st.dataframe(kids_cat_show, use_container_width=True, hide_index=True)
        show_raw(kids_cat_df, "Raw Data (카테고리 TOP10)")
       

with right2:
st.subheader("키즈 기획전 Top10")
@@ -296,7 +289,7 @@ def render_cross_box(title: str, df: pd.DataFrame):
pct_cols=["PURCHASE_CVR_PCT", "purchase_cvr_pct"]
)
st.dataframe(kids_promo_show, use_container_width=True, hide_index=True)
        show_raw(kids_promo_df, "Raw Data (기획전 TOP10)")
      

st.divider()
st.subheader("키즈/성인 광고 통한 교차 구매 비중")