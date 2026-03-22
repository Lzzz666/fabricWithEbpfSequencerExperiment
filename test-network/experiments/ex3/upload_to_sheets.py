import glob
import os
import re
import pandas as pd
import gspread
from google.oauth2.service_account import Credentials

# ── Config ────────────────────────────────────────────────────────────────────
SPREADSHEET_ID = "14QDRxciJry2z53uaZfXregyubgnEYA8V-zl-3RFFeeU"
JSON_KEY       = os.path.join(os.path.dirname(__file__), "gen-lang-client-0837760906-b11be594a0aa.json")
CSV_DIR        = os.path.dirname(__file__)   # same folder as this script
SHEET_NAME     = "Sheet1"                    # change if your sheet tab has a different name
# ─────────────────────────────────────────────────────────────────────────────

SCOPES = ["https://www.googleapis.com/auth/spreadsheets"]

def load_csv_stats(csv_dir: str) -> pd.DataFrame:
    rows = []
    pattern = os.path.join(csv_dir, "latency_peer*_*.csv")
    for f in sorted(glob.glob(pattern)):
        basename = os.path.basename(f).replace(".csv", "")
        # expected format: latency_peer1_1000
        m = re.match(r"latency_(peer\d+)_(\d+)", basename)
        if not m:
            print(f"  [skip] unrecognised filename: {basename}")
            continue
        peer = m.group(1)
        rps  = int(m.group(2))

        df = pd.read_csv(f)
        if df.empty:
            print(f"  [skip] empty file: {basename}")
            continue

        rows.append({
            "RPS":          rps,
            "Peer":         peer,
            "Endorse P50 (ms)": round(df["endorse_ms"].quantile(0.50), 3),
            "Endorse P95 (ms)": round(df["endorse_ms"].quantile(0.95), 3),
            "Endorse P99 (ms)": round(df["endorse_ms"].quantile(0.99), 3),
            "Endorse Avg (ms)": round(df["endorse_ms"].mean(),          3),
            "Commit P50 (ms)":  round(df["commit_ms"].quantile(0.50),  3),
            "Commit P95 (ms)":  round(df["commit_ms"].quantile(0.95),  3),
            "Commit P99 (ms)":  round(df["commit_ms"].quantile(0.99),  3),
            "Commit Avg (ms)":  round(df["commit_ms"].mean(),           3),
            "Success":          len(df),
        })
        print(f"  loaded: {basename}  ({len(df)} records)")

    if not rows:
        raise RuntimeError("No matching CSV files found.")

    return pd.DataFrame(rows).sort_values(["RPS", "Peer"]).reset_index(drop=True)


def upload(df: pd.DataFrame):
    creds  = Credentials.from_service_account_file(JSON_KEY, scopes=SCOPES)
    client = gspread.authorize(creds)
    sheet  = client.open_by_key(SPREADSHEET_ID).worksheet(SHEET_NAME)

    # clear existing content
    sheet.clear()

    # write header + data
    header = df.columns.tolist()
    data   = df.values.tolist()
    sheet.update([header] + data, value_input_option="USER_ENTERED")

    print(f"\nUploaded {len(df)} rows to '{SHEET_NAME}'.")


if __name__ == "__main__":
    print("=== Collecting CSV stats ===")
    df = load_csv_stats(CSV_DIR)
    print(f"\n{df.to_string(index=False)}\n")

    print("=== Uploading to Google Sheets ===")
    upload(df)
