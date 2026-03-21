package main

import (
	"fmt"
	"os"
	"path"
	"strconv"
	"sync"
)

var wg sync.WaitGroup

var peerEndpoints = [2]string{"10.140.0.17:13051", "10.140.0.18:14051"}
var gatewayPeers = [2]string{"peer1.org1.example.com", "peer2.org1.example.com"}

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

	// Each peer handles half the load.
	perPeerRPS := rps / 2
	numTx := perPeerRPS * 10

	p0 := newPeerClient(peerEndpoints[0], gatewayPeers[0])
	p1 := newPeerClient(peerEndpoints[1], gatewayPeers[1])

	wg.Add(2)

	go func() {
		defer wg.Done()
		measureLatency(p0.Contract, numTx, perPeerRPS, fmt.Sprintf("latency_peer0_%d.csv", rps))
	}()

	go func() {
		defer wg.Done()
		measureLatency(p1.Contract, numTx, perPeerRPS, fmt.Sprintf("latency_peer1_%d.csv", rps))
	}()

	wg.Wait()
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
