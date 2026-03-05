#!/usr/bin/env bash

# 連上所有 vm

# make docker

# 配置
SSH_USER="lz"

# VM IP 地址配置
declare -A VMS
VMS["orderer0"]="34.81.30.7"
VMS["orderer1"]="34.81.10.171"
VMS["orderer2"]="35.201.198.28"
VMS["orderer3"]="34.81.170.165"
VMS["peer0"]="35.194.168.248"
VMS["peer1"]="35.221.209.220"
VMS["peer2"]="104.199.189.201"

# SSH 執行命令
run_ssh() {
    local vm_name=$1
    local cmd=$2
    local ip="${VMS[$vm_name]}"

    echo "[$vm_name @ $ip] $cmd"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$ip" "export PATH=\$PATH:~/Fabric_batch_unit_order/scripts/bin && $cmd"
}

# 在所有 VM 上執行命令
run_all() {
    local cmd=$1
    for vm_name in $(echo "${!VMS[@]}" | tr ' ' '\n' | sort); do
        # 在遠程 VM 上設置 PATH 並執行命令
        run_ssh "$vm_name" "$cmd" || true
    done
}

run_all "cd ~/Fabric_batch_unit_order && make docker"