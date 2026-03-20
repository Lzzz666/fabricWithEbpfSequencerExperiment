package main

import (
	"fmt"
	"os"
	"path"
	"strconv"
)

var peerEndpoint = "10.140.0.16:12051"
var gatewayPeer = "peer0.org1.example.com"

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run . <RPS>")
		os.Exit(1)
	}

	rps, err := strconv.Atoi(os.Args[1])
	if err != nil || rps <= 0 {
		fmt.Println("Invalid RPS value")
		os.Exit(1)
	}

	numTx := rps * 20

	p0 := newPeerClient(peerEndpoint, gatewayPeer)

	measureLatency(p0.Contract, p0.Network, numTx, rps, fmt.Sprintf("latency_peer0_%d.csv", rps))
	fmt.Println("===== Latency Experiment Done =====")
}

func readFirstFile(dirPath string) ([]byte, error) {
	dir, err := os.Open(dirPath)
	if err != nil {
		return nil, err
	}
	fileNames, err := dir.Readdirnames(1)
	if err != nil {
		return nil, err
	}
	return os.ReadFile(path.Join(dirPath, fileNames[0]))
}
