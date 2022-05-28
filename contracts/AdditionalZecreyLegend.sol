// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.7.0;

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SafeMathUInt128.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "./Utils.sol";

import "./Storage.sol";
import "./Config.sol";
import "./Events.sol";

import "./Bytes.sol";
import "./TxTypes.sol";

import "./UpgradeableMaster.sol";

/// @title Zecrey additional main contract
/// @author Zecrey
contract AdditionalZecreyLegend is Storage, Config, Events, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMathUInt128 for uint128;

    function increaseBalanceToWithdraw(bytes22 _packedBalanceKey, uint128 _amount) internal {
        uint128 balance = pendingBalances[_packedBalanceKey].balanceToWithdraw;
        pendingBalances[_packedBalanceKey] = PendingBalance(balance.add(_amount), FILLED_GAS_RESERVE_VALUE);
    }

    /*
        StateRoot
            AccountRoot
            NftRoot
        Account
            AccountIndex
            AccountNameHash bytes32
            PublicKey
            AssetRoot
            LiquidityRoot
        Asset
           AssetId
           Balance
        Nft
    */
    function performDesert(
        StoredBlockInfo memory _storedBlockInfo,
        address _owner,
        uint32 _accountId,
        uint32 _tokenId,
        uint128 _amount
    ) external {
        require(_accountId <= MAX_ACCOUNT_INDEX, "e");
        require(_accountId != SPECIAL_ACCOUNT_ID, "v");

        require(desertMode, "s");
        // must be in exodus mode
        require(!performedDesert[_accountId][_tokenId], "t");
        // already exited
        require(storedBlockHashes[totalBlocksVerified] == hashStoredBlockInfo(_storedBlockInfo), "u");
        // incorrect stored block info

        // TODO
        //        bool proofCorrect = verifier.verifyExitProof(
        //            _storedBlockHeader.accountRoot,
        //            _accountId,
        //            _owner,
        //            _tokenId,
        //            _amount,
        //            _nftCreatorAccountId,
        //            _nftCreatorAddress,
        //            _nftSerialId,
        //            _nftContentHash,
        //            _proof
        //        );
        //        require(proofCorrect, "x");

        if (_tokenId <= MAX_FUNGIBLE_ASSET_ID) {
            bytes22 packedBalanceKey = packAddressAndAssetId(_owner, uint16(_tokenId));
            increaseBalanceToWithdraw(packedBalanceKey, _amount);
        } else {
            // TODO
            require(_amount != 0, "Z");
            // Unsupported nft amount
            //            TxTypes.WithdrawNFT memory withdrawNftOp = TxTypes.WithdrawNFT({
            //            txType : uint8(TxTypes.TxType.WithdrawNFT),
            //            accountIndex : _nftCreatorAccountId,
            //            toAddress : _nftCreatorAddress,
            //            proxyAddress : _nftCreatorAddress,
            //            nftAssetId : _nftSerialId,
            //            gasFeeAccountIndex : 0,
            //            gasFeeAssetId : 0,
            //            gasFeeAssetAmount : 0
            //            });
            //            pendingWithdrawnNFTs[_tokenId] = withdrawNftOp;
            //            emit WithdrawalNFTPending(_tokenId);
        }
        performedDesert[_accountId][_tokenId] = true;
    }

    function cancelOutstandingDepositsForExodusMode(uint64 _n, bytes[] memory _depositsPubData) external {
        require(desertMode, "8");
        // exodus mode not active
        uint64 toProcess = Utils.minU64(totalOpenPriorityRequests, _n);
        require(toProcess > 0, "9");
        // no deposits to process
        uint64 currentDepositIdx = 0;
        for (uint64 id = firstPriorityRequestId; id < firstPriorityRequestId + toProcess; id++) {
            if (priorityRequests[id].txType == TxTypes.TxType.Deposit) {
                bytes memory depositPubdata = _depositsPubData[currentDepositIdx];
                require(Utils.hashBytesToBytes20(depositPubdata) == priorityRequests[id].hashedPubData, "a");
                ++currentDepositIdx;

                // TODO get address by account name
                address owner = address(0x0);
                TxTypes.Deposit memory _tx = TxTypes.readDepositPubData(depositPubdata);
                bytes22 packedBalanceKey = packAddressAndAssetId(owner, uint16(_tx.assetId));
                pendingBalances[packedBalanceKey].balanceToWithdraw += _tx.amount;
            }
            delete priorityRequests[id];
        }
        firstPriorityRequestId += toProcess;
        totalOpenPriorityRequests -= toProcess;
    }

    // TODO
    uint256 internal constant SECURITY_COUNCIL_2_WEEKS_THRESHOLD = 3;
    uint256 internal constant SECURITY_COUNCIL_1_WEEK_THRESHOLD = 2;
    uint256 internal constant SECURITY_COUNCIL_3_DAYS_THRESHOLD = 1;

    function cutUpgradeNoticePeriod() external {
        requireActive();

        address payable[SECURITY_COUNCIL_MEMBERS_NUMBER] memory SECURITY_COUNCIL_MEMBERS = [
        payable(0x00), payable(0x00), payable(0x00)
        ];
        for (uint256 id = 0; id < SECURITY_COUNCIL_MEMBERS_NUMBER; ++id) {
            if (SECURITY_COUNCIL_MEMBERS[id] == msg.sender) {
                require(upgradeStartTimestamp != 0);
                require(securityCouncilApproves[id] == false);
                securityCouncilApproves[id] = true;
                numberOfApprovalsFromSecurityCouncil++;

                if (numberOfApprovalsFromSecurityCouncil == SECURITY_COUNCIL_2_WEEKS_THRESHOLD) {
                    if (approvedUpgradeNoticePeriod > 2 weeks) {
                        approvedUpgradeNoticePeriod = 2 weeks;
                        emit NoticePeriodChange(approvedUpgradeNoticePeriod);
                    }
                } else if (numberOfApprovalsFromSecurityCouncil == SECURITY_COUNCIL_1_WEEK_THRESHOLD) {
                    if (approvedUpgradeNoticePeriod > 1 weeks) {
                        approvedUpgradeNoticePeriod = 1 weeks;
                        emit NoticePeriodChange(approvedUpgradeNoticePeriod);
                    }
                } else if (numberOfApprovalsFromSecurityCouncil == SECURITY_COUNCIL_3_DAYS_THRESHOLD) {
                    if (approvedUpgradeNoticePeriod > 3 days) {
                        approvedUpgradeNoticePeriod = 3 days;
                        emit NoticePeriodChange(approvedUpgradeNoticePeriod);
                    }
                }

                break;
            }
        }
    }

    /// @notice Reverts unverified blocks
    function revertBlocks(StoredBlockInfo[] memory _blocksToRevert) external {
        requireActive();

        governance.requireActiveValidator(msg.sender);

        uint32 blocksCommitted = totalBlocksCommitted;
        uint32 blocksToRevert = Utils.minU32(uint32(_blocksToRevert.length), blocksCommitted - totalBlocksVerified);
        uint64 revertedPriorityRequests = 0;

        for (uint32 i = 0; i < blocksToRevert; ++i) {
            StoredBlockInfo memory storedBlockInfo = _blocksToRevert[i];
            require(storedBlockHashes[blocksCommitted] == hashStoredBlockInfo(storedBlockInfo), "r");
            // incorrect stored block info

            delete storedBlockHashes[blocksCommitted];

            --blocksCommitted;
            revertedPriorityRequests += storedBlockInfo.priorityOperations;
        }

        totalBlocksCommitted = blocksCommitted;
        totalCommittedPriorityRequests -= revertedPriorityRequests;
        if (totalBlocksCommitted < totalBlocksVerified) {
            totalBlocksVerified = totalBlocksCommitted;
        }

        emit BlocksRevert(totalBlocksVerified, blocksCommitted);
    }

    function createPair(address _tokenA, address _tokenB) external {
        require(_tokenA != _tokenB, 'ia1');
        requireActive();
        (address _token0, address _token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        // Get asset id by its address
        uint16 assetAId = 0;
        uint16 assetBId;
        if (_token0 != address(0)) {
            assetAId = governance.validateAssetAddress(_token0);
        }
        require(!governance.pausedAssets(assetAId), "ia2");
        assetBId = governance.validateAssetAddress(_token1);
        require(!governance.pausedAssets(assetBId), "ia3");
        (assetAId, assetBId) = assetAId < assetBId ? (assetAId, assetBId) : (assetBId, assetAId);

        // Check asset exist
        require(!isTokenPairExist[assetAId][assetBId], 'ip');

        // Create token pair
        governance.validateAssetTokenLister(msg.sender);
        // new token pair index
        isTokenPairExist[assetAId][assetBId] = true;
        tokenPairs[assetAId][assetBId] = totalTokenPairs;

        // Priority Queue request
        TxTypes.CreatePair memory _tx = TxTypes.CreatePair({
        txType : uint8(TxTypes.TxType.CreatePair),
        pairIndex : totalTokenPairs,
        assetAId : assetAId,
        assetBId : assetBId,
        feeRate : governance.assetGovernance().feeRate(),
        treasuryAccountIndex : governance.assetGovernance().treasuryAccountIndex(),
        treasuryRate : governance.assetGovernance().treasuryRate()
        });
        // compact pub data
        bytes memory pubData = TxTypes.writeCreatePairPubDataForPriorityQueue(_tx);
        // add into priority request queue
        addPriorityRequest(TxTypes.TxType.CreatePair, pubData);
        totalTokenPairs++;

        emit CreateTokenPair(_tx.pairIndex, assetAId, assetBId, _tx.feeRate, _tx.treasuryAccountIndex, _tx.treasuryRate);
    }

    struct PairInfo {
        address tokenA;
        address tokenB;
        uint16 feeRate;
        uint32 treasuryAccountIndex;
        uint16 treasuryRate;
    }

    function updatePairRate(PairInfo memory _pairInfo) external {
        // Only governor can update token pair
        governance.requireGovernor(msg.sender);
        requireActive();
        (address _token0, address _token1) = _pairInfo.tokenA < _pairInfo.tokenB ? (_pairInfo.tokenA, _pairInfo.tokenB) : (_pairInfo.tokenB, _pairInfo.tokenA);
        // Get asset id by its address
        uint16 assetAId = 0;
        uint16 assetBId;
        if (_token0 != address(0)) {
            assetAId = governance.validateAssetAddress(_token0);
        }
        require(!governance.pausedAssets(assetAId), "ia2");
        assetBId = governance.validateAssetAddress(_token1);
        require(!governance.pausedAssets(assetBId), "ia3");
        (assetAId, assetBId) = assetAId < assetBId ? (assetAId, assetBId) : (assetBId, assetAId);
        require(isTokenPairExist[assetAId][assetBId], 'pne');

        uint16 _pairIndex = tokenPairs[assetAId][assetBId];

        // Priority Queue request
        TxTypes.UpdatePairRate memory _tx = TxTypes.UpdatePairRate({
        txType : uint8(TxTypes.TxType.UpdatePairRate),
        pairIndex : _pairIndex,
        feeRate : _pairInfo.feeRate,
        treasuryAccountIndex : _pairInfo.treasuryAccountIndex,
        treasuryRate : _pairInfo.treasuryRate
        });
        // compact pub data
        bytes memory pubData = TxTypes.writeUpdatePairRatePubDataForPriorityQueue(_tx);
        // add into priority request queue
        addPriorityRequest(TxTypes.TxType.UpdatePairRate, pubData);

        emit UpdateTokenPair(_pairIndex, _pairInfo.feeRate, _pairInfo.treasuryAccountIndex, _pairInfo.treasuryRate);
    }

    /// @notice Set default factory for our contract. This factory will be used to mint an NFT token that has no factory
    /// @param _factory Address of NFT factory
    function setDefaultNFTFactory(NFTFactory _factory) external {
        governance.requireGovernor(msg.sender);
        require(address(_factory) != address(0), "mb1");
        // Factory should be non zero
        require(address(defaultNFTFactory) == address(0), "mb2");
        // NFTFactory is already set
        defaultNFTFactory = address(_factory);
        emit NewDefaultNFTFactory(address(_factory));
    }

    /// @notice Register NFTFactory to this contract
    /// @param _creatorAccountNameHash accountNameHash of the creator
    /// @param _collectionId collection Id of the NFT related to this creator
    /// @param _factory NFT Factory
    function registerNFTFactory(
        bytes32 _creatorAccountNameHash,
        uint32 _collectionId,
        NFTFactory _factory
    ) external {
        require(address(nftFactories[_creatorAccountNameHash][_collectionId]) == address(0), "Q");
        // Check check accountNameHash belongs to msg.sender
        address creatorAddress = getAddressByAccountNameHash(_creatorAccountNameHash);
        require(creatorAddress == msg.sender, 'ns');

        nftFactories[_creatorAccountNameHash][_collectionId] = address(_factory);
        emit NewNFTFactory(_creatorAccountNameHash, _collectionId, address(_factory));
    }

    /// @notice Saves priority request in storage
    /// @dev Calculates expiration block for request, store this request and emit NewPriorityRequest event
    /// @param _txType Rollup _tx type
    /// @param _pubData _tx pub data
    function addPriorityRequest(TxTypes.TxType _txType, bytes memory _pubData) internal {
        // Expiration block is: current block number + priority expiration delta
        uint64 expirationBlock = uint64(block.number + PRIORITY_EXPIRATION);

        uint64 nextPriorityRequestId = firstPriorityRequestId + totalOpenPriorityRequests;

        bytes20 hashedPubData = Utils.hashBytesToBytes20(_pubData);

        priorityRequests[nextPriorityRequestId] = PriorityTx({
        hashedPubData : hashedPubData,
        expirationBlock : expirationBlock,
        txType : _txType
        });

        emit NewPriorityRequest(msg.sender, nextPriorityRequestId, _txType, _pubData, uint256(expirationBlock));

        totalOpenPriorityRequests++;
    }

    function getAddressByAccountNameHash(bytes32 accountNameHash) public view returns (address){
        return znsController.getOwner(accountNameHash);
    }

    /// @notice Register full exit request - pack pubdata, add priority request
    /// @param _accountNameHash account name hash
    /// @param _asset Token address, 0 address for BNB
    function requestFullExit(bytes32 _accountNameHash, address _asset) public nonReentrant {
        requireActive();
        require(znsController.isRegisteredHash(_accountNameHash), "not registered");
        // get address by account name hash
        address creatorAddress = getAddressByAccountNameHash(_accountNameHash);
        require(msg.sender == creatorAddress, "invalid address");


        uint16 assetId;
        if (_asset == address(0)) {
            assetId = 0;
        } else {
            assetId = governance.validateAssetAddress(_asset);
        }


        // Priority Queue request
        TxTypes.FullExit memory _tx = TxTypes.FullExit({
        txType : uint8(TxTypes.TxType.FullExit),
        accountIndex : 0, // unknown at this point
        accountNameHash : _accountNameHash,
        assetId : assetId,
        assetAmount : 0 // unknown at this point
        });
        bytes memory pubData = TxTypes.writeFullExitPubDataForPriorityQueue(_tx);
        addPriorityRequest(TxTypes.TxType.FullExit, pubData);

        // User must fill storage slot of balancesToWithdraw(msg.sender, tokenId) with nonzero value
        // In this case operator should just overwrite this slot during confirming withdrawal
        bytes22 packedBalanceKey = packAddressAndAssetId(msg.sender, assetId);
        pendingBalances[packedBalanceKey].gasReserveValue = FILLED_GAS_RESERVE_VALUE;
    }

    /// @notice Register full exit nft request - pack pubdata, add priority request
    /// @param _accountNameHash account name hash
    /// @param _nftIndex account NFT index in zecrey network
    function requestFullExitNft(bytes32 _accountNameHash, uint32 _nftIndex) public nonReentrant {
        requireActive();
        require(znsController.isRegisteredHash(_accountNameHash), "nr");
        require(_nftIndex < MAX_NFT_INDEX, "T");
        // get address by account name hash
        address creatorAddress = getAddressByAccountNameHash(_accountNameHash);
        require(msg.sender == creatorAddress, "ia");

        // Priority Queue request
        TxTypes.FullExitNft memory _tx = TxTypes.FullExitNft({
        txType : uint8(TxTypes.TxType.FullExitNft),
        accountIndex : 0, // unknown
        creatorAccountIndex : 0, // unknown
        creatorTreasuryRate : 0,
        nftIndex : _nftIndex,
        collectionId : 0, // unknown
        nftL1Address : address(0x0), // unknown
        accountNameHash : _accountNameHash,
        creatorAccountNameHash : bytes32(0),
        nftContentHash : bytes32(0x0), // unknown,
        nftL1TokenId : 0 // unknown
        });
        bytes memory pubData = TxTypes.writeFullExitNftPubDataForPriorityQueue(_tx);
        addPriorityRequest(TxTypes.TxType.FullExitNft, pubData);
    }

}
