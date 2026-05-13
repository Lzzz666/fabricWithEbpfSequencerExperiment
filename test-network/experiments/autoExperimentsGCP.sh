#!/usr/bin/env bash

###############################################################################
# GCP Experiment Loop Script (Raft)
#
# 從本機執行，透過 SSH 控制 GCP VM：
#   1. Deploy (帶起節點、join channel、安裝 chaincode、init ledger)
#   2. 在 peer0 上執行 ex1 (transaction sender)
#   3. 在 peer2 上執行 TPSmeasure (TPS monitor)
#   4. 等待結果，重複下一輪
#
# 前提：
#   - 本機已設定好 SSH key-based auth 到所有 GCP VM (user: lz)
#   - GCP VM 上已有 Go 環境 (/usr/local/go/bin/go)
#   - GCP VM 上已 clone repo 至 ~/fabricWithEbpfSequencerExperiment
###############################################################################

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SSH_USER="lz"
REMOTE_BASE="~/fabricWithEbpfSequencerExperiment/test-network"
DEPLOY_SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/boostrapScripts/autoDeployment/autoDeploymentGCP-Raft.sh"

# GCP VM 外部 IP
declare -A VMS
VMS["orderer0"]="107.167.190.170"
VMS["orderer1"]="34.80.16.63"
VMS["orderer2"]="34.80.230.24"
VMS["orderer3"]="34.80.174.19"
VMS["peer0"]="34.80.247.165"
VMS["peer1"]="35.221.173.215"
VMS["peer2"]="34.80.216.59"

SUCCESS_MSG="committed with status (VALID)"

# 顏色
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_step()  { echo -e "\n${YELLOW}=============================================${NC}\n$1\n${YELLOW}=============================================${NC}"; }

# SSH 執行 (blocking)
run_ssh() {
    local vm=$1
    local cmd=$2
    local ip="${VMS[$vm]}"
    echo -e "${BLUE}[$vm @ $ip]${NC} $cmd"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$ip" "$cmd"
}

# SSH 執行 (non-blocking, background)
run_ssh_bg() {
    local vm=$1
    local cmd=$2
    local ip="${VMS[$vm]}"
    echo -e "${BLUE}[$vm @ $ip]${NC} (bg) $cmd"
    ssh -n -f -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$ip" "$cmd"
}

# 執行 GCP 部署並回傳是否成功
deploy_gcp() {
    local output
    output=$(bash "$DEPLOY_SCRIPT" --yes 2>&1)
    echo "$output"
    if echo "$output" | grep -q "$SUCCESS_MSG"; then
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Main experiment loop
# t: 重複次數
# i: RPS 倍率 (每次 RPS = 250 * i)
# -----------------------------------------------------------------------------

for ((t=1; t<=5; t++)); do
    for ((i=20; i>=1; i--)); do
        log_step "Experiment t=$t, i=$i | RPS=$((250*i))"

        # Step 1: Deploy
        log_info "執行 GCP 部署..."
        while true; do
            if deploy_gcp; then
                log_ok "部署成功"
                break
            else
                log_info "部署失敗，10 秒後重試..."
                sleep 10
            fi
        done

        sleep 5

        # Step 2: 在 peer0 執行 ex1 (transaction sender)
        log_info "在 peer0 啟動 ex1 (RPS=$((250*i)))..."
        run_ssh_bg "peer0" \
            "cd ${REMOTE_BASE}/experiments/ex1 && \
             export GO111MODULE=on && \
             go mod tidy && \
             nohup /usr/local/go/bin/go run . $((250*i)) \
             > raft_gcp_latency_${i}_c${t}.log 2>&1 &"

        # Step 3: 等 10 秒讓 ex1 先開始送 tx
        log_info "等待 10 秒..."
        sleep 10

        # Step 4: 在 peer2 執行 TPSmeasure (TPS monitor)
        log_info "在 peer2 啟動 TPSmeasure..."
        run_ssh_bg "peer2" \
            "cd ${REMOTE_BASE}/experiments/TPSmeasure && \
             nohup /usr/local/go/bin/go run . \
             > raft_gcp_tps_${i}_c${t}.log 2>&1 &"

        # Step 5: 等待實驗完成
        log_info "等待 90 秒讓實驗跑完..."
        sleep 90

        log_ok "完成 iteration t=$t, i=$i"
    done
done

# -----------------------------------------------------------------------------
# Completion
# -----------------------------------------------------------------------------

echo ""
echo "==============================================================="
echo " All experiment iterations completed!"
echo "==============================================================="
