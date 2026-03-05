# Raft 部署問題排查指南

## 問題描述

在 GCP 上部署 Raft 版本後，執行 `initLedger` 時出現以下錯誤：

```
panic: failed to submit transaction: rpc error: code = Unavailable desc = no orderers could successfully process transaction
```

## 問題根源

當使用 `network_mode: host` 時，Docker 容器的 `extra_hosts` 配置**不會生效**。這意味著：

1. Peer 容器無法解析 `orderer.example.com`、`orderer1.example.com` 等主機名
2. Gateway 客戶端通過 discovery 服務獲取 orderer 端點時，得到的是主機名（如 `orderer.example.com:7050`）
3. 由於無法解析主機名，peer 無法連接到任何 orderer
4. 導致 "no orderers could successfully process transaction" 錯誤

## 解決方案

### 方法 1：修復 /etc/hosts（推薦）

在每個 GCP VM 的 `/etc/hosts` 文件中添加 orderer 和 peer 的主機名映射。

**自動修復腳本：**

```bash
cd ~/fabricWithEbpfSequencerExperiment/test-network/boostrapScripts/autoDeployment
./fixHostsGCP.sh
```

這個腳本會：
1. 備份現有的 `/etc/hosts` 文件
2. 移除舊的 Fabric 條目
3. 添加所有 orderer 和 peer 的主機名映射
4. 驗證更新是否成功

**手動修復：**

在每個 VM 上執行以下命令：

```bash
sudo bash -c 'cat >> /etc/hosts << EOF

# Hyperledger Fabric orderers and peers
34.81.30.7 orderer.example.com
34.81.10.171 orderer1.example.com
34.81.170.165 orderer2.example.com
34.81.170.165 orderer3.example.com
35.221.209.220 peer0.org1.example.com
35.221.209.220 peer1.org1.example.com
104.199.189.201 peer2.org1.example.com
EOF'
```

### 方法 2：修改 configtx.yaml（不推薦）

將 `configtx.yaml` 中的 orderer 主機名改為 IP 地址。但這會影響所有使用該配置的環境。

## 驗證步驟

### 1. 檢查 /etc/hosts

在 peer VM 上執行：

```bash
cat /etc/hosts | grep -E "(orderer|peer).*example.com"
```

應該看到所有 orderer 和 peer 的映射。

### 2. 測試主機名解析

在 peer VM 上執行：

```bash
ping -c 1 orderer.example.com
ping -c 1 orderer1.example.com
ping -c 1 orderer2.example.com
ping -c 1 orderer3.example.com
```

應該能夠 ping 通所有 orderer。

### 3. 檢查 peer 日誌

```bash
docker logs peer0.org1.example.com | grep -i orderer
```

查看是否有連接 orderer 的錯誤訊息。

### 4. 檢查 orderer 狀態

```bash
# 在每個 orderer VM 上
docker ps | grep orderer
docker logs orderer.example.com | tail -50
```

確認所有 orderer 都在運行且沒有錯誤。

### 5. 重新執行 initLedger

```bash
cd ~/fabricWithEbpfSequencerExperiment/test-network/experiments/initLedger
go run .
```

## 其他可能的原因

如果修復 `/etc/hosts` 後問題仍然存在，請檢查：

### 1. 防火牆規則

確保 GCP 防火牆規則允許以下端口：
- Orderer 端口：7050, 8050, 9050, 10050
- Peer 端口：12051, 13051, 14051

```bash
# 檢查防火牆規則
gcloud compute firewall-rules list | grep fabric
```

### 2. Orderer 是否正確啟動

```bash
# 在每個 orderer VM 上
docker logs orderer.example.com | grep -i "Starting Raft node"
docker logs orderer.example.com | grep -i error
```

### 3. Channel 配置是否正確

確認 channel 配置中包含正確的 orderer 端點：

```bash
# 在 peer VM 上
peer channel getinfo -c mychannel
```

### 4. TLS 證書問題

檢查 TLS 證書是否正確：

```bash
# 在 peer VM 上
ls -la ~/fabricWithEbpfSequencerExperiment/test-network/organizations/ordererOrganizations/example.com/orderers/*/tls/
```

## 預防措施

在部署腳本中添加 `/etc/hosts` 修復步驟：

```bash
# 在 autoDeploymentGCP-Raft.sh 的 Step 1 之前添加
log_step "Step 0: Fix /etc/hosts"

for vm_name in peer0 peer1 peer2 orderer0 orderer1 orderer2 orderer3; do
    run_ssh "$vm_name" "sudo bash -c 'echo \"\" >> /etc/hosts && echo \"# Hyperledger Fabric\" >> /etc/hosts && echo \"34.81.30.7 orderer.example.com\" >> /etc/hosts && echo \"34.81.10.171 orderer1.example.com\" >> /etc/hosts && echo \"34.81.170.165 orderer2.example.com\" >> /etc/hosts && echo \"34.81.170.165 orderer3.example.com\" >> /etc/hosts && echo \"35.221.209.220 peer0.org1.example.com\" >> /etc/hosts && echo \"35.221.209.220 peer1.org1.example.com\" >> /etc/hosts && echo \"104.199.189.201 peer2.org1.example.com\" >> /etc/hosts'"
done
```

## 參考資料

- [Docker network_mode: host 文檔](https://docs.docker.com/network/host/)
- [Hyperledger Fabric Gateway 文檔](https://hyperledger-fabric.readthedocs.io/en/latest/gateway.html)
- [Raft 共識配置](https://hyperledger-fabric.readthedocs.io/en/latest/raft_configuration.html)
