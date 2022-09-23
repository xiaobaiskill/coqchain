// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library Array {
    struct ArrayMap {
        bytes32[] values;
        mapping(bytes32 => bool) map;
    }

    function push(ArrayMap storage arr, bytes32 _value) internal {
        if (!arr.map[_value]) {
            arr.map[_value] = true;
            arr.values.push(_value);
        }
    }

    function contains(ArrayMap storage arr, bytes32 _value)
        internal
        view
        returns (bool)
    {
        return arr.map[_value];
    }

    function remove(ArrayMap storage arr, bytes32 _value) internal {
        if (arr.map[_value]) {
            delete arr.map[_value];
            for (uint256 i = 0; i <= arr.values.length; i++) {
                if (arr.values[i] == _value) {
                    arr.values[i] = arr.values[arr.values.length - 1];
                    arr.values.pop();
                    break;
                }
            }
        }
    }

    function list(ArrayMap storage arr)
        internal
        view
        returns (bytes32[] memory)
    {
        return arr.values;
    }

    function length(ArrayMap storage arr) internal view returns (uint256) {
        return arr.values.length;
    }
}

contract Staker {
    using Array for Array.ArrayMap;
    uint256 public epoch;
    uint256 public threshold;
    uint256 public fineRatio; // 10 = 10%

    Array.ArrayMap signers;
    mapping(address => uint256) public balances;

    enum VoteType {
        REJECT,
        JOIN
    }

    enum VoteRes {
        UNKNOW,
        AGREE,
        AGAINST
    }

    struct ProposalReq {
        address votee;
        VoteType voteType;
    }

    struct Proposal {
        address votee;
        VoteType voteType;
        uint256 agreeCount;
        mapping(address => VoteRes) votes;
    }

    struct ProposalRes {
        address votee;
        VoteType voteType;
        uint256 agreeCount;
    }

    mapping(uint256 => address) public initiateProposals;
    mapping(uint256 => Proposal[]) public proposals;
    mapping(uint256 => bool) epochVoted;

    modifier existSigner(address _signer) {
        require(signers.contains(bytes32(bytes20(_signer))), "invalid signer");
        _;
    }

    event JoinedSigner(uint256 indexed cycle, address indexed signer);
    event RejectedSigner(uint256 indexed cycle, address indexed signer);
    event InitiatedProposal(
        uint256 indexed cycle,
        address indexed initiate,
        ProposalReq[] proposals
    );

    function initiateProposal(ProposalReq[] memory _req)
        public
        existSigner(msg.sender)
    {
        uint256 cycle_ = block.number / epoch;

        if (cycle_ >= 1 && !epochVoted[cycle_ - 1]) {
            _handleProposal(cycle_ - 1);
        }
        require(_req.length > 0, "not found proposal");
        require(proposals[cycle_].length == 0, "initiated proposal");
        address[] memory votees_ = new address[](_req.length);
        for (uint256 i = 0; i < _req.length; i++) {
            if (_req[i].voteType == VoteType.JOIN) {
                require(
                    !signers.contains(bytes32(bytes20(_req[i].votee))),
                    "singer that always exist for JOIN"
                );
                require(
                    balances[_req[i].votee] >= threshold,
                    "insufficient stake amount"
                );
            }

            if (_req[i].voteType == VoteType.REJECT) {
                require(
                    signers.contains(bytes32(bytes20(_req[i].votee))),
                    "signer does not exist for REJECT"
                );
            }

            require(!_exist(votees_, _req[i].votee), "duplicate votee");
            votees_[i] = _req[i].votee;

            uint256 idx_ = proposals[cycle_].length;
            proposals[cycle_].push();
            Proposal storage proposal_ = proposals[cycle_][idx_];
            proposal_.votee = _req[i].votee;
            proposal_.voteType = _req[i].voteType;
        }
        initiateProposals[cycle_] = msg.sender;
        emit InitiatedProposal(cycle_, msg.sender, _req);
    }

    function vote(uint256[] memory _indexs, bool[] memory _agrees)
        public
        existSigner(msg.sender)
    {
        require(
            _indexs.length == _agrees.length,
            "indexs length mismatch with agrees"
        );
        uint256 cycle_ = block.number / epoch;

        Proposal[] storage proposals_ = proposals[cycle_];
        require(
            proposals_.length == _indexs.length,
            "proposals length mismatch with indexs"
        );
        for (uint256 i = 0; i < _indexs.length; i++) {
            if (proposals_[i].votes[msg.sender] == VoteRes.UNKNOW) {
                if (_agrees[i]) {
                    proposals_[i].agreeCount += 1;
                    proposals_[i].votes[msg.sender] = VoteRes.AGREE;
                } else {
                    proposals_[i].votes[msg.sender] = VoteRes.AGAINST;
                }
            }
        }
    }

    function stake() public payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw(address _to, uint256 _amount) public {
        require(
            !signers.contains(bytes32(bytes20(msg.sender))),
            "staking, unable to withdraw"
        );
        require(balances[msg.sender] >= _amount, "insufficient amount");
        balances[msg.sender] -= _amount;
        payable(_to).transfer(_amount);
    }

    function getProposals(uint256 _blockNumber)
        public
        view
        returns (address, ProposalRes[] memory)
    {
        uint256 cycle_ = _blockNumber / epoch;
        Proposal[] storage proposals_ = proposals[cycle_];
        ProposalRes[] memory res_ = new ProposalRes[](proposals_.length);
        for (uint256 i = 0; i < proposals_.length; i++) {
            res_[i] = ProposalRes({
                votee: proposals_[i].votee,
                voteType: proposals_[i].voteType,
                agreeCount: proposals_[i].agreeCount
            });
        }
        return (initiateProposals[cycle_], res_);
    }

    function signerList() public view returns (address[] memory) {
        bytes32[] memory sigsBytes_ = signers.list();
        address[] memory sig_ = new address[](sigsBytes_.length);
        for (uint256 i = 0; i < sigsBytes_.length; i++) {
            sig_[i] = address(bytes20(sigsBytes_[i]));
        }
        return sig_;
    }

    function signerContains(address _signer) public view returns (bool) {
        return signers.contains(bytes32(bytes20(_signer)));
    }

    function getCycle(uint256 _blockNumber) public view returns (uint256) {
        return _blockNumber / epoch;
    }

    function _handleProposal(uint256 _cycle) internal {
        Proposal[] storage proposals_ = proposals[_cycle];
        uint256 median_ = signers.length() / 2;
        for (uint256 i = 0; i < proposals_.length; i++) {
            if (proposals_[i].agreeCount > median_) {
                if (proposals_[i].voteType == VoteType.REJECT) {
                    _reject(_cycle, proposals_[i].votee);
                } else {
                    _join(_cycle, proposals_[i].votee);
                }
            }
        }
        epochVoted[_cycle] = true;
    }

    function _reject(uint256 _cycle, address _signer) internal {
        if (signers.contains(bytes32(bytes20(_signer)))) {
            signers.remove(bytes32(bytes20(_signer)));
            balances[_signer] -= ((threshold * fineRatio) / 100);
            emit RejectedSigner(_cycle, _signer);
        }
    }

    function _join(uint256 _cycle, address _signer) internal {
        if (balances[_signer] >= threshold) {
            signers.push(bytes32(bytes20(_signer)));
            emit JoinedSigner(_cycle, _signer);
        }
    }

    function _exist(address[] memory users, address user)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == user) {
                return true;
            }
        }
        return false;
    }
}
