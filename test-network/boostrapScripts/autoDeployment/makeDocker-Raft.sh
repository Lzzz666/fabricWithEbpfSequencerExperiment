#!/usr/bin/env bash

###############################################################################
# Build Docker Images for Raft (Baseline)
#
# 在所有 GCP VMs 上編譯 Raft 版本的 Fabric Docker images
#
# 使用方法:
#   ./makeDocker-Raft.sh
###############################################################################

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SSH_USER="lz"
DOCKER_USER="lzyu"
IMAGE_VERSION="latest"

# 專案路徑 (Raft/Baseline 版本)
FABRIC_REPO="~/fabricWithEbpfSequencer"
GIT_BRANCH="feat/baseline"

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
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$ip" "$cmd"
}

# 並行在所有 VM 上執行命令
run_all_parallel() {
    local cmd=$1
    local pids=()

    for vm_name in "${!VMS[@]}"; do
        local ip="${VMS[$vm_name]}"
        echo -e "${BLUE}[Starting $vm_name @ $ip]${NC}"
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$ip" "$cmd" &
        pids+=($!)
    done

    # 等待所有背景任務完成
    for pid in "${pids[@]}"; do
        wait $pid || log_error "Process $pid failed"
    done
}

# -----------------------------------------------------------------------------
# Step 0: Confirmation
# -----------------------------------------------------------------------------

echo "=========================================="
echo " Build Docker Images - Raft (Baseline)"
echo "=========================================="
echo ""
echo "Branch: $GIT_BRANCH"
echo "Repo: $FABRIC_REPO"
echo ""
echo "VMs:"
for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
    echo "  $vm_name: ${VMS[$vm_name]}"
done
echo ""

read -p "確定要開始編譯嗎? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "已取消"
    exit 0
fi

# -----------------------------------------------------------------------------
# Step 1: Deep Cleanup (Docker + Go cache)
# -----------------------------------------------------------------------------

log_step "Step 1: Deep Cleanup"

CLEANUP_CMD='
# Docker cleanup
docker rm -f $(docker ps -a -q) 2>/dev/null || true
docker volume rm $(docker volume ls -q) 2>/dev/null || true
docker system prune -a -f --volumes 2>/dev/null || true
docker image prune -a -f 2>/dev/null || true

# Go build cache cleanup (很重要！)
sudo rm -rf /root/.cache/go-build 2>/dev/null || true
rm -rf ~/.cache/go-build 2>/dev/null || true
sudo rm -rf /root/go/pkg/mod/cache 2>/dev/null || true
rm -rf ~/go/pkg/mod/cache 2>/dev/null || true

# APT cleanup
sudo apt-get clean 2>/dev/null || true

# 顯示剩餘空間
df -h / | tail -1
'

for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
    log_info "深度清理 $vm_name..."
    run_ssh "$vm_name" "$CLEANUP_CMD" || true
done

log_success "清理完成"

# -----------------------------------------------------------------------------
# Step 2: Git Pull & Build Docker
# -----------------------------------------------------------------------------

log_step "Step 2: Git Pull & Build Docker (並行)"

BUILD_CMD="cd ${FABRIC_REPO} && git fetch --all && git checkout ${GIT_BRANCH} && git pull && make docker ARCH=amd64"

log_info "在所有 VM 上並行編譯..."
run_all_parallel "$BUILD_CMD"

log_success "所有 VM 編譯完成"

# -----------------------------------------------------------------------------
# Step 3: Install Fabric Binaries
# -----------------------------------------------------------------------------

log_step "Step 3: Install Fabric Binaries"

INSTALL_CMD="cd ${FABRIC_REPO}/scripts && ./install-fabric.sh b"

for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
    log_info "安裝 binaries on $vm_name..."
    run_ssh "$vm_name" "$INSTALL_CMD" || true
done

log_success "Binaries 安裝完成"

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------

echo ""
echo "=========================================="
log_success "Raft Docker Images 編譯完成!"
echo "=========================================="
echo ""
echo "下一步:"
echo "  ./autoDeploymentGCP-Raft.sh"
echo ""
