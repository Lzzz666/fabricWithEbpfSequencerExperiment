package main

import (
	"context"
	"encoding/csv"
	"fmt"
	"os"
	"sort"
	"strconv"
	"sync"
	"time"

	"github.com/hyperledger/fabric-gateway/pkg/client"
)

// BlockRecord records the local time when a block commit event was received.
type BlockRecord struct {
	BlockNum uint64
	TCommit  int64 // Unix nanoseconds (local clock, when event arrived)
	TxCount  int
}

// TxSubmit records per-transaction submission timestamps.
type TxSubmit struct {
	TxID      string
	TGenerate int64 // Unix nanoseconds
	TOrderer  int64 // Unix nanoseconds (when SubmitAsync returned)
}

// LatencyRecord is the final per-transaction result after matching.
type LatencyRecord struct {
	TxID      string
	TGenerate int64
	TOrderer  int64
	TCommit   int64
	BlockNum  uint64
	EndorseMs float64 // tOrderer - tGenerate
	CommitMs  float64 // tCommit  - tGenerate
}

// listenBlockEvents subscribes to raw block events and forwards them to blockCh.
// Works with hash-only blocks: we only use block.Header.Number and len(block.Data.Data).
func listenBlockEvents(ctx context.Context, network *client.Network, blockCh chan<- BlockRecord) {
	events, err := network.BlockEvents(ctx)
	if err != nil {
		fmt.Printf("[BlockEvents] subscribe failed: %v\n", err)
		return
	}
	for {
		select {
		case <-ctx.Done():
			return
		case block, ok := <-events:
			if !ok {
				return
			}
			tCommit := time.Now().UnixNano()
			blockCh <- BlockRecord{
				BlockNum: block.Header.Number,
				TCommit:  tCommit,
				TxCount:  len(block.Data.Data),
			}
		}
	}
}

// measureLatency submits transactions and measures latency using block events.
//
// In hash-only mode, commit.Status() cannot track individual transactions
// because hash-only blocks do not contain full transaction data (txID).
// Instead, we subscribe to block events and use time-based matching:
//
//	t_commit for tx[i] = TCommit of the first block committed AFTER tx[i].TOrderer
//
// This works because a transaction must be in a block committed after it was
// submitted to the orderer (i.e., after SubmitAsync returned).
func measureLatency(contract *client.Contract, network *client.Network, numTransactions int, workload int, outFile string) {
	// --- Phase 1: Start block event listener ---
	blockCtx, blockCancel := context.WithCancel(context.Background())
	blockCh := make(chan BlockRecord, 10000)
	go listenBlockEvents(blockCtx, network, blockCh)

	// Let the subscription settle before starting submissions.
	time.Sleep(500 * time.Millisecond)
	experimentStart := time.Now()

	// --- Phase 2: Submit transactions ---
	var submissions []TxSubmit
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
			goto waitSubmit
		default:
		}

		assetId := "asset" + strconv.FormatInt(time.Now().UnixNano(), 10)
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			tGenerate := time.Now()

			// Do NOT call commit.Status() — incompatible with hash-only blocks.
			// SubmitAsync returns after the transaction is endorsed and added
			// to the peer's batch buffer (submitNonBFT returns immediately).
			_, commit, err := contract.SubmitAsync(
				"CreateAsset",
				client.WithArguments(id, "yellow", "5", "Tom", "1300"),
			)
			tOrderer := time.Now()
			_ = commit // intentionally ignored

			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				if errCount < 3 {
					fmt.Printf("[ERROR sample %d] SubmitAsync: %v\n", errCount+1, err)
				}
				errCount++
			} else {
				submissions = append(submissions, TxSubmit{
					TxID:      id,
					TGenerate: tGenerate.UnixNano(),
					TOrderer:  tOrderer.UnixNano(),
				})
			}
		}(assetId)
	}

waitSubmit:
	wg.Wait()
	fmt.Printf("Submissions complete: %d ok, %d errors\n", len(submissions), errCount)

	// --- Phase 3: Collect block events ---
	// Wait up to 30s for enough blocks to cover all submitted transactions.
	blockRecords := collectBlocks(blockCh, experimentStart, len(submissions), 30*time.Second)
	blockCancel()

	// --- Phase 4: Match transactions to blocks (time-based) ---
	// For each transaction, t_commit = TCommit of the first block committed
	// after that transaction's TOrderer.
	records := matchByTime(submissions, blockRecords)

	writeCSV(records, outFile)
	printStats(records, errCount)
}

// collectBlocks collects block events from blockCh until expectedTxns have been
// seen or waitDur elapses, then drains the channel for 2 more seconds.
func collectBlocks(blockCh <-chan BlockRecord, since time.Time, expectedTxns int, waitDur time.Duration) []BlockRecord {
	var blocks []BlockRecord
	collected := 0
	deadline := time.After(waitDur)

	for collected < expectedTxns {
		select {
		case br := <-blockCh:
			if br.TCommit >= since.UnixNano() {
				blocks = append(blocks, br)
				collected += br.TxCount
				fmt.Printf("[Block] #%d committed, %d txns (total: %d/%d)\n",
					br.BlockNum, br.TxCount, collected, expectedTxns)
			}
		case <-deadline:
			fmt.Printf("Block collection timeout. Got %d/%d txns in %d blocks.\n",
				collected, expectedTxns, len(blocks))
			goto drain
		}
	}

drain:
	drainTimer := time.After(2 * time.Second)
	for {
		select {
		case br := <-blockCh:
			if br.TCommit >= since.UnixNano() {
				blocks = append(blocks, br)
			}
		case <-drainTimer:
			return blocks
		}
	}
}

// matchByTime assigns each transaction the commit time of the first block
// committed after that transaction's TOrderer (time-based matching).
func matchByTime(submissions []TxSubmit, blocks []BlockRecord) []*LatencyRecord {
	sort.Slice(blocks, func(i, j int) bool {
		return blocks[i].BlockNum < blocks[j].BlockNum
	})

	var records []*LatencyRecord
	unmatched := 0

	for _, sub := range submissions {
		matched := false
		for _, blk := range blocks {
			if blk.TCommit > sub.TOrderer {
				records = append(records, &LatencyRecord{
					TxID:      sub.TxID,
					TGenerate: sub.TGenerate,
					TOrderer:  sub.TOrderer,
					TCommit:   blk.TCommit,
					BlockNum:  blk.BlockNum,
					EndorseMs: float64(sub.TOrderer-sub.TGenerate) / 1e6,
					CommitMs:  float64(blk.TCommit-sub.TGenerate) / 1e6,
				})
				matched = true
				break
			}
		}
		if !matched {
			unmatched++
		}
	}

	if unmatched > 0 {
		fmt.Printf("Warning: %d transactions could not be matched to a block.\n", unmatched)
	}
	return records
}

// writeCSV writes all records to a CSV file.
func writeCSV(records []*LatencyRecord, outFile string) {
	f, err := os.Create(outFile)
	if err != nil {
		fmt.Printf("Failed to create %s: %v\n", outFile, err)
		return
	}
	defer f.Close()

	w := csv.NewWriter(f)
	defer w.Flush()

	_ = w.Write([]string{
		"txid", "t_generate_ns", "t_orderer_ns", "t_commit_ns",
		"block_num", "endorse_ms", "commit_ms",
	})
	for _, r := range records {
		_ = w.Write([]string{
			r.TxID,
			strconv.FormatInt(r.TGenerate, 10),
			strconv.FormatInt(r.TOrderer, 10),
			strconv.FormatInt(r.TCommit, 10),
			strconv.FormatUint(r.BlockNum, 10),
			strconv.FormatFloat(r.EndorseMs, 'f', 3, 64),
			strconv.FormatFloat(r.CommitMs, 'f', 3, 64),
		})
	}
	fmt.Printf("Results written to %s (%d records)\n", outFile, len(records))
}

// printStats prints P50/P95/P99 for endorse and commit latency.
func printStats(records []*LatencyRecord, errCount int) {
	n := len(records)
	if n == 0 {
		fmt.Printf("No matched records. Error count: %d\n", errCount)
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
	fmt.Printf("Matched transactions    : %d\n", n)
	fmt.Printf("Error count             : %d\n", errCount)
	fmt.Println("----- Endorse+Submit latency (ms) ------")
	fmt.Printf("  P50 : %.3f ms\n", percentile(endorseVals, 50))
	fmt.Printf("  P95 : %.3f ms\n", percentile(endorseVals, 95))
	fmt.Printf("  P99 : %.3f ms\n", percentile(endorseVals, 99))
	fmt.Printf("  Avg : %.3f ms\n", avg(endorseVals))
	fmt.Println("----- Total commit latency (ms) --------")
	fmt.Printf("  P50 : %.3f ms\n", percentile(commitVals, 50))
	fmt.Printf("  P95 : %.3f ms\n", percentile(commitVals, 95))
	fmt.Printf("  P99 : %.3f ms\n", percentile(commitVals, 99))
	fmt.Printf("  Avg : %.3f ms\n", avg(commitVals))
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
	sum := 0.0
	for _, v := range vals {
		sum += v
	}
	return sum / float64(len(vals))
}
