/*
Copyright 2021 IBM All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path"
	"strconv"
	"sync"
	"time"

	"github.com/hyperledger/fabric-gateway/pkg/client"
)

var wgg sync.WaitGroup

var peerEndpoints = [3]string{"10.140.0.7:12051", "10.140.0.6:13051", "10.140.0.8:14051"}
var gatewayPeers = [3]string{"peer0.org1.example.com", "peer1.org1.example.com", "peer2.org1.example.com"}

func main() {

	param1 := os.Args[1] // First argument (should be an integer)
	rps, _ := strconv.Atoi(param1)
	tpsLoading := rps / 2 * 60 * 4

	p0 := ContractForEachPeer(peerEndpoints[0], gatewayPeers[0])
	p1 := ContractForEachPeer(peerEndpoints[1], gatewayPeers[1])
	//p2 := ContractForEachPeer(peerEndpoints[2], gatewayPeers[2])

	// Add the number of goroutines to WaitGroup
	wgg.Add(2)

	// Launch goroutines for TPS experiment
	go func() {
		defer wgg.Done() // Mark this goroutine as done when finished
		measureTPSTransferAssetAsync(p0, tpsLoading, rps/2)
	}()

	go func() {
		defer wgg.Done() // Mark this goroutine as done when finished
		measureTPSTransferAssetAsync(p1, tpsLoading, rps/2)
	}()

	/* 	go func() {
		defer wgg.Done() // Mark this goroutine as done when finished
		measureTPSTransferAssetAsync(p2, tpsLoading, 1000)
	}() */

	wgg.Wait() // Wait for all async transactions to complete
	fmt.Printf("=====Experiment Done=====")
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

// Submit a transaction synchronously, blocking until it has been committed to the ledger.
func createAsset(contract *client.Contract, assetId string) error {
	_, _, err := contract.SubmitAsync("CreateAsset", client.WithArguments(assetId, "yellow", "5", "Tom", "1300"))
	if err != nil {
		return err
	}

	return nil
}

// Submit a transaction synchronously, blocking until it has been committed to the ledger.
func createAssetWithLatency(contract *client.Contract, assetId string) (int64, error) {
	startTime := time.Now()

	// Channel to receive the error from SubmitTransaction
	doneCh := make(chan error, 1)

	// Submit the transaction in a separate goroutine
	go func() {
		_, err := contract.SubmitTransaction("CreateAsset", assetId, "yellow", "5", "Tom", "1300")
		doneCh <- err
	}()

	// Wait for either the transaction to complete or the 1s timeout
	select {
	case err := <-doneCh:
		if err != nil {
			return 0, err
		}
	case <-time.After(1 * time.Second):
		return 0, fmt.Errorf("transaction timed out after 1 second")
	}

	duration := time.Since(startTime).Microseconds()
	return duration, nil
}

// Evaluate a transaction by assetID to query ledger state.
func readAssetByID(contract *client.Contract, assetId string) {
	fmt.Printf("\n--> Evaluate Transaction: ReadAsset, function returns asset attributes\n")

	evaluateResult, err := contract.EvaluateTransaction("ReadAsset", assetId)
	if err != nil {
		(fmt.Errorf("failed to evaluate transaction: %w", err))
	}
	result := formatJSON(evaluateResult)

	fmt.Printf("*** Result:%s\n", result)
}

// Submit transaction asynchronously, blocking until the transaction has been sent to the orderer, and allowing
// this thread to process the chaincode response (e.g. update a UI) without waiting for the commit notification
func transferAssetAsync(contract *client.Contract, assetId string) error {
	fmt.Printf("\n--> Async Submit Transaction: TransferAsset, updates existing asset owner")

	submitResult, _, err := contract.SubmitAsync("TransferAsset", client.WithArguments(assetId, "SOLO"))
	if err != nil {
		(fmt.Errorf("failed to submit transaction asynchronously: %w", err))
		return err
	}

	fmt.Printf("\n*** Successfully submitted transaction to transfer ownership from %s to Mark. \n", string(submitResult))
	fmt.Println("*** Waiting for transaction commit.")

	return nil
}

// Format JSON data
func formatJSON(data []byte) string {
	var prettyJSON bytes.Buffer
	if err := json.Indent(&prettyJSON, data, "", "  "); err != nil {
		panic(fmt.Errorf("failed to parse JSON: %w", err))
	}
	return prettyJSON.String()
}
