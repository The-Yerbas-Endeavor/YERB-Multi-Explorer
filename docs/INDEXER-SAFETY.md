# Indexer safety

The block indexer processes blocks in strict height order and validates that each block connects to the currently indexed tip.

When the stored chain no longer matches Yerbas Core, the indexer finds the last common ancestor, removes orphaned blocks, transactions, asset events, and orphan-issued assets, resets synchronization state, and replays the canonical chain.

## Operations

- Run exactly one `yerb-explorer-indexer` process.
- Do not attach multiple workers to the `yerbas-blocks` queue.
- Reorganizations publish an `explorer:event` message with type `reorg`.
- Completed and failed queue entries are removed so canonical heights can be queued again.
- Back up MongoDB before a manual full reindex.

Existing assets affected by an orphaned reissue are corrected when the canonical replacement blocks are replayed.
