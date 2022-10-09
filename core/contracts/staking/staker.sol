// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library Array {
    struct ArrayMap {
        bytes32[] values;
        mapping(bytes32 => bool) map;
    }

    function push(ArrayMap storage _arr, bytes32 _value) internal {
        if (!_arr.map[_value]) {
            _arr.map[_value] = true;
            _arr.values.push(_value);
        }
    }

    function contains(ArrayMap storage _arr, bytes32 _value)
        internal
        view
        returns (bool)
    {
        return _arr.map[_value];
    }

    function remove(ArrayMap storage _arr, bytes32 _value) internal {
        if (_arr.map[_value]) {
            delete _arr.map[_value];
            for (uint256 i = 0; i <= _arr.values.length; i++) {
                if (_arr.values[i] == _value) {
                    _arr.values[i] = _arr.values[_arr.values.length - 1];
                    _arr.values.pop();
                    break;
                }
            }
        }
    }

    function list(ArrayMap storage _arr)
        internal
        view
        returns (bytes32[] memory)
    {
        return _arr.values;
    }

    function length(ArrayMap storage _arr) internal view returns (uint256) {
        return _arr.values.length;
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
        UNKNOW,
        JOIN,
        EXIT,
        EVIL
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
        VoteType voteType;
        mapping(address => VoteRes) voteMaps;
        address[] votes;
    }

    // epoch => (votee => Proposal)
    mapping(uint256 => mapping(address => Proposal)) public epochProposals;

    // epoch => [votee]
    mapping(uint256 => address[]) public epochProposalVotees;

    mapping(uint256 => bool) epochVoted;

    // block number when votee join or exit or veil
    mapping(address => uint256) lastOperated;

    modifier existSigner(address _signer) {
        require(signers.contains(bytes32(bytes20(_signer))), "invalid signer");
        _;
    }

    event Voted(
        address indexed signer,
        VoteRes indexed agree,
        address votee,
        VoteType voteType
    );
    event JoinedSigner(uint256 indexed cycle, address indexed signer);
    event RejectedSigner(uint256 indexed cycle, address indexed signer);

    constructor(
        uint256 _epoch,
        uint256 _threshold,
        uint256 _fineRatio,
        address[] memory _signers
    ) payable {
        epoch = _epoch;
        threshold = _threshold;
        fineRatio = _fineRatio;
        for (uint256 i = 0; i < _signers.length; i++) {
            signers.push(bytes32(bytes20(_signers[i])));
            balances[_signers[i]] = threshold;
        }
    }

    function vote(ProposalReq[] memory _proposals, bool[] memory _agrees)
        external
        existSigner(msg.sender)
    {
        require(
            _proposals.length == _agrees.length,
            "proposals length mismatch with agrees"
        );
        uint256 cycle_ = block.number / epoch;

        if (
            cycle_ >= 1 &&
            epochProposalVotees[cycle_ - 1].length > 0 &&
            !epochVoted[cycle_ - 1]
        ) {
            _handleProposal(cycle_ - 1);
        }
        require(
            signers.contains(bytes32(bytes20(msg.sender))),
            "rejected signer"
        );
        for (uint256 i = 0; i < _proposals.length; i++) {
            bool existSigner_ = signerContains(_proposals[i].votee);
            Proposal storage proposal_ = epochProposals[cycle_][
                _proposals[i].votee
            ];
            VoteRes voteRes_;
            if (_agrees[i]) {
                voteRes_ = VoteRes.AGREE;
            } else {
                voteRes_ = VoteRes.AGAINST;
            }
            if (existSigner_ && _proposals[i].voteType == VoteType.EXIT) {
                // exit votee
                if (proposal_.voteType == VoteType.UNKNOW) {
                    proposal_.voteType = VoteType.EXIT;
                    proposal_.voteMaps[msg.sender] = voteRes_;
                    proposal_.votes.push(msg.sender);
                    epochProposalVotees[cycle_].push(_proposals[i].votee);
                } else {
                    if (proposal_.voteMaps[msg.sender] == VoteRes.UNKNOW) {
                        proposal_.votes.push(msg.sender);
                    }
                    proposal_.voteMaps[msg.sender] = voteRes_;
                }
                emit Voted(
                    msg.sender,
                    voteRes_,
                    _proposals[i].votee,
                    _proposals[i].voteType
                );
            }

            if (existSigner_ && _proposals[i].voteType == VoteType.EVIL) {
                // reject votee
                if (proposal_.voteType == VoteType.UNKNOW) {
                    proposal_.voteType = VoteType.EVIL;
                    proposal_.voteMaps[msg.sender] = voteRes_;
                    proposal_.votes.push(msg.sender);
                    epochProposalVotees[cycle_].push(_proposals[i].votee);
                } else {
                    if (proposal_.voteMaps[msg.sender] == VoteRes.UNKNOW) {
                        proposal_.votes.push(msg.sender);
                    }
                    proposal_.voteMaps[msg.sender] = voteRes_;
                }
                emit Voted(
                    msg.sender,
                    voteRes_,
                    _proposals[i].votee,
                    _proposals[i].voteType
                );
            }

            if (!existSigner_ && _proposals[i].voteType == VoteType.JOIN) {
                // add votee to signers
                if (proposal_.voteType == VoteType.UNKNOW) {
                    proposal_.voteType = VoteType.JOIN;
                    proposal_.voteMaps[msg.sender] = voteRes_;
                    proposal_.votes.push(msg.sender);
                    epochProposalVotees[cycle_].push(_proposals[i].votee);
                } else {
                    if (proposal_.voteMaps[msg.sender] == VoteRes.UNKNOW) {
                        proposal_.votes.push(msg.sender);
                    }
                    proposal_.voteMaps[msg.sender] = voteRes_;
                }
                emit Voted(
                    msg.sender,
                    voteRes_,
                    _proposals[i].votee,
                    _proposals[i].voteType
                );
            }
        }
    }

    function stake() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw(address _to, uint256 _amount) external {
        require(
            !signers.contains(bytes32(bytes20(msg.sender))),
            "staking, unable to withdraw"
        );
        require(
            getCycle(block.number) > getCycle(lastOperated[msg.sender]),
            "withdraw in the next epoch"
        );
        require(balances[msg.sender] >= _amount, "insufficient amount");
        require(_to != address(0), "zero address is not allowed");
        balances[msg.sender] -= _amount;
        payable(_to).transfer(_amount);
    }

    function signerList() external view returns (address[] memory) {
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

    function epochVotedByBlockNumber(uint256 _blockNumber)
        external
        view
        returns (bool)
    {
        return epochVoted[getCycle(_blockNumber)];
    }

    function checkVoteStatus(
        uint256 _blockNumber,
        address _votee,
        address _voter
    ) external view returns (VoteRes) {
        return epochProposals[getCycle(_blockNumber)][_votee].voteMaps[_voter];
    }

    function _handleProposal(uint256 _cycle) internal {
        mapping(address => Proposal) storage proposals_ = epochProposals[
            _cycle
        ];
        address[] storage proposalVotees_ = epochProposalVotees[_cycle];
        uint256 median_ = signers.length() / 2;

        for (uint256 i = 0; i < proposalVotees_.length; i++) {
            uint256 agreeCount_;
            Proposal storage proposal_ = proposals_[proposalVotees_[i]];

            for (uint256 j = 0; j < proposal_.votes.length; j++) {
                if (proposal_.voteMaps[proposal_.votes[j]] == VoteRes.AGREE) {
                    agreeCount_ += 1;
                }
            }
            if (agreeCount_ > median_) {
                if (proposal_.voteType == VoteType.EXIT) {
                    _exit(_cycle, proposalVotees_[i]);
                }

                if (proposal_.voteType == VoteType.EVIL) {
                    _evil(_cycle, proposalVotees_[i]);
                }

                if (proposal_.voteType == VoteType.JOIN) {
                    _join(_cycle, proposalVotees_[i]);
                }
            }
        }

        epochVoted[_cycle] = true;
    }

    function _exit(uint256 _cycle, address _signer) internal {
        if (signers.contains(bytes32(bytes20(_signer)))) {
            signers.remove(bytes32(bytes20(_signer)));
            lastOperated[_signer] = block.number;
            emit RejectedSigner(_cycle, _signer);
        }
    }

    function _evil(uint256 _cycle, address _signer) internal {
        if (signers.contains(bytes32(bytes20(_signer)))) {
            signers.remove(bytes32(bytes20(_signer)));
            balances[_signer] -= ((threshold * fineRatio) / 100);
            lastOperated[_signer] = block.number;
            emit RejectedSigner(_cycle, _signer);
        }
    }

    function _join(uint256 _cycle, address _signer) internal {
        if (balances[_signer] >= threshold) {
            signers.push(bytes32(bytes20(_signer)));
            lastOperated[_signer] = block.number;
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
