package main

import (
	"encoding/csv"
	"fmt"
	"os"
	"sort"
	"strconv"
	"sync"
	"time"

	"github.com/hyperledger/fabric-gateway/pkg/client"
)

// LatencyRecord holds three timestamps for a single transaction.
//
//	t_generate  : when the client created and submitted the transaction
//	t_orderer   : when SubmitAsync returned (endorsed + sent to orderer)
//	t_commit    : when commit.Status() returned (peer committed to ledger)
type LatencyRecord struct {
	TxID        string
	TGenerate   int64 // Unix nanoseconds
	TOrderer    int64 // Unix nanoseconds
	TCommit     int64 // Unix nanoseconds
	EndorseMs   float64
	CommitMs    float64
}

// submitWithLatency submits one transaction and records the three timestamps.
func submitWithLatency(contract *client.Contract, assetId string) (*LatencyRecord, error) {
	tGenerate := time.Now()

	_, commit, err := contract.SubmitAsync(
		"CreateAsset",
		client.WithArguments(assetId, "yellow", "5", "Tom", "1300"),
	)
	tOrderer := time.Now()
	if err != nil {
		return nil, fmt.Errorf("SubmitAsync failed: %w", err)
	}

	_, err = commit.Status()
	tCommit := time.Now()
	if err != nil {
		return nil, fmt.Errorf("commit.Status failed: %w", err)
	}

	return &LatencyRecord{
		TxID:      assetId,
		TGenerate: tGenerate.UnixNano(),
		TOrderer:  tOrderer.UnixNano(),
		TCommit:   tCommit.UnixNano(),
		EndorseMs: float64(tOrderer.Sub(tGenerate).Microseconds()) / 1000.0,
		CommitMs:  float64(tCommit.Sub(tGenerate).Microseconds()) / 1000.0,
	}, nil
}

// measureLatency sends numTransactions at the given workload (tx/s) and
// writes per-transaction results to outFile (CSV).
func measureLatency(contract *client.Contract, numTransactions int, workload int, outFile string) {
	records := make([]*LatencyRecord, 0, numTransactions)
	var mu sync.Mutex
	var wg sync.WaitGroup

	errCount := 0
	interval := time.Duration(float64(time.Second) / float64(workload))

	timeout := time.After(90 * time.Second)

	for i := 0; i < numTransactions; i++ {
		time.Sleep(interval)

		select {
		case <-timeout:
			fmt.Println("Timeout reached, stopping submission.")
			goto wait
		default:
		}

		assetId := "asset" + strconv.FormatInt(time.Now().UnixNano(), 10)

		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			rec, err := submitWithLatency(contract, id)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				if errCount < 3 {
					fmt.Printf("[ERROR sample %d] %v\n", errCount+1, err)
				}
				errCount++
			} else {
				records = append(records, rec)
			}
		}(assetId)
	}

wait:
	wg.Wait()

	writeCSV(records, outFile)
	printStats(records, errCount)
}

// writeCSV writes all records to a CSV file.
func writeCSV(records []*LatencyRecord, outFile string) {
	f, err := os.Create(outFile)
	if err != nil {
		fmt.Printf("Failed to create output file %s: %v\n", outFile, err)
		return
	}
	defer f.Close()

	w := csv.NewWriter(f)
	defer w.Flush()

	// Header
	_ = w.Write([]string{
		"txid",
		"t_generate_ns",
		"t_orderer_ns",
		"t_commit_ns",
		"endorse_ms",
		"commit_ms",
	})

	for _, r := range records {
		_ = w.Write([]string{
			r.TxID,
			strconv.FormatInt(r.TGenerate, 10),
			strconv.FormatInt(r.TOrderer, 10),
			strconv.FormatInt(r.TCommit, 10),
			strconv.FormatFloat(r.EndorseMs, 'f', 3, 64),
			strconv.FormatFloat(r.CommitMs, 'f', 3, 64),
		})
	}

	fmt.Printf("Results written to %s (%d records)\n", outFile, len(records))
}

// printStats prints P50/P95/P99 for endorse latency and total commit latency.
func printStats(records []*LatencyRecord, errCount int) {
	n := len(records)
	if n == 0 {
		fmt.Printf("No successful transactions. Error count: %d\n", errCount)
		return
	}

	endorseVals := make([]float64, n)
	commitVals := make([]float64, n)
	for i, r := range records {
		endorseVals[i] = r.EndorseMs
		commitVals[i] = r.CommitMs
	}
	sort.Float64s(endorseVals)
	sort.Float64s(commitVals)

	fmt.Println("========== Latency Statistics ==========")
	fmt.Printf("Successful transactions : %d\n", n)
	fmt.Printf("Error count             : %d\n", errCount)
	fmt.Println("----- Endorse+Submit latency (ms) ------")
	fmt.Printf("  P50  : %.3f ms\n", percentile(endorseVals, 50))
	fmt.Printf("  P95  : %.3f ms\n", percentile(endorseVals, 95))
	fmt.Printf("  P99  : %.3f ms\n", percentile(endorseVals, 99))
	fmt.Printf("  Avg  : %.3f ms\n", avg(endorseVals))
	fmt.Println("----- Total commit latency (ms) --------")
	fmt.Printf("  P50  : %.3f ms\n", percentile(commitVals, 50))
	fmt.Printf("  P95  : %.3f ms\n", percentile(commitVals, 95))
	fmt.Printf("  P99  : %.3f ms\n", percentile(commitVals, 99))
	fmt.Printf("  Avg  : %.3f ms\n", avg(commitVals))
	fmt.Println("========================================")
}

func percentile(sorted []float64, p float64) float64 {
	if len(sorted) == 0 {
		return 0
	}
	idx := int(float64(len(sorted)-1) * p / 100.0)
	return sorted[idx]
}

func avg(vals []float64) float64 {
	if len(vals) == 0 {
		return 0
	}
	sum := 0.0
	for _, v := range vals {
		sum += v
	}
	return sum / float64(len(vals))
}
