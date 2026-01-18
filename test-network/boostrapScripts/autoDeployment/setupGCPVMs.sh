#!/usr/bin/env bash

###############################################################################
# GCP VM 初始化腳本
# 
# 此腳本在所有 GCP VM 上安裝必要的工具和依賴
#
# 使用方法:
#   ./setupGCPVMs.sh
###############################################################################

set -e

# 配置
GCP_PROJECT="${GCP_PROJECT:-your-project-id}"  # 請替換為您的 GCP 專案 ID
ZONE="${ZONE:-asia-east1-a}"  # 請替換為您的 zone

# VM 名稱映射
declare -A VM_MAP
VM_MAP["orderer"]="orderer"
VM_MAP["orderer1"]="orderer1"
VM_MAP["orderer2"]="orderer2"
VM_MAP["orderer3"]="orderer3"
VM_MAP["peer"]="peer"
VM_MAP["peer1"]="peer1"
VM_MAP["peer2"]="peer2"

# 初始化腳本內容（會上傳到 VM 執行）
INIT_SCRIPT=$(cat <<'EOF'
#!/usr/bin/env bash
set -e

echo "=========================================="
echo " 開始安裝必要工具"
echo "=========================================="

# 更新系統
echo "更新系統套件..."
sudo apt-get update -y
sudo apt-get upgrade -y

# 安裝基礎工具
echo "安裝基礎工具..."
sudo apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release

# 安裝 Docker
echo "安裝 Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    echo "Docker 安裝完成"
else
    echo "Docker 已安裝，跳過"
fi

# 安裝 Docker Compose
echo "安裝 Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo "Docker Compose 安裝完成"
else
    echo "Docker Compose 已安裝，跳過"
fi

# 安裝 Go (如果需要編譯 chaincode)
echo "安裝 Go..."
if ! command -v go &> /dev/null; then
    GO_VERSION="1.21.0"
    wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
    rm go${GO_VERSION}.linux-amd64.tar.gz
    
    # 添加到 PATH
    if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    fi
    
    # 立即生效
    export PATH=$PATH:/usr/local/go/bin
    echo "Go 安裝完成"
else
    echo "Go 已安裝，跳過"
fi

# 驗證安裝
echo ""
echo "=========================================="
echo " 安裝完成，驗證版本："
echo "=========================================="
echo "Docker: $(docker --version 2>/dev/null || echo '未安裝')"
echo "Docker Compose: $(docker-compose --version 2>/dev/null || echo '未安裝')"
echo "Go: $(go version 2>/dev/null || echo '未安裝')"

echo ""
echo "=========================================="
echo " 初始化完成！"
echo "=========================================="
echo "注意: 如果需要使用 Docker 而無需 sudo，請登出並重新登入"
EOF
)

# 函數：在 VM 上執行命令
run_on_vm() {
    local vm_name=$1
    local cmd=$2
    
    echo ""
    echo ">>> [VM: $vm_name] 執行: $cmd"
    gcloud compute ssh "$vm_name" \
        --zone="$ZONE" \
        --project="$GCP_PROJECT" \
        --command="$cmd" \
        --quiet
}

# 主程序
echo "=========================================="
echo " GCP VM 初始化腳本"
echo "=========================================="
echo "專案: $GCP_PROJECT"
echo "Zone: $ZONE"
echo ""

# 檢查 gcloud 是否安裝
if ! command -v gcloud &> /dev/null; then
    echo "錯誤: 未找到 gcloud 命令"
    echo "請安裝 Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# 檢查 GCP 專案是否設置
if [ "$GCP_PROJECT" = "your-project-id" ]; then
    echo "警告: 請先設置 GCP_PROJECT 環境變數或修改腳本中的預設值"
    read -p "請輸入 GCP 專案 ID: " GCP_PROJECT
fi

# 設置預設專案
echo "設置 GCP 專案為: $GCP_PROJECT"
gcloud config set project "$GCP_PROJECT"

# 為每個 VM 執行初始化
echo ""
echo "開始初始化 VM..."
for vm_role in "${!VM_MAP[@]}"; do
    vm_name="${VM_MAP[$vm_role]}"
    
    echo ""
    echo "=========================================="
    echo " 初始化 $vm_role ($vm_name)"
    echo "=========================================="
    
    # 上傳並執行初始化腳本
    echo "$INIT_SCRIPT" > /tmp/init_vm.sh
    chmod +x /tmp/init_vm.sh
    
    gcloud compute scp /tmp/init_vm.sh "$vm_name:/tmp/init_vm.sh" \
        --zone="$ZONE" \
        --project="$GCP_PROJECT" \
        --quiet
    
    run_on_vm "$vm_name" "bash /tmp/init_vm.sh && rm /tmp/init_vm.sh"
    
    echo "✓ $vm_name 初始化完成"
done

# 清理
rm -f /tmp/init_vm.sh

echo ""
echo "=========================================="
echo " 所有 VM 初始化完成！"
echo "=========================================="
echo ""
echo "下一步:"
echo "1. 上傳專案文件到 VM"
echo "2. 配置並執行 autoDeploymentGCP.sh"
echo ""

