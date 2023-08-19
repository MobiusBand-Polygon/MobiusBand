// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Bucket.sol";
import "./IV3SwapRouter.sol";
import "./INonfungiblePositionManager.sol";

interface IERC20EX is IERC20{
    function _mint(address account, uint256 amount) external;
    function _burn(address account, uint256 amount) external;
    function getTokenAmountFromMatic(uint256 account) external view returns (uint256);
}

contract MobiusBand is ReentrancyGuard, Bucket {
    uint256 public constant PRINCIPAL_RATIO = 500000; //50%
    uint256 public constant INVEST_RATIO = 300000; //30%
    uint256 public constant RECOMMENDREWARD_RATIO = 20000; //2%
    uint256 public constant REFERRER_RATIO = 60000; //6%
    uint256 public constant BUYBACK_RATIO = 50000; //5%
    uint256 public constant SUPERNODE_RATIO = 10000; //1%
    uint256 public constant BONUS_RATIO = 20000; //2%
    uint256 public constant COMMUNITY_RATIO = 20000; //2%
    uint256 public constant PLATFORM_RATIO = 20000; //2%
    uint256 public constant PRICE_PRECISION = 1e6;

    uint256 public constant ACCURACY = 1e18;
    uint256 public constant DEFAULT_INVEST_RETURN_RATE = 10000;

    uint256 public constant MAX_INVEST = 1e3 * ACCURACY;
    uint256 public constant MIN_INVEST = 1e2 * ACCURACY;

    uint256 public constant TIME_UNIT = 1 days;

    uint256 public constant MAX_SEARCH_DEPTH = 50;
    uint256 public constant RANKED_INCENTIVE = 60;

    address public bonusAddress;
    address public communityAddress;
    address public platformAddress;
    uint256 public currentEpochs;

    mapping(uint256 => mapping(address => PositionInfo[]))[6] public roundLedgers;
    mapping(uint256 => RoundInfo)[6] public roundInfos;
    mapping(address => UserRoundInfo[])[6] public userRoundsInfos;
    mapping(address => UserGlobalInfo) public userGlobalInfos;
    mapping(address => UserCapitalFlowInfo) public userCapitalFlowInfs;

    mapping(address => address[]) public children;
    uint256 public totalFlowAmount;
    mapping(uint256 => uint256) public epochCurrentInvestAmount;
    mapping(uint256 => uint256) public epochCurrentPrincipalAmount;

    uint256 internal temporaryTokenAmount;
    uint256 internal temporaryTotalProperty;
    uint256 internal temporaryTotalMatic;

    bool[] public epochStopLoss;
    uint256 public totalLosePrincipal;
    uint256 public stopLossAmount;

    address public operator;
    bool public gamePaused;

    IV3SwapRouter router = IV3SwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    INonfungiblePositionManager positionManager =
    INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    uint24 constant defaultFee = 3000;
    address public tokenAddress = 0xF70e40031adf2EF46B8fa600BdE1CEbAbBcE0065;
    address public maticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    uint256 public positionId = 1015851;
    uint256 public lpMaticAmount;
    uint256 public lpMaticLimit;

    uint256 public tokenConsumeRatio;
    uint256 public startUseTokenNum;
    uint256[9] public levelSales = [1000 * ACCURACY, 3000 * ACCURACY, 5000 * ACCURACY, 10000 * ACCURACY, 50000 * ACCURACY, 100000 * ACCURACY, 500000 * ACCURACY, 1000000 * ACCURACY, 5000000 * ACCURACY];
    uint256[5] public tokenOutputRatio;

    struct FundTarget {
        uint256 lastCheckTime;
        uint256 amount;
        uint256 achievedAmount;
    }

    struct UserGlobalInfo {
        address referrer;
        uint256 totalReferrerReward;
        uint256 referrerRewardClaimed;
        uint256 maxChildrenSales;
        uint256 sales;
        uint256 totalPositionAmount;
        uint256 reportedSales;
        uint8 salesLevel;
        bool supernode;
        address supernodeAddress;
    }

    struct UserCapitalFlowInfo {
        uint256 totalPrincipalClaimed;
        uint256 totalRecommendReward;
        uint256 totalExpectedInvestReturnAmount;
        uint256 totalExpectedInvestRewardAmount;
        uint256 totalConvertTokenAmount;
    }

    struct PositionInfo {
        uint256 amount;
        uint256 openTime;
        uint256 expiryTime;
        uint256 investReturnRate;
        uint256 withdrawnAmount;
        uint256 investReturnAmount;
        uint256 index;
        uint256 removalTime;
    }

    struct LinkedPosition {
        address user;
        uint256 userPositionIndex;
    }

    struct RoundInfo {
        FundTarget fundTarget;
        uint256 totalPositionAmount;
        uint256 currentPrincipalAmount;
        uint256 currentInvestAmount;
        uint256 totalPositionCount;
        uint256 currentPositionCount;
        uint256 incentiveSnapshot;
        uint256 head;
        mapping(uint256 => LinkedPosition) linkedPositions;
        mapping(address => uint256) ledgerRoundToUserRoundIndex;
        bool stopLoss;
    }

    struct UserRoundInfo {
        uint256 epoch;
        uint256 totalPositionAmount;
        uint256 currentPrincipalAmount;
        uint256 totalWithdrawnAmount;
        uint256 totalClosedPositionCount;
    }

    struct ReferrerSearch {
        uint256 currentUserSales;
        uint256 currentReferrerSales;
        address currentReferrer;
        uint256 currentReferrerAmount;
        uint256 levelDiffAmount;
        uint256 leftLevelDiffAmount;
        uint256 levelDiffAmountPerLevel;
        uint256 currentReferrerMaxChildSales;
        uint256 currentUserTotalPosAmount;
        uint256 currentUserReportedSales;
        address currentUser;
        uint256 currentReferrerRoundsLength;
        uint256 currentReferrerNewEpoch;
        uint8 depth;
        uint8 currentLevelDiff;
        uint8 baseSalesLevel;
        uint8 currentReferrerLevel;
        bool levelDiffDone;
        bool levelSearchDone;
        bool levelSalesDone;
    }

    struct OpenPositionParams {
        uint256 principalAmount;
        uint256 investAmount;
        uint256 referrerAmount;
        uint256 investReturnRate;
    }

    struct AssetPackageInfo {
        uint256 birthday;
        uint256 amount;
        uint256 release;
        uint256 withdrawn;
        bool state;
    }

    event PositionOpened(address indexed user, uint256 indexed ledgeType, uint256 indexed epoch, uint256 positionIndex, uint256 amount);
    event PositionClosed(address indexed user, uint256 indexed ledgeType, uint256 indexed epoch, uint256 positionIndex, uint256 amount);
    event NewReferrer(address indexed user, address indexed referrer);
    event NewRound(uint256 indexed epoch, uint256 indexed ledgeType);
    event ReferrerRewardAdded(address indexed user, uint256 amount, uint256 indexed rewardType);
    event ReferrerRewardClaimed(address indexed user, uint256 amount);
    event SalesLevelUpdated(address indexed user, uint8 level);
    event SllocationAmount(address form, address to, uint256 amount);

    mapping(address => AssetPackageInfo[]) public AssetPackage;

    modifier notContract() {
        require(msg.sender == tx.origin, "Contract not allowed");
        _;
    }

    constructor(
        address _bonusAddress,
        address _communityAddress,
        address _platformAddress,
        address _operator
    ) {
        require(
            _bonusAddress != address(0) && _communityAddress != address(0) && _platformAddress != address(0) && _operator != address(0),
            "Invalid address provided"
        );

        UserGlobalInfo storage userGlobalInfo;
        userGlobalInfo = userGlobalInfos[_platformAddress];
        userGlobalInfo.referrer = address(0);
        userGlobalInfo.salesLevel = 12;
        children[address(0)].push(_platformAddress);

        bonusAddress = _bonusAddress;
        communityAddress = _communityAddress;
        platformAddress = _platformAddress;
        operator = _operator;
        gamePaused = false;

        IERC20(tokenAddress).approve(address(router),type(uint).max);
        IERC20(tokenAddress).approve(address(positionManager),type(uint).max);

        tokenConsumeRatio = 100000;
        tokenOutputRatio = [100 * PRICE_PRECISION, 50 * PRICE_PRECISION, 25 * PRICE_PRECISION, 10 * PRICE_PRECISION, PRICE_PRECISION];
        lpMaticLimit = 500000 * ACCURACY;
        startUseTokenNum = 25000000 * ACCURACY;
    }

    function addCurrentInvestAmount(uint256 epoch, bool _add, uint256 num) external {
        require(msg.sender == operator, "Only operator");
        if(_add){
            epochCurrentInvestAmount[epoch] += num;
        }else{
            epochCurrentInvestAmount[epoch] -= num;
        }
    }

    function setTokenConsumeRatio(uint256 _ratio) external {
        require(msg.sender == operator, "Only operator");
        tokenConsumeRatio = _ratio;
    }

    function updateTokenOutputRatio(uint256[] memory _ratio) external {
        require(msg.sender == operator, "Only operator");
        for (uint256 i = 0; i < 5; i++) {
            tokenOutputRatio[i] = _ratio[i];
        }
    }

    function setPause(bool _paused) external {
        require(msg.sender == operator, "Only operator");
        gamePaused = _paused;
    }

    function setlpMaticLimit(uint256 amount) public {
        require(msg.sender == operator, "Only operator");
        lpMaticLimit = amount;
    }

    function setStartUseTokenNum(uint256 amount) public {
        require(msg.sender == operator, "Only operator");
        startUseTokenNum = amount;
    }

    function batchSetReferrerInfo(
        address[] memory users,
        address[] memory referrers,
        uint8[] memory salesLevels,
        bool[] memory supernodes,
        address[] memory supernodeAddresss
    ) external {
        require(msg.sender == operator, "Only admin");
        require(users.length == referrers.length && users.length == salesLevels.length && users.length == supernodes.length && users.length == supernodeAddresss.length, "Invalid input");
        UserGlobalInfo storage userGlobalInfo;
        uint256 userLength = users.length;
        for (uint256 i = 0; i < userLength; ++i) {
            require(users[i] != address(0), "Invalid address provided");
            userGlobalInfo = userGlobalInfos[users[i]];
            require(userGlobalInfo.referrer == address(0), "Referrer already set");
            userGlobalInfo.referrer = referrers[i];
            userGlobalInfo.salesLevel = salesLevels[i];
            userGlobalInfo.supernode = supernodes[i];
            userGlobalInfo.supernodeAddress = supernodeAddresss[i];
            children[referrers[i]].push(users[i]);
        }
    }

    function setStock(
        uint256 ledgerType,
        uint8[] memory typeDays,
        uint16[] memory stock
    ) public {
        require(ledgerType > 0, "Invalid ledger type");
        require(ledgerType < 4, "Invalid ledger type");
        require(stock.length > 0, "Invalid stock array");
        require(typeDays.length == stock.length, "Invalid params");

        _setStock(ledgerType, typeDays, stock);
    }

    function openPosition(
        address referrer
    ) public payable notContract nonReentrant {
        require(msg.value >= MIN_INVEST, "Too small");
        require(msg.value <= MAX_INVEST, "Too large");
        require(!gamePaused, "Paused");

        UserGlobalInfo storage userGlobalInfo = userGlobalInfos[msg.sender];
        address _referrer = userGlobalInfo.referrer;

        if (_referrer == address(0) && children[msg.sender].length == 0) {
            _referrer = referrer;
            require((referrer != address(0) && referrer != msg.sender) || referrer == platformAddress, "Invalid referrer 1");

            require(userGlobalInfos[referrer].totalPositionAmount > 0 || referrer == platformAddress, "Invalid referrer 2");

            require(userGlobalInfos[referrer].referrer != address(0) || children[referrer].length > 0 || referrer == platformAddress,  "Invalid referrer 3");

            userGlobalInfo.referrer = referrer;
            children[referrer].push(msg.sender);

        }

        if(userGlobalInfo.supernodeAddress == address(0)){
            if(userGlobalInfos[_referrer].supernode == true){
                userGlobalInfo.supernodeAddress = _referrer;
            }else if(userGlobalInfos[_referrer].supernodeAddress != address(0)){
                userGlobalInfo.supernodeAddress = userGlobalInfos[_referrer].supernodeAddress;
            }
        }

        if(totalFlowAmount >= startUseTokenNum){
            uint256 useTokenAmount = msg.value * tokenConsumeRatio / PRICE_PRECISION;
            require(IERC20(tokenAddress).balanceOf(msg.sender) >= useTokenAmount, "Insufficient Token amount");
            require(IERC20(tokenAddress).allowance(msg.sender, address(this)) >= useTokenAmount, "Insufficient Token allowance");
            IERC20EX(tokenAddress)._burn(msg.sender, useTokenAmount);
        }

        bool success;

        {
            uint256 recommendReward = msg.value * RECOMMENDREWARD_RATIO / PRICE_PRECISION;
            userCapitalFlowInfs[_referrer].totalRecommendReward += recommendReward;
            (success, ) = _referrer.call{value: recommendReward}("");
            require(success, "Transfer failed.");
            emit SllocationAmount(address(this), _referrer, recommendReward);
        }

        {
            uint256 buybackAmount = msg.value * BUYBACK_RATIO / PRICE_PRECISION;
            if(lpMaticAmount < lpMaticLimit){
                uint256 backTokenAmount = IERC20EX(tokenAddress).getTokenAmountFromMatic(buybackAmount);
                if(IERC20EX(tokenAddress).balanceOf(address(this)) >= backTokenAmount){
                    addLiquitidyWithId(backTokenAmount,buybackAmount);
                    lpMaticAmount += buybackAmount;
                }
            }else{
                uint256 historyTokenAmount = IERC20(tokenAddress).balanceOf(address(this));
                buyBurn(buybackAmount);
                uint256 nowTokenAmount = IERC20(tokenAddress).balanceOf(address(this));
                uint256 differenceTokenAmount = nowTokenAmount - historyTokenAmount;
                if(differenceTokenAmount > 0){
                    IERC20EX(tokenAddress)._burn(address(this), differenceTokenAmount);
                }
            }
        }

        {
            if(userGlobalInfo.supernodeAddress != address(0)){
                uint256 supernodeAmount = msg.value * SUPERNODE_RATIO / PRICE_PRECISION;
                (success, ) = userGlobalInfo.supernodeAddress.call{value: supernodeAmount}("");
                require(success, "Transfer failed.");
                emit SllocationAmount(address(this), userGlobalInfo.supernodeAddress, supernodeAmount);
            }
        }

        {
            uint256 organization = msg.value * BONUS_RATIO / PRICE_PRECISION;
            (success, ) = bonusAddress.call{value: organization}("");
            require(success, "Transfer failed.");
            emit SllocationAmount(address(this), bonusAddress, organization);
            (success, ) = communityAddress.call{value: organization}("");
            require(success, "Transfer failed.");
            emit SllocationAmount(address(this), communityAddress, organization);
            (success, ) = platformAddress.call{value: organization}("");
            require(success, "Transfer failed.");
            emit SllocationAmount(address(this), platformAddress, organization);
        }

        uint256 MagicBoxAmount1 =  msg.value * 20 / 100;
        uint256 MagicBoxAmount2 =  msg.value * 15 / 100;
        uint256 MagicBoxAmount3 =  msg.value * 25 / 100;
        uint256 MagicBoxAmount4 =  msg.value * 40 / 100;
        uint256 distributionAmount = 0;
        distributionAmount += setPosition(MagicBoxAmount1,0);
        distributionAmount += setPosition(MagicBoxAmount2,1);
        distributionAmount += setPosition(MagicBoxAmount3,2);
        distributionAmount += setPosition(MagicBoxAmount4,3);

        totalFlowAmount += msg.value;
    }

    function setPosition (
        uint256 amountValue,
        uint256 ledgerType
    ) internal returns (uint256) {
        require(ledgerType < 4, "Invalid ledger type");

        RoundInfo storage roundInfo = roundInfos[ledgerType][currentEpochs];

        UserRoundInfo storage userRoundInfo;

        OpenPositionParams memory params = OpenPositionParams({
            principalAmount: (amountValue * PRINCIPAL_RATIO) / PRICE_PRECISION,
            investAmount: (amountValue * INVEST_RATIO) / PRICE_PRECISION,
            referrerAmount: (amountValue * REFERRER_RATIO) / PRICE_PRECISION,
            investReturnRate: DEFAULT_INVEST_RETURN_RATE
        });

        uint256 userRoundInfoLength = userRoundsInfos[ledgerType][msg.sender].length;
        if (
            userRoundInfoLength == 0 ||
            userRoundsInfos[ledgerType][msg.sender][userRoundInfoLength - 1].epoch < currentEpochs
        ) {

            UserRoundInfo memory _userRoundInfo;
            _userRoundInfo = UserRoundInfo({
                epoch: currentEpochs,
                totalPositionAmount: 0,
                currentPrincipalAmount: 0,
                totalWithdrawnAmount: 0,
                totalClosedPositionCount: 0
            });

            userRoundsInfos[ledgerType][msg.sender].push(_userRoundInfo);
            roundInfo.ledgerRoundToUserRoundIndex[msg.sender] = userRoundInfoLength;
            userRoundInfoLength += 1;
        }

        if(epochStopLoss.length == 0 || epochStopLoss.length < (currentEpochs + 1)){
            epochStopLoss.push(false);
        }

        userRoundInfo = userRoundsInfos[ledgerType][msg.sender][userRoundInfoLength - 1];
        userRoundInfo.totalPositionAmount += amountValue;
        userRoundInfo.currentPrincipalAmount += params.principalAmount;

        roundInfo.totalPositionAmount += amountValue;
        roundInfo.currentPrincipalAmount += params.principalAmount;
        epochCurrentPrincipalAmount[currentEpochs] += params.principalAmount;

        epochCurrentInvestAmount[currentEpochs] += params.investAmount;
        roundInfo.currentPositionCount += 1;
        roundInfo.incentiveSnapshot += amountValue;
        roundInfo.totalPositionCount += 1;

        uint256 userTotalPositionCount = roundLedgers[ledgerType][currentEpochs][msg.sender].length;

        {
            uint256 openTime = block.timestamp;
            uint256 expiryTime = block.timestamp;
            if (ledgerType == 0) {
                expiryTime += TIME_UNIT;
            } else {
                expiryTime += _pickDay(ledgerType, roundInfo.totalPositionCount) * TIME_UNIT;
            }

            PositionInfo memory positionInfo = PositionInfo({
                amount: amountValue,
                openTime: openTime,
                expiryTime: expiryTime,
                investReturnRate: params.investReturnRate,
                withdrawnAmount: 0,
                investReturnAmount: 0,
                index: userTotalPositionCount,
                removalTime: 0
            });

            roundLedgers[ledgerType][currentEpochs][msg.sender].push(positionInfo);
        }

        _distributeReferrerReward(amountValue, msg.sender, params.referrerAmount);

        {

            mapping(uint256 => LinkedPosition) storage linkedPositions = roundInfo.linkedPositions;

            LinkedPosition storage linkedPosition = linkedPositions[roundInfo.totalPositionCount - 1];
            linkedPosition.user = msg.sender;
            linkedPosition.userPositionIndex = userTotalPositionCount;

            if (roundInfo.totalPositionCount - roundInfo.head > RANKED_INCENTIVE) {

                LinkedPosition storage headLinkedPosition = linkedPositions[roundInfo.head];
                PositionInfo storage headPositionInfo = roundLedgers[ledgerType][currentEpochs][headLinkedPosition.user][
                                headLinkedPosition.userPositionIndex
                    ];

                unchecked {
                    roundInfo.incentiveSnapshot -= headPositionInfo.amount;
                }

                roundInfo.head += 1;
            }
        }

        return  params.principalAmount + params.investAmount + params.referrerAmount;
    }

    function closePosition(
        uint256 ledgerType,
        uint256 epoch,
        uint256 positionIndex
    ) external notContract nonReentrant {
        require(ledgerType < 4, "Invalid ledger type");
        require(epoch <= currentEpochs, "Invalid epoch");

        PositionInfo[] storage positionInfos = roundLedgers[ledgerType][epoch][msg.sender];
        require(positionIndex < positionInfos.length, "Invalid position index");

        PositionInfo storage positionInfo = positionInfos[positionIndex];

        RoundInfo storage roundInfo = roundInfos[ledgerType][epoch];

        UserGlobalInfo storage userGlobalInfo = userGlobalInfos[msg.sender];

        UserCapitalFlowInfo storage userCapitalFlowInfo = userCapitalFlowInfs[msg.sender];

        _safeClosePosition(ledgerType, epoch, positionIndex, positionInfo, roundInfo, userGlobalInfo, userCapitalFlowInfo);
    }

    function batchClosePositions(
        uint256 ledgerType,
        uint256 epoch,
        uint256[] calldata positionIndexes
    ) external nonReentrant {
        require(ledgerType < 4, "Invalid ledger type");
        require(epoch <= currentEpochs, "Invalid epoch");
        require(positionIndexes.length > 0, "Invalid position indexes");

        PositionInfo[] storage positionInfos = roundLedgers[ledgerType][epoch][msg.sender];

        RoundInfo storage roundInfo = roundInfos[ledgerType][epoch];

        PositionInfo storage positionInfo;

        UserGlobalInfo storage userGlobalInfo = userGlobalInfos[msg.sender];

        UserCapitalFlowInfo storage userCapitalFlowInfo = userCapitalFlowInfs[msg.sender];

        uint256 positionIndexesLength = positionIndexes.length;
        uint256 positionInfosLength = positionInfos.length;
        for (uint256 i = 0; i < positionIndexesLength; ++i) {
            require(positionIndexes[i] < positionInfosLength, "Invalid position index");

            positionInfo = positionInfos[positionIndexes[i]];
            _safeClosePosition(ledgerType, epoch, positionIndexes[i], positionInfo, roundInfo, userGlobalInfo, userCapitalFlowInfo);
        }
    }

    function claimReferrerReward(address referrer) external notContract nonReentrant {
        require(referrer != address(0), "Invalid referrer address");
        UserGlobalInfo storage userGlobalInfo = userGlobalInfos[referrer];
        uint256 claimableAmount = userGlobalInfo.totalReferrerReward - userGlobalInfo.referrerRewardClaimed;
        require(claimableAmount > 0, "No claimable amount");
        userGlobalInfo.referrerRewardClaimed += claimableAmount;
        {
            (bool success, ) = referrer.call{value: claimableAmount}("");
            require(success, "Transfer failed.");
        }

    }

    function getUserRounds(
        uint256 ledgerType,
        address user,
        uint256 cursor,
        uint256 size
    ) external view returns (UserRoundInfo[] memory, uint256) {
        uint256 length = size;
        uint256 roundCount = userRoundsInfos[ledgerType][user].length;
        if (cursor + length > roundCount) {
            length = roundCount - cursor;
        }

        UserRoundInfo[] memory userRoundInfos = new UserRoundInfo[](length);
        for (uint256 i = 0; i < length; ++i) {
            userRoundInfos[i] = userRoundsInfos[ledgerType][user][cursor + i];
        }

        return (userRoundInfos, cursor + length);
    }

    function getUserRoundsLength(uint256 ledgerType, address user) external view returns (uint256) {
        return userRoundsInfos[ledgerType][user].length;
    }

    function getUserRoundLedgers(
        uint256 ledgerType,
        uint256 epoch,
        address user,
        uint256 cursor,
        uint256 size
    ) external view returns (PositionInfo[] memory, uint256) {
        uint256 length = size;
        uint256 positionCount = roundLedgers[ledgerType][epoch][user].length;
        if (cursor + length > positionCount) {
            length = positionCount - cursor;
        }

        PositionInfo[] memory positionInfos = new PositionInfo[](length);
        for (uint256 i = 0; i < length; ++i) {
            positionInfos[i] = roundLedgers[ledgerType][epoch][user][cursor + i];
        }

        return (positionInfos, cursor + length);
    }

    function getUserRoundLedgersLength(
        uint256 ledgerType,
        uint256 epoch,
        address user
    ) external view returns (uint256) {
        return roundLedgers[ledgerType][epoch][user].length;
    }

    function getChildren(
        address user,
        uint256 cursor,
        uint256 size
    ) external view returns (address[] memory, uint256) {
        uint256 length = size;
        uint256 childrenCount = children[user].length;
        if (cursor + length > childrenCount) {
            length = childrenCount - cursor;
        }

        address[] memory _children = new address[](length);
        for (uint256 i = 0; i < length; ++i) {
            _children[i] = children[user][cursor + i];
        }

        return (_children, cursor + length);
    }

    function getLedgerRoundToUserRoundIndex(
        uint256 ledgerType,
        uint256 epoch,
        address user
    ) external view returns (uint256) {
        return roundInfos[ledgerType][epoch].ledgerRoundToUserRoundIndex[user];
    }

    function getChildrenLength(address user) external view returns (uint256) {
        return children[user].length;
    }

    function getUserDepartSalesAndLevel(address user) external view returns (uint256, uint8) {
        UserGlobalInfo storage userGlobalInfo = userGlobalInfos[user];
        return (userGlobalInfo.sales - userGlobalInfo.maxChildrenSales, userGlobalInfo.salesLevel);
    }

    function _safeClosePosition(
        uint256 ledgerType,
        uint256 epoch,
        uint256 positionIndex,
        PositionInfo storage positionInfo,
        RoundInfo storage roundInfo,
        UserGlobalInfo storage userGlobalInfo,
        UserCapitalFlowInfo storage userCapitalFlowInfo
    ) internal {
        require(positionInfo.withdrawnAmount == 0, "Position already claimed");
        require(positionInfo.expiryTime <= block.timestamp || epochStopLoss[epoch], "Position not expired");

        uint256 targetRoundInfoIndex = roundInfo.ledgerRoundToUserRoundIndex[msg.sender];
        UserRoundInfo storage userRoundInfo = userRoundsInfos[ledgerType][msg.sender][targetRoundInfoIndex];

        uint256 payoutAmount;
        uint256 principalAmount = (positionInfo.amount * PRINCIPAL_RATIO) / PRICE_PRECISION;
        roundInfo.currentPositionCount -= 1;
        roundInfo.currentPrincipalAmount -= principalAmount;
        userRoundInfo.currentPrincipalAmount -= principalAmount;

        temporaryTokenAmount = 0;
        if (!epochStopLoss[epoch]) {

            payoutAmount += principalAmount;
            userCapitalFlowInfo.totalPrincipalClaimed += principalAmount;

            uint256 daysPassed;
            daysPassed = (positionInfo.expiryTime - positionInfo.openTime);

            uint256 expectedInvestReturnAmount = (positionInfo.amount * positionInfo.investReturnRate * daysPassed) /
                        PRICE_PRECISION /
                        TIME_UNIT;

            uint256 investReturnAmount = positionInfo.amount - principalAmount + expectedInvestReturnAmount;

            if (epochCurrentInvestAmount[epoch] < investReturnAmount) {
                if(epochCurrentInvestAmount[epoch] > principalAmount){
                    userCapitalFlowInfo.totalExpectedInvestRewardAmount += epochCurrentInvestAmount[epoch] - principalAmount;
                }else{
                    temporaryTokenAmount = principalAmount - epochCurrentInvestAmount[epoch];
                }
                investReturnAmount = epochCurrentInvestAmount[epoch];
                epochCurrentInvestAmount[epoch] = 0;
            } else {
                unchecked {
                    epochCurrentInvestAmount[epoch] -= investReturnAmount;
                    userCapitalFlowInfo.totalExpectedInvestRewardAmount += expectedInvestReturnAmount;
                }
            }
            userCapitalFlowInfo.totalExpectedInvestReturnAmount += investReturnAmount;

            if (epochCurrentInvestAmount[epoch] == 0) {

                if(temporaryTokenAmount > 0){
                    temporaryTotalProperty = userCapitalFlowInfo.totalPrincipalClaimed + userGlobalInfo.totalReferrerReward + userCapitalFlowInfo.totalRecommendReward + userCapitalFlowInfo.totalExpectedInvestReturnAmount + userCapitalFlowInfo.totalConvertTokenAmount;

                    setAssetPackage(userGlobalInfo.totalPositionAmount, temporaryTotalProperty, temporaryTokenAmount, userCapitalFlowInfo);
                }

                epochStopLoss[epoch] = true;
                currentEpochs += 1;
                _refillStock(0);
                _refillStock(1);
                _refillStock(2);
                _refillStock(3);
            }

            payoutAmount += investReturnAmount;

            positionInfo.investReturnAmount = investReturnAmount;
        }else{
            temporaryTotalMatic = userCapitalFlowInfo.totalPrincipalClaimed + userGlobalInfo.totalReferrerReward + userCapitalFlowInfo.totalRecommendReward + userCapitalFlowInfo.totalExpectedInvestReturnAmount;
            temporaryTotalProperty = temporaryTotalMatic + userCapitalFlowInfo.totalConvertTokenAmount;

            if(userGlobalInfo.totalPositionAmount > temporaryTotalProperty){
                uint256 totalPrincipalAmount = userGlobalInfo.totalPositionAmount * PRINCIPAL_RATIO / PRICE_PRECISION;
                if(temporaryTotalMatic < totalPrincipalAmount){
                    uint256 totalPrincipalLoss = totalPrincipalAmount - temporaryTotalMatic;
                    if(totalPrincipalLoss < principalAmount){
                        totalLosePrincipal += principalAmount - totalPrincipalLoss;
                        principalAmount = totalPrincipalLoss;
                    }
                    payoutAmount += principalAmount;
                    userCapitalFlowInfo.totalPrincipalClaimed += principalAmount;
                }
                temporaryTokenAmount = positionInfo.amount - payoutAmount;
                temporaryTotalProperty += payoutAmount;
                setAssetPackage(userGlobalInfo.totalPositionAmount, temporaryTotalProperty, temporaryTokenAmount, userCapitalFlowInfo);
            }
        }

        userRoundInfo.totalWithdrawnAmount += payoutAmount;
        unchecked {
            epochCurrentPrincipalAmount[epoch] -= principalAmount;
        }

        positionInfo.withdrawnAmount = payoutAmount;
        positionInfo.removalTime = block.timestamp;

        if(payoutAmount > 0){
            (bool success, ) = msg.sender.call{value: payoutAmount}("");
            require(success, "Transfer failed.");
        }

        emit PositionClosed(msg.sender, ledgerType, epoch, positionIndex, payoutAmount);
    }

    function setAssetPackage(uint256 _otalPositionAmount, uint256 _temporaryTotalProperty, uint256 tokenAmount, UserCapitalFlowInfo storage userCapitalFlowInfo) private {
        if(_otalPositionAmount > _temporaryTotalProperty){
            uint256 totalTokenAmount = _otalPositionAmount - _temporaryTotalProperty;
            if(totalTokenAmount < tokenAmount){
                tokenAmount = totalTokenAmount;
            }
            userCapitalFlowInfo.totalConvertTokenAmount += tokenAmount;
            if(tokenAmount > 0){
                if(stopLossAmount < 900000000 * ACCURACY){
                    uint256 MBSAmount;
                    uint8 ratioNum;
                    if(stopLossAmount < 200000000 * ACCURACY){
                        ratioNum = 0;
                    }else if(stopLossAmount < 400000000 * ACCURACY){
                        ratioNum = 1;
                    }else if(stopLossAmount < 600000000 * ACCURACY){
                        ratioNum = 2;
                    }else if(stopLossAmount < 800000000 * ACCURACY){
                        ratioNum = 3;
                    }else{
                        ratioNum = 4;
                    }
                    MBSAmount = tokenAmount * tokenOutputRatio[ratioNum] / PRICE_PRECISION;
                    AssetPackage[msg.sender].push(AssetPackageInfo({
                        birthday: block.timestamp,
                        amount: MBSAmount,
                        release: MBSAmount / 300,
                        withdrawn: 0,
                        state: true
                    }));
                    stopLossAmount += tokenAmount;
                }
            }
        }

    }

    function _safeProcessSalesLevel(
        uint8 currentLevel,
        address user,
        uint256 currentSales,
        UserGlobalInfo storage userGlobalInfo
    ) internal returns (uint8) {
        uint8 newLevel = _getSalesToLevel(currentSales);
        if (newLevel > currentLevel) {
            userGlobalInfo.salesLevel = newLevel;
            emit SalesLevelUpdated(user, newLevel);
        } else {
            newLevel = currentLevel;
        }
        return newLevel;
    }

    function _distributeReferrerReward(uint256 amountValue, address user, uint256 referrerAmount) internal virtual {
        UserGlobalInfo storage userGlobalInfo = userGlobalInfos[user];
        UserGlobalInfo storage referrerGlobalInfo;
        uint256 positionAmount = amountValue;

        ReferrerSearch memory search;
        search.baseSalesLevel = 0;
        search.currentReferrer = userGlobalInfo.referrer;
        search.levelDiffAmount = referrerAmount;
        search.leftLevelDiffAmount = search.levelDiffAmount;
        search.levelDiffAmountPerLevel = search.levelDiffAmount / 12;
        search.currentUserTotalPosAmount = userGlobalInfo.totalPositionAmount + positionAmount;
        userGlobalInfo.totalPositionAmount = search.currentUserTotalPosAmount;
        search.currentUser = user;

        while (search.depth < MAX_SEARCH_DEPTH) {

            if (search.currentReferrer == address(0)) {
                break;
            }

            if (search.depth > 0) userGlobalInfo.reportedSales += positionAmount;

            search.currentUserSales = userGlobalInfo.sales;
            search.currentUserReportedSales = userGlobalInfo.reportedSales;

            referrerGlobalInfo = userGlobalInfos[search.currentReferrer];

            {
                search.currentReferrerSales = referrerGlobalInfo.sales;

                search.currentReferrerSales += positionAmount;

                if (search.currentUserReportedSales < search.currentUserSales) {

                    search.currentReferrerSales += search.currentUserSales - search.currentUserReportedSales;

                    userGlobalInfo.reportedSales = search.currentUserSales;
                }

                referrerGlobalInfo.sales = search.currentReferrerSales;
            }

            {

                search.currentUserSales += search.currentUserTotalPosAmount;

                search.currentReferrerMaxChildSales = referrerGlobalInfo.maxChildrenSales;
                if (search.currentReferrerMaxChildSales < search.currentUserSales) {

                    referrerGlobalInfo.maxChildrenSales = search.currentUserSales;
                    search.currentReferrerMaxChildSales = search.currentUserSales;
                }
            }

            search.currentReferrerLevel = _safeProcessSalesLevel(
                referrerGlobalInfo.salesLevel,
                search.currentReferrer,
                search.currentReferrerSales - search.currentReferrerMaxChildSales,
                referrerGlobalInfo
            );

            search.currentReferrerRoundsLength = userRoundsInfos[0][search.currentReferrer].length;
            if(search.currentReferrerRoundsLength > 0){
                search.currentReferrerNewEpoch = userRoundsInfos[0][search.currentReferrer][search.currentReferrerRoundsLength - 1].epoch;
                if (!search.levelDiffDone && search.currentReferrerRoundsLength > 0 && search.currentReferrerNewEpoch >= currentEpochs) {
                    if (search.currentReferrerLevel > search.baseSalesLevel) {

                        search.currentLevelDiff = search.currentReferrerLevel - search.baseSalesLevel;

                        search.baseSalesLevel = search.currentReferrerLevel;

                        search.currentReferrerAmount = search.currentLevelDiff * search.levelDiffAmountPerLevel;

                        if (search.currentReferrerAmount + PRICE_PRECISION > search.leftLevelDiffAmount) {
                            search.currentReferrerAmount = search.leftLevelDiffAmount;
                        }

                        referrerGlobalInfo.totalReferrerReward += search.currentReferrerAmount;
                        emit ReferrerRewardAdded(search.currentReferrer, search.currentReferrerAmount, 0);

                        unchecked {
                            search.leftLevelDiffAmount -= search.currentReferrerAmount;
                        }

                        if (search.leftLevelDiffAmount == 0) {
                            search.levelDiffDone = true;
                        }
                    }
                }
            }

            search.currentUser = search.currentReferrer;
            search.currentReferrer = referrerGlobalInfo.referrer;

            userGlobalInfo = referrerGlobalInfo;
            search.currentUserTotalPosAmount = userGlobalInfo.totalPositionAmount;

            unchecked {
                search.depth += 1;
            }
        }
    }

    function _getSalesToLevel(uint256 amount) internal view virtual returns (uint8) {
        /* istanbul ignore else  */
        if (amount < levelSales[0]) {
            return 0;
        } else if (amount < levelSales[1]) {
            return 1;
        } else if (amount < levelSales[2]) {
            return 2;
        } else if (amount < levelSales[3]) {
            return 3;
        } else if (amount < levelSales[4]) {
            return 4;
        } else if (amount < levelSales[5]) {
            return 5;
        } else if (amount < levelSales[6]) {
            return 6;
        } else if (amount < levelSales[7]) {
            return 8;
        } else if (amount < levelSales[8]) {
            return 10;
        }
        return 12;
    }

    function getWithdrawalAmount(
        address Addr
    ) external view returns (uint256){
        AssetPackageInfo[] memory assetPackageArr = AssetPackage[Addr];
        uint256 amount;
        if(assetPackageArr.length > 0){
            for(uint256 i = 0; i < assetPackageArr.length; i++){
                AssetPackageInfo memory ap = assetPackageArr[i];
                if(ap.withdrawn < ap.amount){
                    uint256 dayPassed = (block.timestamp - ap.birthday) / TIME_UNIT;
                    uint256 reward = dayPassed * ap.release;
                    if ((reward + ap.withdrawn) > ap.amount){
                        reward = ap.amount - ap.withdrawn;
                    }
                    amount += reward;
                }
            }
        }
        return (amount);
    }

    function withdrawalMBS() external {
        AssetPackageInfo[] storage assetPackageArr = AssetPackage[msg.sender];
        uint256 amount;
        if(assetPackageArr.length > 0){
            for(uint256 i = 0; i < assetPackageArr.length; i++){
                AssetPackageInfo storage ap = assetPackageArr[i];
                if(ap.withdrawn < ap.amount){
                    uint256 dayPassed = (block.timestamp - ap.birthday) / TIME_UNIT;
                    uint256 reward = dayPassed * ap.release;
                    if ((reward + ap.withdrawn) > ap.amount){
                        reward = ap.amount - ap.withdrawn;
                        ap.state = false;
                    }
                    ap.birthday += dayPassed * TIME_UNIT;
                    amount += reward;
                    ap.withdrawn += reward;
                }
            }
        }
        if(amount > 0){
            IERC20EX(tokenAddress)._mint(msg.sender, amount);
        }
    }

    function addLiquitidyWithId(
        uint256 tokenAmount,
        uint256 maticAmount
    ) internal {
        (uint amount0, uint amount1) = tokenAddress > maticAddress
            ? (maticAmount, tokenAmount)
            : (tokenAmount, maticAmount);
        positionManager.increaseLiquidity{value: maticAmount}(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );
        positionManager.refundETH();
    }

    function buyBurn(
        uint256 amountIn
    ) internal {
        router.exactInputSingle{value: amountIn}(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: maticAddress,
                tokenOut: tokenAddress,
                fee: defaultFee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function _tokenAllocation(IERC20 _ERC20, address _address, uint256 _amount) external {
        require(msg.sender == platformAddress, "Only platformAddress");
        _ERC20.transfer(_address, _amount);
    }

    function withdrawEth(address to, uint256 value) external {
        require(msg.sender == platformAddress, "Only platformAddress");
        payable(to).transfer(value);
    }

    receive() external payable {}
}
