# GCP 部署指南

## 📋 步驟概覽

當您已經創建了 7 台 GCP VM（4 台 Orderer + 3 台 Peer）後，請按照以下步驟進行部署：

---

## 步驟 1: 收集 VM 資訊

首先，需要收集所有 VM 的資訊：

```bash
# 列出所有 VM 實例
gcloud compute instances list

# 或使用以下命令查看特定資訊
gcloud compute instances list --format="table(name,zone,status,EXTERNAL_IP,INTERNAL_IP)"
```

**記錄以下資訊：**
- VM 名稱（instance name）
- Zone（例如：asia-east1-a）
- 內部 IP（INTERNAL_IP）- 用於 VM 間通訊
- 外部 IP（EXTERNAL_IP）- 可選，如果需要從外部訪問

---

## 步驟 2: 配置防火牆規則

### 2.1 創建防火牆規則

您需要開放以下端口：

**Orderer 端口：**
- 8050 (gRPC)
- 8053 (Admin TLS)
- 8443 (Operations)
- 8073 (UDP)
- 8074, 8085, 8086 (gRPC Sequencer)

**Peer 端口：**
- 7051 (Peer gRPC)
- 12051 (Peer gRPC - 根據您的配置)
- 12052 (Chaincode)
- 12444 (Operations)

```bash
# 創建 Orderer 防火牆規則
gcloud compute firewall-rules create fabric-orderer-ports \
    --allow tcp:8050,tcp:8053,tcp:8443,tcp:8074,tcp:8085,tcp:8086,udp:8073 \
    --source-ranges 0.0.0.0/0 \
    --description "Hyperledger Fabric Orderer ports"

# 創建 Peer 防火牆規則
gcloud compute firewall-rules create fabric-peer-ports \
    --allow tcp:7051,tcp:12051,tcp:12052,tcp:12444 \
    --source-ranges 0.0.0.0/0 \
    --description "Hyperledger Fabric Peer ports"
```

### 2.2 允許 VM 間通訊

```bash
# 允許所有 VM 在內部網路中互相通訊
gcloud compute firewall-rules create fabric-internal \
    --allow tcp,udp,icmp \
    --source-ranges 10.0.0.0/8 \
    --description "Internal Fabric network communication"
```

---

## 步驟 3: 在 VM 上安裝必要工具

### 3.1 使用初始化腳本

我們提供了一個初始化腳本，會自動在所有 VM 上安裝必要工具：

```bash
# 執行初始化腳本（需要提供 VM 資訊）
./setupGCPVMs.sh
```

或者手動在每台 VM 上執行：

```bash
# 連接到 VM（替換為您的 VM 名稱和 zone）
gcloud compute ssh <VM_NAME> --zone=<ZONE>

# 在 VM 上執行以下命令
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# 安裝 Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 安裝 Go (如果需要)
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# 登出並重新登入以應用 Docker 群組變更
exit
```

---

## 步驟 4: 上傳專案文件到 VM

### 4.1 使用 gcloud 上傳

```bash
# 壓縮專案目錄（在本地）
cd /Users/lz/Documents/Research_Test/original_nopaxos_fabric
tar -czf fabric-project.tar.gz fabricWithEbpfSequencerExperiment/

# 上傳到每台 VM
# 替換 <VM_NAME> 和 <ZONE>
for vm in orderer orderer1 orderer2 orderer3 peer peer1 peer2; do
    gcloud compute scp fabric-project.tar.gz $vm:~/ --zone=<ZONE>
    gcloud compute ssh $vm --zone=<ZONE} --command="tar -xzf fabric-project.tar.gz && rm fabric-project.tar.gz"
done
```

### 4.2 或使用 rsync（更高效）

```bash
# 安裝 gcloud beta（如果需要）
gcloud components install beta

# 使用 rsync 上傳
for vm in orderer orderer1 orderer2 orderer3 peer peer1 peer2; do
    gcloud compute scp --recurse \
        fabricWithEbpfSequencerExperiment $vm:~/ \
        --zone=<ZONE>
done
```

---

## 步驟 5: 配置部署腳本

### 5.1 更新 GCP 部署腳本

編輯 `autoDeploymentGCP.sh`，填入您的 VM 資訊：

```bash
# 編輯腳本
nano autoDeploymentGCP.sh

# 修改以下部分：
# - GCP_PROJECT: 您的 GCP 專案 ID
# - ZONE: VM 所在的 zone
# - VM 名稱映射到節點類型
```

---

## 步驟 6: 執行部署

```bash
# 確保腳本有執行權限
chmod +x autoDeploymentGCP.sh

# 執行部署
./autoDeploymentGCP.sh
```

---

## 步驟 7: 驗證部署

### 7.1 檢查容器狀態

```bash
# 在每台 VM 上檢查
gcloud compute ssh <VM_NAME> --zone=<ZONE> --command="docker ps"
```

### 7.2 檢查日誌

```bash
# 查看 Orderer 日誌
gcloud compute ssh orderer --zone=<ZONE> --command="docker logs orderer.example.com"

# 查看 Peer 日誌
gcloud compute ssh peer --zone=<ZONE> --command="docker logs peer0.org1.example.com"
```

---

## 🔧 故障排除

### 問題 1: SSH 連接失敗

**解決方案：**
```bash
# 檢查 VM 狀態
gcloud compute instances describe <VM_NAME> --zone=<ZONE>

# 確保有防火牆規則允許 SSH（默認已開啟）
gcloud compute firewall-rules list | grep ssh
```

### 問題 2: Docker 權限問題

**解決方案：**
```bash
# 在 VM 上執行
sudo usermod -aG docker $USER
# 重新登入
```

### 問題 3: 端口無法訪問

**解決方案：**
```bash
# 檢查防火牆規則
gcloud compute firewall-rules list

# 測試端口連接
gcloud compute ssh <VM_NAME> --zone=<ZONE> --command="sudo netstat -tlnp | grep <PORT>"
```

---

## 📝 注意事項

1. **內部 IP vs 外部 IP**
   - VM 間通訊使用內部 IP
   - 如果從外部訪問，需要外部 IP

2. **持久化存儲**
   - Docker volumes 會存儲在 VM 本地
   - 考慮使用 GCP Persistent Disk 來持久化重要數據

3. **成本優化**
   - 測試完成後記得停止或刪除 VM
   ```bash
   # 停止 VM（保留磁碟）
   gcloud compute instances stop <VM_NAME> --zone=<ZONE>
   
   # 刪除 VM（包括磁碟）
   gcloud compute instances delete <VM_NAME> --zone=<ZONE>
   ```

4. **安全建議**
   - 生產環境建議使用內部 IP
   - 配置更嚴格的防火牆規則
   - 啟用 VPC 和子網路隔離

---

## ✅ 下一步

部署完成後，您可以：
1. 執行 Chaincode 初始化
2. 運行測試實驗
3. 監控網路狀態
4. 進行效能測試

