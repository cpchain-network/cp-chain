package rollup

import (
	"errors"

	"github.com/cpchain-network/cp-chain/cp-node/bindings"
	"github.com/cpchain-network/cp-chain/cp-service/eth"
)

var ErrNilProof = errors.New("output root proof is nil")

// ComputeL2OutputRoot computes the core output root by hashing an output root proof.
func ComputeL2OutputRoot(proofElements *bindings.TypesOutputRootProof) (eth.Bytes32, error) {
	if proofElements == nil {
		return eth.Bytes32{}, ErrNilProof
	}

	if eth.Bytes32(proofElements.Version) != eth.OutputVersionV0 {
		return eth.Bytes32{}, errors.New("unsupported output root version")
	}
	l2Output := eth.OutputV0{
		StateRoot:                eth.Bytes32(proofElements.StateRoot),
		MessagePasserStorageRoot: proofElements.MessagePasserStorageRoot,
		BlockHash:                proofElements.LatestBlockhash,
	}
	return eth.OutputRoot(&l2Output), nil
}

func ComputeL2OutputRootV0(block eth.BlockInfo, storageRoot [32]byte) (eth.Bytes32, error) {
	stateRoot := block.Root()
	l2Output := eth.OutputV0{
		StateRoot:                eth.Bytes32(stateRoot),
		MessagePasserStorageRoot: storageRoot,
		BlockHash:                block.Hash(),
	}
	return eth.OutputRoot(&l2Output), nil
}
