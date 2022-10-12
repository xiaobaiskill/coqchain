package stake

import (
	"context"
	"errors"
	"fmt"
	"math/big"

	"github.com/Ankr-network/coqchain/accounts"
	"github.com/Ankr-network/coqchain/accounts/abi/bind"
	"github.com/Ankr-network/coqchain/common"
	"github.com/Ankr-network/coqchain/core/contracts"
	"github.com/Ankr-network/coqchain/core/contracts/staking/staker"
	"github.com/Ankr-network/coqchain/core/types"
	"github.com/Ankr-network/coqchain/crypto"
	"github.com/Ankr-network/coqchain/ethclient"
	"github.com/Ankr-network/coqchain/log"
	"github.com/Ankr-network/coqchain/params"
)

const (
	VoteReqUnknow uint8 = iota
	VoteReqJoin
	VoteReqExit
)

const (
	VoteResUnknow uint8 = iota
	VoteResAgree
	VoteResAgainst
)

type stake struct {
	contract common.Address
	chainId  *big.Int
	Staker   *staker.Staker
	backend  Backend
}

type signer struct {
	wallet  accounts.Wallet
	account accounts.Account
}

var (
	Stake *stake
	sign  *signer
)

func InitStake(
	backend Backend,
	client *ethclient.Client,
) {
	s, _ := staker.NewStaker(contracts.SlashAddr, client)

	Stake = &stake{
		contract: contracts.SlashAddr,
		chainId:  backend.ChainConfig().ChainID,
		Staker:   s,
		backend:  backend,
	}
}

func InitWallet(
	wallet accounts.Wallet,
	account accounts.Account,
) {
	sign = &signer{
		wallet:  wallet,
		account: account,
	}
}

func Vote(proposals []staker.StakerProposalReq, agrees []bool, txOps ...TxOps) (*types.Transaction, error) {

	txOps = append(txOps, func(tops *bind.TransactOpts) {
		tops.NoSend = true
		// tops.GasPrice = big.NewInt(0)
	})

	tx, err := Stake.Staker.Vote(getTransactorOpts(txOps...), proposals, agrees)
	if err != nil {
		return nil, err
	}
	_, err = SubmitTransaction(context.Background(), Stake.backend, tx)
	return tx, err
}

func SignerList() ([]common.Address, error) {
	return Stake.Staker.SignerList(nil)
}

func CheckVoteStatus(number *big.Int, votee common.Address) (uint8, error) {
	return Stake.Staker.CheckVoteStatus(nil, number, votee, sign.account.Address)
}

func SignerContains() bool {
	res, _ := Stake.Staker.SignerContains(nil, sign.account.Address)
	return res
}

func getTransactorOpts(txOps ...TxOps) *bind.TransactOpts {
	opts := &bind.TransactOpts{
		From: sign.account.Address,
		Signer: func(address common.Address, tx *types.Transaction) (*types.Transaction, error) {
			return sign.wallet.SignTx(sign.account, tx, Stake.chainId)
		},
		Context: context.Background(),
	}

	for _, v := range txOps {
		v(opts)
	}
	return opts
}

type TxOps func(*bind.TransactOpts)

type Backend interface {
	CurrentBlock() *types.Block
	SendTx(ctx context.Context, signedTx *types.Transaction) error
	RPCTxFeeCap() float64     // global tx fee cap for all transaction related APIs
	UnprotectedAllowed() bool // allows only for EIP155 transactions.
	ChainConfig() *params.ChainConfig
}

// SubmitTransaction is a helper function that submits tx to txPool and logs a message.
func SubmitTransaction(ctx context.Context, b Backend, tx *types.Transaction) (common.Hash, error) {
	// If the transaction fee cap is already specified, ensure the
	// fee of the given transaction is _reasonable_.
	if err := checkTxFee(tx.GasPrice(), tx.Gas(), b.RPCTxFeeCap()); err != nil {
		return common.Hash{}, err
	}
	if !b.UnprotectedAllowed() && !tx.Protected() {
		// Ensure only eip155 signed transactions are submitted if EIP155Required is set.
		return common.Hash{}, errors.New("only replay-protected (EIP-155) transactions allowed over RPC")
	}
	if err := b.SendTx(ctx, tx); err != nil {
		return common.Hash{}, err
	}
	// Print a log with full tx details for manual investigations and interventions
	signer := types.MakeSigner(b.ChainConfig(), b.CurrentBlock().Number())
	from, err := types.Sender(signer, tx)
	if err != nil {
		return common.Hash{}, err
	}

	if tx.To() == nil {
		addr := crypto.CreateAddress(from, tx.Nonce())
		log.Info("Submitted contract creation", "hash", tx.Hash().Hex(), "from", from, "nonce", tx.Nonce(), "contract", addr.Hex(), "value", tx.Value())
	} else {
		log.Info("Submitted transaction", "hash", tx.Hash().Hex(), "from", from, "nonce", tx.Nonce(), "recipient", tx.To(), "value", tx.Value())
	}
	return tx.Hash(), nil
}

// checkTxFee is an internal function used to check whether the fee of
// the given transaction is _reasonable_(under the cap).
func checkTxFee(gasPrice *big.Int, gas uint64, cap float64) error {
	// Short circuit if there is no cap for transaction fee at all.
	if cap == 0 {
		return nil
	}
	feeEth := new(big.Float).Quo(new(big.Float).SetInt(new(big.Int).Mul(gasPrice, new(big.Int).SetUint64(gas))), new(big.Float).SetInt(big.NewInt(params.Ether)))
	feeFloat, _ := feeEth.Float64()
	if feeFloat > cap {
		return fmt.Errorf("tx fee (%.2f ether) exceeds the configured cap (%.2f ether)", feeFloat, cap)
	}
	return nil
}
