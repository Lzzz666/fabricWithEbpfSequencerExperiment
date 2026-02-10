#!/usr/bin/env bash

###############################################################################
# Auto Git Pull Script for GCP VMs
#
# 連上每一台 VM 並執行 git pull 更新專案
#
# 使用方法:
#   ./autopullrepo.sh              # 使用預設分支 (feat/raft)
#   ./autopullrepo.sh main         # 指定分支
#   ./autopullrepo.sh -f           # 強制覆蓋本地變更 (git fetch + reset)
###############################################################################

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# SSH 使用者名稱
SSH_USER="lz"

# 預設分支
DEFAULT_BRANCH="feat/raft"

# 專案在 VM 上的路徑
REMOTE_REPO_PATH="mainPlan/fabricWithEbpfSequencerExperiment"

# Git 倉庫 URL
GIT_REPO_URL="https://github.com/Lzzz666/fabricWithEbpfSequencerExperiment.git"

# VM IP 地址配置
declare -A VMS
VMS["orderer0"]="104.199.222.55"
VMS["orderer1"]="35.236.133.204"
VMS["orderer2"]="34.80.197.84"
VMS["orderer3"]="35.229.223.218"
VMS["peer0"]="34.80.206.206"
VMS["peer1"]="35.229.144.77"
VMS["peer2"]="104.155.194.223"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# SSH 執行命令
run_ssh() {
    local vm_name=$1
    local ip=$2
    local cmd=$3

    echo ""
    log_info "[$vm_name @ $ip] 執行: $cmd"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$ip" "$cmd"
}

# 在 VM 上執行 git pull
pull_on_vm() {
    local vm_name=$1
    local ip=$2
    local branch=$3
    local force_mode=$4

    echo ""
    echo "=========================================="
    log_info "處理 $vm_name ($ip)"
    echo "=========================================="

    if [ "$force_mode" = true ]; then
        # 強制模式：fetch + reset
        run_ssh "$vm_name" "$ip" "cd $REMOTE_REPO_PATH && \
            git fetch origin && \
            git checkout $branch && \
            git reset --hard origin/$branch"
    else
        # 一般模式：pull
        run_ssh "$vm_name" "$ip" "cd $REMOTE_REPO_PATH && \
            git checkout $branch && \
            git pull origin $branch"
    fi

    if [ $? -eq 0 ]; then
        log_success "$vm_name 更新完成"
    else
        log_error "$vm_name 更新失敗"
        return 1
    fi
}

# 顯示使用說明
show_usage() {
    echo "用法: $0 [選項] [分支名稱]"
    echo ""
    echo "選項:"
    echo "  -f, --force    強制覆蓋本地變更 (git fetch + reset --hard)"
    echo "  -h, --help     顯示此說明"
    echo "  -l, --list     列出所有 VM"
    echo "  -v, --vm       只更新指定的 VM (例如: -v peer0)"
    echo ""
    echo "範例:"
    echo "  $0                  # 使用預設分支 ($DEFAULT_BRANCH)"
    echo "  $0 main             # 切換到 main 分支並 pull"
    echo "  $0 -f               # 強制覆蓋並更新"
    echo "  $0 -v peer0         # 只更新 peer0"
    echo "  $0 -v peer0 main    # 只更新 peer0 到 main 分支"
}

# 列出所有 VM
list_vms() {
    echo "已配置的 VM 列表:"
    echo ""
    for vm_name in "${!VMS[@]}"; do
        echo "  $vm_name: ${VMS[$vm_name]}"
    done | sort
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

FORCE_MODE=false
BRANCH="$DEFAULT_BRANCH"
SPECIFIC_VM=""

# 解析參數
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -l|--list)
            list_vms
            exit 0
            ;;
        -v|--vm)
            SPECIFIC_VM="$2"
            shift 2
            ;;
        -*)
            log_error "未知選項: $1"
            show_usage
            exit 1
            ;;
        *)
            BRANCH="$1"
            shift
            ;;
    esac
done

echo "=========================================="
echo " Auto Git Pull Script"
echo "=========================================="
echo "分支: $BRANCH"
echo "強制模式: $FORCE_MODE"
if [ -n "$SPECIFIC_VM" ]; then
    echo "目標 VM: $SPECIFIC_VM"
fi
echo ""

# 確認執行
read -p "確定要執行更新嗎? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warning "已取消"
    exit 0
fi

# 記錄成功/失敗的 VM
declare -a SUCCESS_VMS
declare -a FAILED_VMS

# 執行更新
if [ -n "$SPECIFIC_VM" ]; then
    # 只更新指定的 VM
    if [ -z "${VMS[$SPECIFIC_VM]}" ]; then
        log_error "找不到 VM: $SPECIFIC_VM"
        list_vms
        exit 1
    fi

    if pull_on_vm "$SPECIFIC_VM" "${VMS[$SPECIFIC_VM]}" "$BRANCH" "$FORCE_MODE"; then
        SUCCESS_VMS+=("$SPECIFIC_VM")
    else
        FAILED_VMS+=("$SPECIFIC_VM")
    fi
else
    # 更新所有 VM
    for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
        ip="${VMS[$vm_name]}"
        if pull_on_vm "$vm_name" "$ip" "$BRANCH" "$FORCE_MODE"; then
            SUCCESS_VMS+=("$vm_name")
        else
            FAILED_VMS+=("$vm_name")
        fi
    done
fi

# 顯示結果摘要
echo ""
echo "=========================================="
echo " 執行結果"
echo "=========================================="

if [ ${#SUCCESS_VMS[@]} -gt 0 ]; then
    log_success "成功更新: ${SUCCESS_VMS[*]}"
fi

if [ ${#FAILED_VMS[@]} -gt 0 ]; then
    log_error "更新失敗: ${FAILED_VMS[*]}"
    exit 1
fi

echo ""
log_success "所有 VM 更新完成!"
