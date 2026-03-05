#!/usr/bin/env bash

###############################################################################
# Auto-Deployment Script for GCP VMs (Raft)
#
# 完整部署流程：
#   1. Docker cleanup
#   2. 啟動 Orderer/Peer 節點
#   3. Join Channel
#   4. Install/Approve/Commit Chaincode
#   5. Init Ledger
#
# 使用方法:
#   ./autoDeploymentGCP-Raft.sh           # 完整部署 (interactive)
#   ./autoDeploymentGCP-Raft.sh --yes     # 跳過確認 (用於自動化)
###############################################################################

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SSH_USER="lz"

# 專案路徑 (在遠端 VM 上)
REMOTE_PATH="~/fabricWithEbpfSequencerExperiment/test-network/boostrapScripts"

# VM 外部 IP 地址
declare -A VMS
VMS["orderer0"]="34.81.30.7"
VMS["orderer1"]="34.81.10.171"
VMS["orderer2"]="35.201.198.28"
VMS["orderer3"]="34.81.170.165"
VMS["peer0"]="35.194.168.248"
VMS["peer1"]="35.221.209.220"
VMS["peer2"]="104.199.189.201"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${YELLOW}========== $1 ==========${NC}\n"; }

# SSH 執行命令
run_ssh() {
    local vm_name=$1
    local cmd=$2
    local ip="${VMS[$vm_name]}"

    echo -e "${BLUE}[$vm_name @ $ip]${NC} $cmd"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$ip" "$cmd"
}

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------

AUTO_YES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --yes|-y)
            AUTO_YES=true
            shift
            ;;
        -h|--help)
            echo "用法: $0 [--yes]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Step 0: Confirmation
# -----------------------------------------------------------------------------

echo "=========================================="
echo " GCP Auto Deployment (Raft)"
echo "=========================================="
echo "VMs:"
for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
    echo "  $vm_name: ${VMS[$vm_name]}"
done
echo ""

if [[ "$AUTO_YES" == false ]]; then
    read -p "確定要開始部署嗎? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "已取消"
        exit 0
    fi
fi

# -----------------------------------------------------------------------------
# Step 1: Docker Cleanup
# -----------------------------------------------------------------------------

log_step "Step 1: Docker Cleanup"

for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
    run_ssh "$vm_name" \
        "docker rm -f \$(docker ps -a -q) 2>/dev/null || true; \
         docker volume rm \$(docker volume ls -q) 2>/dev/null || true" || true
done

log_success "Docker cleanup 完成"
sleep 3

# -----------------------------------------------------------------------------
# Step 1.5: Create Docker Network
# -----------------------------------------------------------------------------

log_step "Step 1.5: Create Docker Network (fabric_test)"

for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
    run_ssh "$vm_name" \
        "docker network inspect fabric_test >/dev/null 2>&1 || docker network create fabric_test"
    log_info "$vm_name: fabric_test network OK"
done

log_success "Docker network 建立完成"

# -----------------------------------------------------------------------------
# Step 2: Bring Up Nodes
# -----------------------------------------------------------------------------

log_step "Step 2: Bring Up Nodes"

log_info "啟動 Orderers..."
run_ssh "orderer0" "cd ${REMOTE_PATH}/bringUpNode && ./orderer.sh"
run_ssh "orderer1" "cd ${REMOTE_PATH}/bringUpNode && ./orderer1.sh"
run_ssh "orderer2" "cd ${REMOTE_PATH}/bringUpNode && ./orderer2.sh"
run_ssh "orderer3" "cd ${REMOTE_PATH}/bringUpNode && ./orderer3.sh"

log_info "啟動 Peers..."
run_ssh "peer0" "cd ${REMOTE_PATH}/bringUpNode && ./peer.sh"
run_ssh "peer1" "cd ${REMOTE_PATH}/bringUpNode && ./peer1.sh"
run_ssh "peer2" "cd ${REMOTE_PATH}/bringUpNode && ./peer2.sh"

log_success "所有節點已啟動"
sleep 5

# -----------------------------------------------------------------------------
# Step 3: Join Channel
# -----------------------------------------------------------------------------

log_step "Step 3: Join Channel"

log_info "Orderers 加入 channel..."
run_ssh "orderer0" "cd ${REMOTE_PATH}/joinChannel && ./orderer.sh"
sleep 1
run_ssh "orderer1" "cd ${REMOTE_PATH}/joinChannel && ./orderer1.sh"
sleep 1
run_ssh "orderer2" "cd ${REMOTE_PATH}/joinChannel && ./orderer2.sh"
sleep 1
run_ssh "orderer3" "cd ${REMOTE_PATH}/joinChannel && ./orderer3.sh"

sleep 5

log_info "Peers 加入 channel..."
run_ssh "peer0" "cd ${REMOTE_PATH}/joinChannel && ./peer.sh"
sleep 1
run_ssh "peer1" "cd ${REMOTE_PATH}/joinChannel && ./peer1.sh"
sleep 1
run_ssh "peer2" "cd ${REMOTE_PATH}/joinChannel && ./peer2.sh"

log_success "所有節點已加入 channel"
sleep 5

# -----------------------------------------------------------------------------
# Step 4: Install Chaincode
# -----------------------------------------------------------------------------

log_step "Step 4: Install Chaincode"

run_ssh "peer0" "cd ${REMOTE_PATH}/CCpackage && ./peerCCInstall.sh"
run_ssh "peer1" "cd ${REMOTE_PATH}/CCpackage && ./peer1CCInstall.sh"
run_ssh "peer2" "cd ${REMOTE_PATH}/CCpackage && ./peer2CCInstall.sh"

log_success "Chaincode 已安裝"
sleep 3

# -----------------------------------------------------------------------------
# Step 5: Approve & Commit Chaincode
# -----------------------------------------------------------------------------

log_step "Step 5: Approve & Commit Chaincode"

run_ssh "peer0" "cd ${REMOTE_PATH}/CCpackage && ./approveCC.sh"
sleep 3

run_ssh "peer0" "cd ${REMOTE_PATH}/CCpackage && ./commitCC.sh"
sleep 5

log_success "Chaincode 已批准並提交"

# -----------------------------------------------------------------------------
# Step 6: Init Ledger
# -----------------------------------------------------------------------------

log_step "Step 6: Init Ledger"

run_ssh "peer0" "cd ~/fabricWithEbpfSequencerExperiment/test-network/experiments/initLedger && \
    export GO111MODULE=on && go mod tidy && go run ."

log_success "Ledger 初始化完成"

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------

echo ""
echo "=========================================="
log_success "部署完成!"
echo "=========================================="
