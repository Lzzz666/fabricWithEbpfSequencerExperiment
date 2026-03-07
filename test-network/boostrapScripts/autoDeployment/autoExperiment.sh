#!/usr/bin/env bash

###############################################################################
# Auto Experiment Script for GCP NOPaxos
#
# 每輪 RPS 的完整流程：
#   1. cleanupAll.sh 清理所有 VM
#   2. autoDeploymentGCP.sh 部署（失敗則重試）
#   3. initLedger 初始化帳本
#   4. 啟動 sequencer
#   5. peer0 執行 ex1（背景）
#   6. 等 10 秒
#   7. peer2 執行 TPSmeasure（同步，10s timeout 後自動結束）
#   8. 收集結果
#   9. kill ex1、kill sequencer
#   → 下一輪
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SSH_USER="lz"

# ─── GCP VM IPs ───────────────────────────────────────────────────────────────
PEER0_IP="34.80.136.133"    # ex1 benchmark 來源
PEER2_IP="104.199.189.201"   # TPSmeasure 監聽 peer2
SEQUENCER_IP="104.199.155.71"

# ─── 實驗參數 ─────────────────────────────────────────────────────────────────
RPS_LIST=(1000 1500 1800 2000 2500 2800 3000)

SEQUENCER_ORDERER_COUNT=4

# ─── 遠端路徑 ─────────────────────────────────────────────────────────────────
EXPERIMENT_PATH="~/fabricWithEbpfSequencerExperiment/test-network/experiments"
SEQUENCER_PATH="~/Fabric_batch_unit_order/sequencer"

# ─── 本地結果目錄 ──────────────────────────────────────────────────────────────
RESULT_DIR="$SCRIPT_DIR/results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_DIR"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${YELLOW}========== $1 ==========${NC}\n"; }

run_ssh() {
    local ip=$1
    local cmd=$2
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$SSH_USER@$ip" "$cmd"
}

# ─── 部署函數（含重試）────────────────────────────────────────────────────────
do_deploy() {
    local MAX_RETRIES=5
    for ((retry=1; retry<=MAX_RETRIES; retry++)); do
        log_info "部署嘗試 $retry/$MAX_RETRIES ..."
        if OUTPUT=$(echo "y" | bash "$SCRIPT_DIR/autoDeploymentGCP.sh" 2>&1); then
            echo "$OUTPUT"
            if echo "$OUTPUT" | grep -q "部署完成"; then
                log_success "部署成功"
                return 0
            fi
        fi
        log_error "部署失敗，清理後重試..."
        echo "$OUTPUT" | tail -20
        bash "$SCRIPT_DIR/cleanupAll.sh" || true
        sleep 10
    done
    log_error "部署多次失敗"
    return 1
}

# ─── 確認 ─────────────────────────────────────────────────────────────────────
echo "=========================================="
echo " GCP NOPaxos Auto Experiment"
echo "=========================================="
echo "Peer0 (ex1):        $PEER0_IP"
echo "Peer2 (TPSmeasure): $PEER2_IP"
echo "Sequencer:          $SEQUENCER_IP"
echo "RPS list:           ${RPS_LIST[*]}"
echo "Results dir:        $RESULT_DIR"
echo ""
read -p "確定要開始實驗嗎? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "已取消"
    exit 0
fi

# ─── Summary 初始化 ───────────────────────────────────────────────────────────
SUMMARY_FILE="$RESULT_DIR/summary.txt"
echo "# NOPaxos GCP TPS Experiment - $(date)" > "$SUMMARY_FILE"
echo "# RPS, TotalBlocks, TotalTx, Duration(s), TPS" >> "$SUMMARY_FILE"

# ─── 主實驗迴圈 ───────────────────────────────────────────────────────────────
for rps in "${RPS_LIST[@]}"; do
    echo ""
    log_step "RPS = $rps"

    # 1) Cleanup
    log_info "清理所有 VM..."
    bash "$SCRIPT_DIR/cleanupAll.sh"
    log_success "清理完成"

    # 2) Deploy
    if ! do_deploy; then
        log_error "RPS=$rps 部署失敗，跳過此輪"
        echo "$rps, DEPLOY_FAILED, -, -, -" >> "$SUMMARY_FILE"
        continue
    fi

    sleep 3
done

# ─── Done ─────────────────────────────────────────────────────────────────────
log_step "All Experiments Done"
echo ""
echo "結果已儲存至: $RESULT_DIR"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "$SUMMARY_FILE"
echo ""
