import pandas as pd
import yfinance as yf
from pathlib import Path
from datetime import datetime

BASE_DIR = Path(__file__).resolve().parent
DATA_XLSX = BASE_DIR / "Data.xlsx"
OUTPUT_XLSX = BASE_DIR / "etf_adjclose_only.xlsx"

TICKERS = ["QQQ", "TQQQ", "SQQQ", "QLD", "QID"]
START_DATE = "2015-01-01"

def download_prices():
    all_data = []

    for ticker in TICKERS:
        print(f"Downloading {ticker}...")
        df = yf.download(
            ticker,
            start=START_DATE,
            end=None,
            auto_adjust=False,
            progress=False
        )

        if df.empty:
            raise ValueError(f"No data returned for {ticker}")

        if isinstance(df.columns, pd.MultiIndex):
            df.columns = df.columns.get_level_values(0)

        df = df[["Adj Close"]].copy().reset_index()
        df = df.rename(columns={"Adj Close": ticker})
        all_data.append(df)

    merged = all_data[0]
    for df in all_data[1:]:
        merged = pd.merge(merged, df, on="Date", how="outer")

    merged = merged.sort_values("Date").reset_index(drop=True)
    return merged

def save_outputs(merged: pd.DataFrame):
    merged.to_excel(OUTPUT_XLSX, index=False)

    with pd.ExcelWriter(DATA_XLSX, engine="openpyxl") as writer:
        merged.to_excel(writer, sheet_name="DATA", index=False)

    print(f"Saved: {OUTPUT_XLSX}")
    print(f"Saved: {DATA_XLSX}")

def main():
    print(f"Run started: {datetime.now().isoformat(timespec='seconds')}")
    merged = download_prices()
    save_outputs(merged)
    print("Update finished successfully.")

if __name__ == "__main__":
    main()
