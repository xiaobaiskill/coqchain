package core

import "github.com/Ankr-network/coqchain/common"

type genesisAllocItem struct {
	addr common.Address
	GenesisAccount
}

type genesisAllocList []genesisAllocItem

func (a genesisAllocList) Len() int { return len(a) }
func (a genesisAllocList) Less(i, j int) bool {
	return a[i].addr.Hash().Big().Cmp(a[j].addr.Hash().Big()) < 0
}
func (a genesisAllocList) Swap(i, j int) { a[i], a[j] = a[j], a[i] }
