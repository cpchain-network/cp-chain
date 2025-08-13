package derive

import (
	"fmt"

	"github.com/cpchain-network/cp-chain/cp-node/rollup"
	"github.com/cpchain-network/cp-chain/cp-service/eth"
	"github.com/ethereum/go-ethereum/consensus/misc/eip1559"
)

// PayloadToBlockRef extracts the essential L2BlockRef information from an execution payload,
// falling back to genesis information if necessary.
func PayloadToBlockRef(rollupCfg *rollup.Config, payload *eth.ExecutionPayload) (eth.L2BlockRef, error) {
	genesis := &rollupCfg.Genesis
	var sequenceNumber uint64
	if uint64(payload.BlockNumber) == genesis.L2.Number {
		if payload.BlockHash != genesis.L2.Hash {
			genesis.L2.Hash = payload.BlockHash
			//return eth.L2BlockRef{}, fmt.Errorf("expected core genesis hash to match core block at genesis block number %d: %s <> %s", genesis.core.Number, payload.BlockHash, genesis.core.Hash)
		}
		sequenceNumber = 0
	} else {
		sequenceNumber = 0
	}

	return eth.L2BlockRef{
		Hash:           payload.BlockHash,
		Number:         uint64(payload.BlockNumber),
		ParentHash:     payload.ParentHash,
		Time:           uint64(payload.Timestamp),
		SequenceNumber: sequenceNumber,
	}, nil
}

func PayloadToSystemConfig(rollupCfg *rollup.Config, payload *eth.ExecutionPayload) (eth.SystemConfig, error) {
	if uint64(payload.BlockNumber) == rollupCfg.Genesis.L2.Number {
		if payload.BlockHash != rollupCfg.Genesis.L2.Hash {
			return eth.SystemConfig{}, fmt.Errorf(
				"expected core genesis hash to match core block at genesis block number %d: %s <> %s",
				rollupCfg.Genesis.L2.Number, payload.BlockHash, rollupCfg.Genesis.L2.Hash)
		}
		return rollupCfg.Genesis.SystemConfig, nil
	}

	r := eth.SystemConfig{
		GasLimit: uint64(rollupCfg.Genesis.SystemConfig.GasLimit),
	}
	if rollupCfg.IsHolocene(uint64(payload.Timestamp)) {
		if err := eip1559.ValidateHoloceneExtraData(payload.ExtraData); err != nil {
			return eth.SystemConfig{}, err
		}
		d, e := eip1559.DecodeHoloceneExtraData(payload.ExtraData)
		copy(r.EIP1559Params[:], eip1559.EncodeHolocene1559Params(d, e))
	}
	return r, nil
}
