#!/usr/bin/env bash

###############################################################################
# Cleanup Script - 清理所有 GCP VM 上的 Docker containers 和 volumes
###############################################################################

set -e

SSH_USER="lz"

# VM IP 地址配置
declare -A VMS
VMS["orderer0"]="35.229.147.60"
VMS["orderer1"]="35.229.171.253"
VMS["orderer2"]="34.80.136.190"
VMS["orderer3"]="35.234.56.10"
VMS["peer0"]="35.201.241.96"
VMS["peer1"]="34.81.21.239"
VMS["peer2"]="35.201.182.70"


# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=========================================="
echo " Docker Cleanup - All GCP VMs"
echo "=========================================="

for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
    ip="${VMS[$vm_name]}"
    log_info "清理 $vm_name ($ip)..."

    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$ip" \
        "docker rm -f \$(docker ps -aq) 2>/dev/null || true; \
         docker volume rm \$(docker volume ls -q) 2>/dev/null || true; \
         docker network prune -f 2>/dev/null || true" || log_error "Failed: $vm_name"
done

log_success "所有 VM 清理完成"
