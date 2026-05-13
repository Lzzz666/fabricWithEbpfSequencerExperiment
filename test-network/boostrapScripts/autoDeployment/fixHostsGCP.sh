#!/usr/bin/env bash

###############################################################################
# 修復 GCP VM 的 /etc/hosts 文件
#
# 問題：當使用 network_mode: host 時，Docker 的 extra_hosts 不生效
# 解決方案：在每個 VM 的 /etc/hosts 中添加 orderer 和 peer 主機名映射
#
# 使用方法:
#   ./fixHostsGCP.sh
###############################################################################

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SSH_USER="lz"

# VM IP 地址配置
declare -A VMS
VMS["orderer0"]="107.167.190.170"
VMS["orderer1"]="34.80.16.63"
VMS["orderer2"]="34.80.230.24"
VMS["orderer3"]="34.80.174.19"
VMS["peer0"]="34.80.247.165"
VMS["peer1"]="35.221.173.215"
VMS["peer2"]="34.80.216.59"

# Orderer 內部 IP 地址（GCP 內部網絡）
declare -A ORDERER_IPS
ORDERER_IPS["orderer.example.com"]="10.140.0.19"
ORDERER_IPS["orderer1.example.com"]="10.140.0.20"
ORDERER_IPS["orderer2.example.com"]="10.140.0.21"
ORDERER_IPS["orderer3.example.com"]="10.140.0.22"

# Peer 內部 IP 地址
declare -A PEER_IPS
PEER_IPS["peer0.org1.example.com"]="10.140.0.16"
PEER_IPS["peer1.org1.example.com"]="10.140.0.17"
PEER_IPS["peer2.org1.example.com"]="10.140.0.18"

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


# 修復單個 VM 的 /etc/hosts
fix_vm_hosts() {
    local vm_name=$1
    local ip="${VMS[$vm_name]}"
    
    log_info "修復 $vm_name ($ip) 的 /etc/hosts..."
    
    # 備份現有的 /etc/hosts
    run_ssh "$vm_name" "sudo cp /etc/hosts /etc/hosts.backup.\$(date +%Y%m%d_%H%M%S)" || true
    
    # 移除舊的 Fabric 條目（如果存在）
    run_ssh "$vm_name" "sudo sed -i.bak '/# Hyperledger Fabric orderers and peers/,/^$/d' /etc/hosts" || true
    
    # 添加標記和所有條目
    run_ssh "$vm_name" "echo '' | sudo tee -a /etc/hosts > /dev/null"
    run_ssh "$vm_name" "echo '# Hyperledger Fabric orderers and peers' | sudo tee -a /etc/hosts > /dev/null"
    
    for hostname in "${!ORDERER_IPS[@]}"; do
        run_ssh "$vm_name" "echo '${ORDERER_IPS[$hostname]} $hostname' | sudo tee -a /etc/hosts > /dev/null"
    done
    
    for hostname in "${!PEER_IPS[@]}"; do
        run_ssh "$vm_name" "echo '${PEER_IPS[$hostname]} $hostname' | sudo tee -a /etc/hosts > /dev/null"
    done
    
    # 驗證
    log_info "驗證 $vm_name 的 /etc/hosts..."
    run_ssh "$vm_name" "cat /etc/hosts | grep -E '(orderer|peer).*example.com' || echo '未找到條目'"
    
    log_success "$vm_name 的 /etc/hosts 已更新"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

log_step "修復 GCP VM 的 /etc/hosts 文件"

echo "將在以下 VM 上更新 /etc/hosts:"
for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
    echo "  $vm_name: ${VMS[$vm_name]}"
done
echo ""
echo "將添加以下主機名映射:"
for hostname in "${!ORDERER_IPS[@]}"; do
    echo "  ${ORDERER_IPS[$hostname]} -> $hostname"
done
for hostname in "${!PEER_IPS[@]}"; do
    echo "  ${PEER_IPS[$hostname]} -> $hostname"
done
echo ""

read -p "確定要繼續嗎? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "已取消"
    exit 0
fi

# 修復所有 VM
for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
    fix_vm_hosts "$vm_name" || log_error "修復 $vm_name 失敗"
done

log_step "完成"

echo ""
log_success "所有 VM 的 /etc/hosts 已更新！"
echo ""
echo "下一步："
echo "  1. 重新啟動 peer 容器（如果正在運行）"
echo "  2. 驗證 peer 可以解析 orderer 主機名"
echo "  3. 重新執行 initLedger"
echo ""
