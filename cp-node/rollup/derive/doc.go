// Package derive provides the data transformation functions that take L1 data
// and turn it into core blocks and results. Certain core data is also able to
// turned back into L1 data.
//
// The data flow is as follows:
// receipts, batches -> eth.PayloadAttributes, by parsing the L1 data and deriving core inputs
// l2.PayloadAttributes -> l2.ExecutionPayload, by running the EVM (using an Execution Engine)
// core block -> Corresponding L1 block info, by parsing the first deposited transaction
//
// The Payload Attributes derivation stage is a pure function.
// The Execution Payload derivation stage relies on the core execution engine to perform the state update.
// The inversion step is a pure function.
//
// The steps should be kept separate to enable easier testing.
package derive
