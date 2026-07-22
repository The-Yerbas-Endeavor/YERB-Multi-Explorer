# Address and UTXO indexing

The explorer maintains a canonical native YERB UTXO set while blocks are processed in strict height order.

## Collections

- `utxos`: indexed outputs, ownership, value, creation data, and optional spend data
- `addresstransactions`: one summarized relationship per address and transaction
- `addresses`: derived balance, lifetime received and sent totals, transaction count, and first/last activity heights

## Processing

For every transaction the worker:

1. Resolves non-coinbase inputs against the indexed UTXO set.
2. Marks those outputs spent and records the spending transaction, input, height, block, and time.
3. Inserts address-bearing outputs into the UTXO set.
4. Updates each touched address once with received, sent, net, input-count, and output-count values.
5. Stores transaction input totals, output totals, and fees.

Outputs without a recognized address remain available in raw transaction data but do not affect an address balance.

## Reorganizations

A rollback now:

- deletes UTXOs created on the orphaned branch
- restores UTXOs spent on the orphaned branch
- deletes orphaned address-transaction records
- rebuilds every affected address from canonical UTXO and history records

## API

- `GET /api/v1/addresses/:address`
- `GET /api/v1/addresses/:address/transactions?page=1&limit=25`
- `GET /api/v1/addresses/:address/utxos?includeSpent=false`

## Required validation

Test coinbase transactions, standard P2PKH and P2SH outputs, same-block spends, outputs without addresses, double-spend rejection, pagination, and a reorganization that removes both creating and spending transactions.
