package main

import (
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/hyperledger/fabric-gateway/pkg/client"
)

var wg1 sync.WaitGroup

// measureTPSTransferAssetAsync submits transactions using a ticker-based approach:
// every 100ms, a batch of (workload/10) transactions is sent to achieve uniform load.
func measureTPSTransferAssetAsync(contract *client.Contract, numTransactions int, workload int) {
	errCount := 0
	txCount := 0
	ltCount := 0
	totalLt := 0
	var mu sync.Mutex
	var mu1 sync.Mutex

	batchSize := workload / 10 // e.g. 500 RPS → 50 tx per 100ms batch
	if batchSize < 1 {
		batchSize = 1
	}

	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	timeout := time.After(90 * time.Second)

	submitted := 0
	for submitted < numTransactions {
		select {
		case <-timeout:
			goto wait
		case <-ticker.C:
			count := batchSize
			if submitted+count > numTransactions {
				count = numTransactions - submitted
			}
			for j := 0; j < count; j++ {
				wg1.Add(1)
				assetId := "asset" + strconv.FormatInt(time.Now().UnixNano(), 10)
				idx := submitted + j
				go func(id string, i int) {
					defer wg1.Done()
					if i%75 == 0 {
						latency, err := createAssetWithLatency(contract, id)
						if err != nil {
							mu.Lock()
							errCount++
							mu.Unlock()
						} else {
							mu1.Lock()
							txCount++
							ltCount++
							totalLt += int(latency)
							mu1.Unlock()
						}
					} else {
						err := createAsset(contract, id)
						if err != nil {
							mu.Lock()
							errCount++
							mu.Unlock()
						} else {
							mu1.Lock()
							txCount++
							mu1.Unlock()
						}
					}
				}(assetId, idx)
			}
			submitted += count
		}
	}

wait:
	wg1.Wait()
	if ltCount > 0 {
		fmt.Printf("=======Transaction Average Latency: %d =======\n", totalLt/ltCount)
	}
	fmt.Printf("=======Submitted: %d  Errors: %d =======\n", txCount, errCount)
}
