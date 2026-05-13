#!/usr/bin/env bash

# 連上所有 vm

# make docker

# 配置
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