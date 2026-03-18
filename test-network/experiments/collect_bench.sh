#!/usr/bin/env bash
# =============================================================================
# collect_bench.sh
# 跑完實驗後執行這個 script，自動從所有 Docker container 抓 BENCH 資料，
# 顯示一張統一的 pipeline 表格，讓你一眼看出瓶頸在哪。
#
# 用法：
#   ./collect_bench.sh [seq_log_file]
#
# 範例（本地 localhost 跑法）：
#   ./collect_bench.sh /tmp/sequencer.log
#
# 如果 sequencer 跑在另一個 terminal，先這樣啟動它：
#   go run . 1 2>&1 | tee /tmp/sequencer.log
# =============================================================================

SEQ_LOG="${1:-/tmp/sequencer.log}"

# ── 顏色 ──────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YEL='\033[0;33m'; GRN='\033[0;32m'; BLU='\033[0;34m'
BLD='\033[1m'; RST='\033[0m'

# ── helper：從 docker container 的 log 抓最後一筆 BENCH_WIN 資料 ──────────────
get_win() {
  local container="$1"
  local tag="$2"      # e.g. "GW", "ORD", "NOP"
  # docker logs 常帶時間戳前綴，不能用 ^BENCH_WIN；且容器 log 多在 stderr，不可用 2>/dev/null
  docker logs "$container" 2>&1 \
    | grep "BENCH_WIN: ${tag}" \
    | tail -1
}

# ── helper：從 sequencer log 檔案抓資料 ────────────────────────────────────────
get_seq_win() {
  local logfile="$1"
  if [[ ! -f "$logfile" ]]; then
    echo ""
    return
  fi
  grep "BENCH_WIN: SEQ" "$logfile" | tail -1
}

# ── helper：從字串 "key=value" 中取出 value（macOS/BSD grep 相容）────────────
kv() {
  echo "$1" | sed -n "s/.*${2}=\([0-9.][0-9.]*\).*/\1/p"
}

# ── 抓資料 ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}=== 正在收集 BENCH 資料... ===${RST}"

# peer containers (取 peer0 + peer1 的最後一筆，加起來)
GW0=$(get_win "peer0.org1.example.com" "GW")
GW1=$(get_win "peer1.org1.example.com" "GW")

# sequencer (從 log 檔或 container，依環境而定)
# 如果 sequencer 也跑在 docker，改成：
#   SEQ_DATA=$(get_win "sequencer" "SEQ")
SEQ_DATA=$(get_seq_win "$SEQ_LOG")

# orderer containers (取 orderer0 的最後一筆)
ORD0=$(get_win "orderer.example.com"  "ORD")
NOP0=$(get_win "orderer.example.com"  "NOP")
# 如果有多個 orderer 都在記錄，也可加 orderer1 等；
# 在 nopaxos 裡只有 leader 會 WriteBlock，所以取 leader 那台。

# ── 解析數值 ──────────────────────────────────────────────────────────────────

# Stage 1: client → peer gateway (txn/s)
# peer0 和 peer1 各自收一半的 client 流量，加起來才是總 S1
s1_0=$(kv "$GW0" "s1"); s1_0=${s1_0:-0}
s1_1=$(kv "$GW1" "s1"); s1_1=${s1_1:-0}
S1=$(echo "$s1_0 $s1_1" | awk '{printf "%.1f", $1+$2}')

# Stage 2: gateway → sequencer batch RTT
s2_0=$(kv "$GW0" "s2_tps"); s2_0=${s2_0:-0}
s2_1=$(kv "$GW1" "s2_tps"); s2_1=${s2_1:-0}
S2=$(echo "$s2_0 $s2_1" | awk '{printf "%.1f", $1+$2}')
S2_RTT=$(kv "$GW0" "s2_rtt"); S2_RTT=${S2_RTT:-0}
S2_CAP=$(kv "$GW0" "s2_cap"); S2_CAP=${S2_CAP:-0}

# Stage 3 & 4: sequencer
S3=$(echo "$(kv "$SEQ_DATA" "s3_batch")" | awk '{printf "%.1f", $1*100}')  # batch/s × 100
S4=$(echo "$(kv "$SEQ_DATA" "s4_batch")" | awk '{printf "%.1f", $1*100}')
S4_LAT=$(kv "$SEQ_DATA" "s4_lat"); S4_LAT=${S4_LAT:-0}
S4_CAP=$(kv "$SEQ_DATA" "s4_cap"); S4_CAP=${S4_CAP:-0}

# Stage 5 & 6: orderer
S5=$(kv "$ORD0" "s5_tps"); S5=${S5:-0}
S6=$(kv "$ORD0" "s6_tps"); S6=${S6:-0}
S6_LAT=$(kv "$ORD0" "s6_lat"); S6_LAT=${S6_LAT:-0}

# Stage 7: nopaxos WriteBlock
S7=$(kv "$NOP0" "s7_tps"); S7=${S7:-0}
S7_LAT=$(kv "$NOP0" "s7_lat"); S7_LAT=${S7_LAT:-0}

# ── 找瓶頸：哪個 stage 的 txn/s 最低 ──────────────────────────────────────────
find_bottleneck() {
  local stages=("$S1" "$S2" "$S3" "$S4" "$S5" "$S6" "$S7")
  local labels=("S1" "S2" "S3" "S4" "S5" "S6" "S7")
  local min_tps=99999999
  local min_idx=0

  for i in "${!stages[@]}"; do
    val="${stages[$i]}"
    [[ -z "$val" || "$val" == "0" ]] && continue
    result=$(echo "$val $min_tps" | awk '{print ($1 < $2) ? "yes" : "no"}')
    if [[ "$result" == "yes" ]]; then
      min_tps="$val"
      min_idx=$i
    fi
  done

  # Cap-based bottleneck 更準確（S2, S4）
  if [[ -n "$S2_CAP" && "$S2_CAP" != "0" && -n "$S4_CAP" && "$S4_CAP" != "0" ]]; then
    result=$(echo "$S2_CAP $S4_CAP" | awk '{print ($1 < $2) ? "S2" : "S4"}')
    cap_bottleneck="$result"
  fi

  echo "$min_idx"
}

BOTTLENECK_IDX=$(find_bottleneck)

# ── flag：哪個 stage 需要標記 ───────────────────────────────────────────────────
flag() {
  local idx="$1"   # 0-based stage index
  [[ "$idx" == "$BOTTLENECK_IDX" ]] && echo "  ← ⚠ TPS 最低點" || echo ""
}

# cap_flag: 如果 cap 是所有 cap 裡最小的
cap_flag_s2() {
  [[ -n "$S2_CAP" && -n "$S4_CAP" && "$S2_CAP" != "0" && "$S4_CAP" != "0" ]] && \
    echo "$S2_CAP $S4_CAP" | awk '{if($1<$2) print "  ← ⚠ 理論上限最低"}'
}
cap_flag_s4() {
  [[ -n "$S2_CAP" && -n "$S4_CAP" && "$S2_CAP" != "0" && "$S4_CAP" != "0" ]] && \
    echo "$S2_CAP $S4_CAP" | awk '{if($2<$1) print "  ← ⚠ 理論上限最低"}'
}

s6_warn=""
if [[ -n "$S6_LAT" ]] && echo "$S6_LAT" | awk '{exit ($1 > 1.0) ? 0 : 1}'; then
  s6_warn="  ← ⚠ >1ms! nopaxos 積壓"
fi
s7_warn=""
if [[ -n "$S7_LAT" ]] && echo "$S7_LAT" | awk '{exit ($1 > 10.0) ? 0 : 1}'; then
  s7_warn="  ← ⚠ 高! 磁碟/gossip 積壓"
fi

# ── 印出統一表格 ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}╔══════════════════════════════════════════════════════════════════════════╗${RST}"
echo -e "${BLD}║            Pipeline Throughput Summary (last 5s window)                ║${RST}"
echo -e "${BLD}╠═══════╦══════════════════════════╦══════════════╦══════════════════════╣${RST}"
printf "${BLD}║ Stage ║ 這一段在算什麼           ║   txn/s      ║ 延遲 / 上限          ║${RST}\n"
echo -e "${BLD}╠═══════╬══════════════════════════╬══════════════╬══════════════════════╣${RST}"

# S1
s1_mark=$(flag 0)
printf "║  S1   ║ Client → Peer Gateway    ║ %8s/s   ║ (你的目標 RPS)       ║%s\n" \
  "$S1" "$s1_mark"

# S2
s2_mark=$(flag 1)
cap2_mark=$(cap_flag_s2)
printf "║  S2   ║ Peer Gateway → Sequencer ║ %8s/s   ║ RTT=%5sms cap=%s/s║%s%s\n" \
  "$S2" "$S2_RTT" "$S2_CAP" "$s2_mark" "$cap2_mark"

echo -e "╠═══════╬══════════════════════════╬══════════════╬══════════════════════╣"

# S3
s3_mark=$(flag 2)
printf "║  S3   ║ Sequencer 收到           ║ %8s/s   ║                      ║%s\n" \
  "$S3" "$s3_mark"

# S4
s4_mark=$(flag 3)
cap4_mark=$(cap_flag_s4)
printf "║  S4   ║ Sequencer → Orderer      ║ %8s/s   ║ Lat=%5sms cap=%s/s║%s%s\n" \
  "$S4" "$S4_LAT" "$S4_CAP" "$s4_mark" "$cap4_mark"

echo -e "╠═══════╬══════════════════════════╬══════════════╬══════════════════════╣"

# S5
s5_mark=$(flag 4)
printf "║  S5   ║ Orderer 收到             ║ %8s/s   ║                      ║%s\n" \
  "$S5" "$s5_mark"

# S6
s6_mark=$(flag 5)
printf "║  S6   ║ Orderer OrderBatch       ║ %8s/s   ║ Lat=%5sms           ║%s%s\n" \
  "$S6" "$S6_LAT" "$s6_mark" "$s6_warn"

echo -e "╠═══════╬══════════════════════════╬══════════════╬══════════════════════╣"

# S7
s7_mark=$(flag 6)
printf "║  S7   ║ * WriteBlock (COMMIT)   ║ %8s/s   ║ Lat=%5sms           ║%s%s\n" \
  "$S7" "$S7_LAT" "$s7_mark" "$s7_warn"

echo -e "${BLD}╚═══════╩══════════════════════════╩══════════════╩══════════════════════╝${RST}"

echo ""
echo -e "${BLD}=== 如何看這張表 ===${RST}"
echo " • S7 txn/s 是最終 commit 速率，應該接近你的目標 RPS"
echo " • 從 S1 往下找第一個 txn/s 明顯掉下去的地方 → 那就是瓶頸"
echo " • S2/S4 有「cap」: 這是 RTT/Lat 決定的理論上限，若 S1 > cap 就是被這段卡住"
echo " • S6 Lat 應 < 1ms；S7 Lat 應 < 10ms"
echo ""

# ── 原始 BENCH_WIN 行（方便 debug）────────────────────────────────────────────
echo -e "${BLU}=== Raw BENCH_WIN lines ===${RST}"
[[ -n "$GW0"     ]] && echo "peer0  : $GW0"
[[ -n "$GW1"     ]] && echo "peer1  : $GW1"
[[ -n "$SEQ_DATA" ]] && echo "seq    : $SEQ_DATA"
[[ -n "$ORD0"    ]] && echo "orderer: $ORD0"
[[ -n "$NOP0"    ]] && echo "nopaxos: $NOP0"
echo ""
