package stake

import (
	"context"
	"math/big"

	"github.com/Ankr-network/coqchain/accounts"
	"github.com/Ankr-network/coqchain/accounts/abi/bind"
	"github.com/Ankr-network/coqchain/common"
	"github.com/Ankr-network/coqchain/core/contracts"
	"github.com/Ankr-network/coqchain/core/contracts/staking/staker"
	"github.com/Ankr-network/coqchain/core/types"
	"github.com/Ankr-network/coqchain/ethclient"
)

const (
	VoteReqUnknow uint8 = iota
	VoteReqJoin
	VoteReqExit
	VoteReqEvil
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
	client *ethclient.Client,
	chainId *big.Int,
) {
	s, _ := staker.NewStaker(contracts.SlashAddr, client)

	Stake = &stake{
		contract: contracts.SlashAddr,
		chainId:  chainId,
		Staker:   s,
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
	return Stake.Staker.Vote(getTransactorOpts(txOps...), proposals, agrees)
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
