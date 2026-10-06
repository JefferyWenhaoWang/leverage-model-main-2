import pandas as pd
import numpy as np

# ============================================================
# Parameter settings (modifiable)
# ============================================================
FILE_PATH = "Data.xlsx"
OUTPUT_PATH = "CASE_SQQQ_BAND_Python.xlsx"

INITIAL_EQUITY = 1_000_000.0
L_MIN = 3.0
L_MAX = 3.3
L_INIT = 3.0

# ============================================================
# 1. Read price data
# ============================================================

df_data = pd.read_excel(FILE_PATH, sheet_name="DATA", parse_dates=["Date"])

prices = df_data[["Date", "QQQ", "TQQQ", "SQQQ"]].copy()
prices = prices.rename(columns={
    "QQQ": "QQQ_Price",
    "TQQQ": "TQQQ_Price",
    "SQQQ": "SQQQ_Price"
})

prices = prices.sort_values("Date").reset_index(drop=True)
n = len(prices)

sqqq = prices["SQQQ_Price"].values

# ============================================================
# 2. Initialize result arrays
# ============================================================
shares_prev    = np.zeros(n)
pos_pre        = np.zeros(n)
equity_pre     = np.zeros(n)
leverage_pre   = np.zeros(n)
shares_new     = np.zeros(n)
trade_shares   = np.zeros(n)
trade_cashflow = np.zeros(n)
cash_new       = np.zeros(n)
pos_new        = np.zeros(n)
equity_new     = np.zeros(n)
leverage_final = np.zeros(n)

# ============================================================
# 3. Day 0 initialization
# ============================================================
shares_init = -L_INIT * INITIAL_EQUITY / (3.0 * sqqq[0])
pos_init    = shares_init * sqqq[0]
cash_init   = INITIAL_EQUITY - pos_init

shares_prev[0]    = shares_init
pos_pre[0]        = pos_init
equity_pre[0]     = INITIAL_EQUITY
leverage_pre[0]   = -3.0 * pos_init / INITIAL_EQUITY

shares_new[0]     = shares_init
trade_shares[0]   = 0.0
trade_cashflow[0] = 0.0
cash_new[0]       = cash_init
pos_new[0]        = pos_init
equity_new[0]     = INITIAL_EQUITY
leverage_final[0] = leverage_pre[0]

# ============================================================
# 4. Daily simulation loop
# ============================================================
for t in range(1, n):
    shares_prev[t] = shares_new[t - 1]
    prev_cash      = cash_new[t - 1]

    pos_pre[t]    = shares_prev[t] * sqqq[t]
    equity_pre[t] = prev_cash + pos_pre[t]

    if equity_pre[t] <= 0:
        leverage_pre[t]   = np.nan
        shares_new[t]     = shares_prev[t]
        trade_shares[t]   = 0.0
        trade_cashflow[t] = 0.0
        cash_new[t]       = prev_cash
        pos_new[t]        = pos_pre[t]
        equity_new[t]     = equity_pre[t]
        leverage_final[t] = np.nan
        continue

    leverage_pre[t] = -3.0 * pos_pre[t] / equity_pre[t]

    if leverage_pre[t] < L_MIN:
        target_lev = L_MIN
    elif leverage_pre[t] > L_MAX:
        target_lev = L_MAX
    else:
        target_lev = None

    if target_lev is not None:
        shares_new[t]     = -target_lev * equity_pre[t] / (3.0 * sqqq[t])
        trade_shares[t]   = shares_new[t] - shares_prev[t]
        trade_cashflow[t] = -trade_shares[t] * sqqq[t]
        cash_new[t]       = prev_cash + trade_cashflow[t]
        pos_new[t]        = shares_new[t] * sqqq[t]
        equity_new[t]     = cash_new[t] + pos_new[t]
        leverage_final[t] = -3.0 * pos_new[t] / equity_new[t]
    else:
        shares_new[t]     = shares_prev[t]
        trade_shares[t]   = 0.0
        trade_cashflow[t] = 0.0
        cash_new[t]       = prev_cash
        pos_new[t]        = pos_pre[t]
        equity_new[t]     = equity_pre[t]
        leverage_final[t] = leverage_pre[t]

# ============================================================
# 5. Build result DataFrame
# ============================================================
result = pd.DataFrame({
    "Date":           prices["Date"],
    "QQQ_Price":      prices["QQQ_Price"],
    "TQQQ_Price":     prices["TQQQ_Price"],
    "SQQQ_Price":     prices["SQQQ_Price"],
    "Shares_prev":    shares_prev,
    "Pos_pre":        pos_pre,
    "Equity_pre":     equity_pre,
    "Leverage_pre":   leverage_pre,
    "Shares_new":     shares_new,
    "Trade_Shares":   trade_shares,
    "Trade_CashFlow": trade_cashflow,
    "Cash_new":       cash_new,
    "Pos_new":        pos_new,
    "Equity_new":     equity_new,
    "Leverage":       leverage_final
})

# ============================================================
# 6. Save output
# ============================================================
result.to_excel(OUTPUT_PATH, index=False, sheet_name="CASE_SQQQ_BAND")
print(f"Result saved to: {OUTPUT_PATH}")

# ============================================================
# 7. Output summary statistics
# ============================================================
print(f"\nResult shape: {result.shape}")
print(f"\nFirst 10 rows:\n{result.head(10).to_string()}")
print(f"\nLast 5 rows:\n{result.tail(5).to_string()}")

print(f"\nLeverage statistics:")
print(f"  min  = {result['Leverage'].min():.6f}")
print(f"  max  = {result['Leverage'].max():.6f}")
print(f"  mean = {result['Leverage'].mean():.6f}")

print(f"\nFinal equity value: {result['Equity_new'].iloc[-1]:,.2f}")
