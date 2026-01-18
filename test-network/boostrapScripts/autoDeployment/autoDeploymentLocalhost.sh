#!/usr/bin/env bash

###############################################################################
# Local Auto-Deployment Script for Hyperledger Fabric Setup
#
# Usage:
#   ./auto_deploy_local.sh <root_path>
#
# Example:
#   ./auto_deploy_local.sh /path/to/mainPlan/fabricWithEbpfSequencerExperiment
###############################################################################

if [ -z "$1" ]; then
  echo "Usage: $0 <root_path>"
  exit 1
fi

ROOT_DIR=$1

export PATH=$PATH:~/Documents/Research_Test/original_nopaxos_fabric/fabricWithEbpfSequencer/scripts/bin
echo "Using root path: $ROOT_DIR"

echo ""
echo "====================="
echo " Step 1: Docker Cleanup "
echo "====================="

docker rm -f $(docker ps -a -q) || true
docker volume rm $(docker volume ls -q) || true

echo ""
echo "=================="
echo " Step 2: Setup "
echo "=================="

# Helper to run a script
run_local_script() {
  local relative_script_path=$1
  echo -e "\n>>> Running $relative_script_path"
  bash "$ROOT_DIR/$relative_script_path"
}

# Helper to run a script with PATH exported
run_local_script_with_env() {
  local relative_script_path=$1
  echo -e "\n>>> Running $relative_script_path with PATH update"
  PATH="$ROOT_DIR/bin:$PATH" bash "$ROOT_DIR/$relative_script_path"
}

# ---- Bring Up Node ----
run_local_script "test-network/boostrapScripts/bringUpNode/orderer.sh"
run_local_script "test-network/boostrapScripts/bringUpNode/orderer1.sh"
run_local_script "test-network/boostrapScripts/bringUpNode/orderer2.sh"
run_local_script "test-network/boostrapScripts/bringUpNode/orderer3.sh"
#run_local_script "test-network/boostrapScripts/bringUpNode/orderer4.sh"

run_local_script "test-network/boostrapScripts/bringUpNode/peer.sh"
run_local_script "test-network/boostrapScripts/bringUpNode/peer1.sh"
run_local_script "test-network/boostrapScripts/bringUpNode/peer2.sh"

sleep 5

# ---- Join Channel ----
run_local_script_with_env "test-network/boostrapScripts/joinChannel/orderer.sh"
run_local_script_with_env "test-network/boostrapScripts/joinChannel/orderer1.sh"
run_local_script_with_env "test-network/boostrapScripts/joinChannel/orderer2.sh"
run_local_script_with_env "test-network/boostrapScripts/joinChannel/orderer3.sh"
#run_local_script_with_env "test-network/boostrapScripts/joinChannel/orderer4.sh"

sleep 5

run_local_script_with_env "test-network/boostrapScripts/joinChannel/peer.sh"
run_local_script_with_env "test-network/boostrapScripts/joinChannel/peer1.sh"
run_local_script_with_env "test-network/boostrapScripts/joinChannel/peer2.sh"

sleep 5

# ---- Install Chaincode ----
cd "$ROOT_DIR/test-network/boostrapScripts/CCpackage"
./peerCCInstall.sh
./peer1CCInstall.sh
./peer2CCInstall.sh

sleep 10

# ---- Approve and Commit ----
run_local_script_with_env "test-network/boostrapScripts/CCpackage/approveCCLocalhost.sh"

sleep 10

run_local_script_with_env "test-network/boostrapScripts/CCpackage/commitCCLocalhost.sh"

sleep 10

echo ""
echo "===================================================="
echo " Deployment steps completed successfully!"
echo "===================================================="

# ---- Chaincode Initialization ----
echo ""
echo ">>> Initializing chaincode..."
(cd "$ROOT_DIR/test-network/experiments/initLedger" && export GO111MODULE=on && go mod tidy && go run .)

echo ""
echo "===================================================="
echo " Chaincode initialization steps completed successfully!"
echo "===================================================="
