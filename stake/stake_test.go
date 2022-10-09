package stake

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/Ankr-network/coqchain/accounts"
	"github.com/Ankr-network/coqchain/accounts/abi/bind"
	"github.com/Ankr-network/coqchain/accounts/keystore"
	"github.com/Ankr-network/coqchain/common"
	"github.com/Ankr-network/coqchain/common/hexutil"
	"github.com/Ankr-network/coqchain/core/contracts"
	"github.com/Ankr-network/coqchain/core/contracts/staking/staker"
	"github.com/Ankr-network/coqchain/ethclient"
)

func TestMain(m *testing.M) {
	contracts.SlashAddr = common.HexToAddress("0x179423Bc79Dc3A6ae376BAEc2b2CdE00ce7C5179")
	client, _ := ethclient.Dial("https://testnet.ankr.com")
	chainId, _ := client.ChainID(context.Background())

	InitStake(client, chainId)

	ks := keystore.NewKeyStore("./", keystore.StandardScryptN, keystore.StandardScryptP)
	account := ks.Accounts()[0]
	ks.Unlock(account, "1234")

	for _, v := range ks.Wallets() {
		if v.Contains(account) {
			InitWallet(v, account)
		}
	}

	m.Run()
}

func TestSignData(t *testing.T) {
	bytesData, err := sign.wallet.SignData(sign.account, accounts.MimetypeClique, []byte("aaaa"))
	if err != nil {
		t.Error(err)
	} else {
		t.Log(hexutil.Encode(bytesData))
	}
}

func TestVote(t *testing.T) {
	var proposals []staker.StakerProposalReq = []staker.StakerProposalReq{
		{
			Votee:    common.HexToAddress("0x6A92F2E354228e866C44419860233Cc23bec0d8A"),
			VoteType: VoteReqEvil,
		},
	}

	var agrees []bool = []bool{true}
	tx, err := Vote(proposals, agrees, func(opts *bind.TransactOpts) {
		// opts.NoSend = true
	})
	if err != nil {
		t.Error(err)
	} else {
		bytesData, _ := json.Marshal(tx)
		t.Log(string(bytesData))
	}
}
