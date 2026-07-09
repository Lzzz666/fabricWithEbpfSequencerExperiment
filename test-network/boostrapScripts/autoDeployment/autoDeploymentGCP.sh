#!/usr/bin/env bash

###############################################################################
# Auto-Deployment Script for GCP VMs
#
# 完整部署流程：
#   1. Docker cleanup
#   2. Pull latest images (從 Docker Hub)
#   3. 啟動 Orderer/Peer 節點
#   4. Join Channel
#   5. Install/Approve/Commit Chaincode
#
# 使用方法:
#   ./autoDeploymentGCP.sh           # 完整部署
#   ./autoDeploymentGCP.sh --skip-pull  # 跳過 image 拉取
###############################################################################

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SSH_USER="lz"
DOCKER_USER="lzyu"
IMAGE_VERSION="latest"

# 專案路徑
REMOTE_PATH="~/fabricWithEbpfSequencerExperiment/test-network/boostrapScripts"



# VM IP 地址配置
declare -A VMS
VMS["orderer0"]="104.199.212.243"
VMS["orderer1"]="130.211.246.135"
VMS["orderer2"]="104.199.158.220"
VMS["orderer3"]="35.185.128.74"
VMS["peer0"]="34.80.228.213"
VMS["peer1"]="34.80.78.13"
VMS["peer2"]="35.229.158.140"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${YELLOW}========== $1 ==========${NC}\n"; }

# SSH 執行命令
run_ssh() {
    local vm_name=$1
    local cmd=$2
    local ip="${VMS[$vm_name]}"

    echo -e "${BLUE}[$vm_name @ $ip]${NC} $cmd"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$ip" "export PATH=\$PATH:/usr/local/go/bin:~/Fabric_batch_unit_order/scripts/bin && $cmd"
}

# 在所有 VM 上執行命令
run_all() {
    local cmd=$1
    for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
        # 在遠程 VM 上設置 PATH 並執行命令
        run_ssh "$vm_name" "$cmd" || true
    done
}

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------

SKIP_PULL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-pull)
            SKIP_PULL=true
            shift
            ;;
        -h|--help)
            echo "用法: $0 [--skip-pull]"
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
echo " GCP Auto Deployment"
echo "=========================================="
echo "VMs:"
for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
    echo "  $vm_name: ${VMS[$vm_name]}"
done
echo ""
echo "Skip image pull: $SKIP_PULL"
echo ""


# -----------------------------------------------------------------------------
# Step 1: Bring Up Nodes
# -----------------------------------------------------------------------------

log_step "Step 3: Bring Up Nodes"

# Orderers
log_info "啟動 Orderers..."
run_ssh "orderer0" "cd ${REMOTE_PATH}/bringUpNode && ./orderer.sh"
run_ssh "orderer1" "cd ${REMOTE_PATH}/bringUpNode && ./orderer1.sh"
run_ssh "orderer2" "cd ${REMOTE_PATH}/bringUpNode && ./orderer2.sh"
run_ssh "orderer3" "cd ${REMOTE_PATH}/bringUpNode && ./orderer3.sh"

# Peers
log_info "啟動 Peers..."
run_ssh "peer0" "cd ${REMOTE_PATH}/bringUpNode && ./peer.sh"
run_ssh "peer1" "cd ${REMOTE_PATH}/bringUpNode && ./peer1.sh"
run_ssh "peer2" "cd ${REMOTE_PATH}/bringUpNode && ./peer2.sh"

log_success "所有節點已啟動"
sleep 5

# -----------------------------------------------------------------------------
# Step 4: Join Channel
# -----------------------------------------------------------------------------

log_step "Step 4: Join Channel"

# Orderers join
log_info "Orderers 加入 channel..."
run_ssh "orderer0" "cd ${REMOTE_PATH}/joinChannel && ./orderer.sh"
sleep 1
run_ssh "orderer1" "cd ${REMOTE_PATH}/joinChannel && ./orderer1.sh"
sleep 1
run_ssh "orderer2" "cd ${REMOTE_PATH}/joinChannel && ./orderer2.sh"
sleep 1
run_ssh "orderer3" "cd ${REMOTE_PATH}/joinChannel && ./orderer3.sh"

sleep 5

# Peers join
log_info "Peers 加入 channel..."
run_ssh "peer0" "cd ${REMOTE_PATH}/joinChannel && ./peer.sh"
sleep 1
run_ssh "peer1" "cd ${REMOTE_PATH}/joinChannel && ./peer1.sh"
sleep 1
run_ssh "peer2" "cd ${REMOTE_PATH}/joinChannel && ./peer2.sh"

log_success "所有節點已加入 channel"
sleep 10

# -----------------------------------------------------------------------------
# Step 5: Install Chaincode
# -----------------------------------------------------------------------------

log_step "Step 5: Install Chaincode"

run_ssh "peer0" "cd ${REMOTE_PATH}/CCpackage && ./peerCCInstall.sh"
run_ssh "peer1" "cd ${REMOTE_PATH}/CCpackage && ./peer1CCInstall.sh"
run_ssh "peer2" "cd ${REMOTE_PATH}/CCpackage && ./peer2CCInstall.sh"

log_success "Chaincode 已安裝"
sleep 3

# -----------------------------------------------------------------------------
# Step 6: Approve & Commit Chaincode
# -----------------------------------------------------------------------------

log_step "Step 6: Approve & Commit Chaincode"

run_ssh "peer0" "cd ${REMOTE_PATH}/CCpackage && ./approveCC.sh"
sleep 3

run_ssh "peer0" "cd ${REMOTE_PATH}/CCpackage && ./commitCC.sh"
sleep 5

log_success "Chaincode 已批准並提交"

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------

echo ""
echo "=========================================="
log_success "部署完成!"
echo "=========================================="
echo ""
echo "下一步:"
echo "  1. 執行 initLedger 初始化帳本"
echo "  2. 開始實驗"
echo ""

# 執行 initLedger 初始化帳本

# run_ssh "peer0" "cd ~/fabricWithEbpfSequencerExperiment/test-network/experiments/initLedger && export GO111MODULE=on && go mod tidy && go run ."
