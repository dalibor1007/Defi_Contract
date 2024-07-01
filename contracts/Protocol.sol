// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol';
import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Metadata.sol";
import "./common/Context.sol";
import "./tokens/ERC20.sol";
import "./tokens/ERC20Burnable.sol";
import "./common/Ownable.sol";
import "./WARRENToken.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library Constants {

  uint8 public constant BONDS_LIMIT = 100;
  uint256 public constant MIN_BOND_ETH = 1 ether;
  uint256 public constant MIN_BOND_TOKENS = 1 ether;

  uint256 public constant STAKING_REWARD_PERCENT = 200; 
  uint256 public constant STAKING_REWARD_LIMIT_PERCENT = 17500; 

  uint256 constant public PERCENTS_DIVIDER = 10000;

  uint256 public constant GLOBAL_LIQUIDITY_BONUS_STEP_ETH = 25 ether;
  uint256 public constant GLOBAL_LIQUIDITY_BONUS_STEP_PERCENT = 10; 
  uint256 public constant GLOBAL_LIQUIDITY_BONUS_LIMIT_PERCENT = 10000; 

  uint256 public constant USER_HOLD_BONUS_STEP = 1 days;
  uint256 public constant USER_HOLD_BONUS_STEP_PERCENT = 5; 
  uint256 public constant USER_HOLD_BONUS_LIMIT_PERCENT = 200; 

  uint256 public constant LIQUIDITY_BONUS_STEP_ETH = 1 ether;
  uint256 public constant LIQUIDITY_BONUS_STEP_PERCENT = 10; 
  uint256 public constant LIQUIDITY_BONUS_LIMIT_PERCENT = 200; 

}

library Models {

  struct User {
    address upline;//0
    uint8 refLevel;
    uint8 bondsNumber;//2
    uint256 balance;
    uint256 totalInvested;//4
    uint256 liquidityCreated;
    uint256 totalRefReward;//6
    uint256 totalWithdrawn;
    uint256 refTurnover;//8
    uint256 lastActionTime;
    address[] referrals;//10
    uint256[10] refs;
    uint256[10] refsNumber;
    uint256 totalSold; //13
    uint256 totalRebonded;//14
    uint256 totalClaimed;//15
  }

  struct Bond {
    uint256 amount;
    uint256 creationTime;

    uint256 freezePeriod;
    uint256 profitPercent;

    
    uint256 stakeAmount;
    uint256 stakeTime;
    uint256 collectedTime;
    uint256 collectedReward;
    uint256 stakingRewardLimit;

    bool isClosed;
  }

}

library Events {

  event NewBond(
    address indexed userAddress,
    uint8 indexed bondType,
    uint8 indexed bondIndex,
    uint256 amount,
    uint256 tokensAmount,
    bool isRebond,
    uint256 time
  );

  event ReBond(
    address indexed userAddress,
    uint8 indexed bondIndex,
    uint256 amount,
    uint256 tokensAmount,
    uint256 time
  );

  event StakeBond(
    address indexed userAddress,
    uint8 indexed bondIndex,
    uint256 amountToken,
    uint256 amountETH,
    uint256 time
  );

  event Transfer(
    address indexed userAddress,
    uint8 indexed bondIndex,
    uint256 amountToken,
    uint256 time
  );

  event Claim(
    address indexed userAddress,
    uint256 tokensAmount,
    uint256 time
  );

  event Sell(
    address indexed userAddress,
    uint256 tokensAmount,
    uint256 ethAmount,
    uint256 time
  );

  event NewUser(
    address indexed userAddress,
    address indexed upline,
    uint256 time
  );

  event RefPayout(
    address indexed investor,
    address indexed upline,
    uint256 indexed level,
    uint256 amount,
    uint256 time
  );

  event LiquidityAdded(
    uint256 amountToken,
    uint256 amountETH,
    uint256 liquidity,
    uint256 time
  );

}

contract WARRENProtocol is Ownable {
  using SafeERC20 for IERC20;
  mapping(address => Models.User) public users;
  mapping(address => mapping(uint8 => Models.Bond)) public bonds;


  address public immutable TOKEN_ADDRESS;
  address public immutable LP_TOKEN_ADDRESS;
  address public immutable UNISWAP_ROUTER_ADDRESS;
  address public immutable DEFAULT_UPLINE;
  IERC20 public immutable DEFAULT_TOKEN;
  uint256 public immutable DEFAULT_TOKENS_PER_ETH;

  uint256[] public REFERRAL_LEVELS_PERCENTS = [250, 350, 450, 550, 700, 800, 900, 1000];
  uint256[] public REFERRAL_LEVELS_MILESTONES = [
    0, 
    5 ether, 
    15 ether, 
    50 ether, 
    100 ether, 
    250 ether, 
    750 ether, 
    1500 ether
  ];
  uint8 constant public REFERRAL_DEPTH = 10;
  uint8 constant public REFERRAL_TURNOVER_DEPTH = 5;

  uint256 private PRICE_BALANCER_PERCENT = 110;

  uint256[5] public BOND_FREEZE_PERIODS = [
     30 days,
     20 days,
     10 days,
      5 days,
    100 days
  ];
  uint256[5] public BOND_FREEZE_PERCENTS = [
    3000, 
    2000, 
    1000, 
     500, 
       0  
  ];
  bool[5] public BOND_ACTIVATIONS = [
    true,
    false,
    false,
    false,
    false
  ];

  constructor(
    address uniswapRouterAddress,
    address WARRENTokenAddress,
    address lpTokenAddress,
    address defaultUpline,
    address defaultToken,
    uint256 defaultTokensPerETH
  ) {
    UNISWAP_ROUTER_ADDRESS = uniswapRouterAddress;
    TOKEN_ADDRESS = WARRENTokenAddress;
    LP_TOKEN_ADDRESS = lpTokenAddress;
    DEFAULT_UPLINE = defaultUpline;
    DEFAULT_TOKEN = IERC20(defaultToken);
    DEFAULT_TOKENS_PER_ETH = defaultTokensPerETH;
  }

  function buy(address upline, uint8 bondType, uint256 amount) external {
    require(bondType < 4 && BOND_ACTIVATIONS[bondType], "Buy: invalid bond type");
    require(users[msg.sender].bondsNumber < Constants.BONDS_LIMIT, "Buy: you have reached bonds limit");
    require(amount >= Constants.MIN_BOND_ETH, "Buy: min buy amount is 1 LP");
    
    DEFAULT_TOKEN.safeTransferFrom(msg.sender, address(this), amount);

    bool isNewUser = false;
    Models.User storage user = users[msg.sender];
    if (user.upline == address(0)) {
      isNewUser = true;
      if (upline == address(0) || upline == msg.sender || users[upline].bondsNumber == 0) {
        upline = DEFAULT_UPLINE;
      }
      user.upline = upline;

      if (upline != DEFAULT_UPLINE) {
        users[upline].referrals.push(msg.sender);
      }

      emit Events.NewUser(
        msg.sender, upline, block.timestamp
      );
    }

    uint256 refReward = distributeRefPayout(user, amount, isNewUser);
    uint256 adminFee = amount / 10;
    DEFAULT_TOKEN.safeTransfer(owner(), adminFee);

    newBond(msg.sender, bondType, amount, amount - adminFee - refReward);
  }

  function distributeRefPayout(
    Models.User storage user,
    uint256 ethAmount,
    bool isNewUser
  ) private returns (uint256 refReward) {
    if (user.upline == address(0)) {
      return 0;
    }

    bool[] memory distributedLevels = new bool[](REFERRAL_LEVELS_PERCENTS.length);

    address current = msg.sender;
    address upline = user.upline;
    uint8 maxRefLevel = 0;
    for (uint256 i = 0; i < REFERRAL_DEPTH; i++) {
      if (upline == address(0)) {
        break;
      }

      uint256 refPercent = 0;
      if (i == 0) {
        refPercent = REFERRAL_LEVELS_PERCENTS[users[upline].refLevel];

        maxRefLevel = users[upline].refLevel;
        for (uint8 j = users[upline].refLevel; j >= 0; j--) {
          distributedLevels[j] = true;

          if (j == 0) {
            break;
          }
        }
      } else if (users[upline].refLevel > maxRefLevel && !distributedLevels[users[upline].refLevel]) {
        refPercent =
          REFERRAL_LEVELS_PERCENTS[users[upline].refLevel] - REFERRAL_LEVELS_PERCENTS[maxRefLevel];

        maxRefLevel = users[upline].refLevel;
        for (uint8 j = users[upline].refLevel; j >= 0; j--) {
          distributedLevels[j] = true;

          if (j == 0) {
            break;
          }
        }
      }

      uint256 amount = ethAmount * refPercent / Constants.PERCENTS_DIVIDER;
      if (amount > 0) {
        DEFAULT_TOKEN.safeTransfer(upline, amount); 
        users[upline].totalRefReward+= amount;
        refReward+= amount;

        emit Events.RefPayout(
          msg.sender, upline, i, amount, block.timestamp
        );
      }

      users[upline].refs[i]++;
      if (isNewUser) {
        users[upline].refsNumber[i]++;
      }

      current = upline;
      upline = users[upline].upline;
    }

    upline = user.upline;
    for (uint256 i = 0; i < REFERRAL_TURNOVER_DEPTH; i++) {
      if (upline == address(0)) {
        break;
      }

      updateReferralLevel(upline, ethAmount);

      upline = users[upline].upline;
    }

  }

  function updateReferralLevel(address _userAddress, uint256 _amount) private {
    users[_userAddress].refTurnover+= _amount;

    for (uint8 level = uint8(REFERRAL_LEVELS_MILESTONES.length - 1); level > 0; level--) {
      if (users[_userAddress].refTurnover >= REFERRAL_LEVELS_MILESTONES[level]*DEFAULT_TOKENS_PER_ETH) {
        users[_userAddress].refLevel = level;

        break;
      }
    }
  }

  function newBond(
    address userAddr,
    uint8 bondType,
    uint256 bondAmount,
    uint256 liquidityAmount
  ) private returns (uint8) {
    Models.User storage user = users[userAddr];
    Models.Bond storage bond  = bonds[userAddr][user.bondsNumber];

    bond.freezePeriod = BOND_FREEZE_PERIODS[bondType];
    bond.profitPercent = BOND_FREEZE_PERCENTS[bondType];
    bond.amount = bondAmount;
    bond.creationTime = block.timestamp;

    if (user.bondsNumber == 0) { 
      user.lastActionTime = block.timestamp;
    }

    user.bondsNumber++;
    user.totalInvested+= bondAmount;

    uint256 tokensAmount = 0;
    if (liquidityAmount > 0) {
      tokensAmount = getTokensAmount(liquidityAmount);
      WARRENToken(TOKEN_ADDRESS).mint(address(this), tokensAmount);
      WARRENToken(TOKEN_ADDRESS).increaseAllowance(UNISWAP_ROUTER_ADDRESS, tokensAmount);
      DEFAULT_TOKEN.approve(UNISWAP_ROUTER_ADDRESS, liquidityAmount);
      
      (uint256 amountToken, uint256 amountETH, uint256 liquidity) =
        IUniswapV2Router01(UNISWAP_ROUTER_ADDRESS).addLiquidity(
          TOKEN_ADDRESS,
          address(DEFAULT_TOKEN),
          tokensAmount,
          liquidityAmount,
          0,
          0,
          address(this),
          block.timestamp
        );

      emit Events.LiquidityAdded(
        amountToken, amountETH, liquidity, block.timestamp
      );
    }

    emit Events.NewBond(
      userAddr, bondType, user.bondsNumber - 1, bondAmount, tokensAmount, liquidityAmount == 0, block.timestamp
    );

    return user.bondsNumber - 1;
  }

  function stake(uint8 bondIdx) external {
    require(bondIdx < users[msg.sender].bondsNumber, "Stake: invalid bond index");
    require(!bonds[msg.sender][bondIdx].isClosed, "Stake: this bond already closed");
    require(bonds[msg.sender][bondIdx].stakeTime == 0, "Stake: this bond was already staked");

    Models.User storage user = users[msg.sender];
    Models.Bond storage bond  = bonds[msg.sender][bondIdx];

    uint256 defaultTokenAmount = bond.amount * (Constants.PERCENTS_DIVIDER + bond.profitPercent) / Constants.PERCENTS_DIVIDER;
    DEFAULT_TOKEN.safeTransferFrom(msg.sender, address(this), defaultTokenAmount);

    uint256 refReward = distributeRefPayout(user, defaultTokenAmount, false);
    uint256 adminFee = defaultTokenAmount / 10;
    DEFAULT_TOKEN.safeTransfer(owner(), adminFee);

    uint256 tokensAmount = getTokensAmount(defaultTokenAmount);

    defaultTokenAmount = defaultTokenAmount - refReward - adminFee;
    uint256 liquidityTokensAmount = getTokensAmount(defaultTokenAmount);

    WARRENToken(TOKEN_ADDRESS).mint(address(this), liquidityTokensAmount);
    WARRENToken(TOKEN_ADDRESS).increaseAllowance(UNISWAP_ROUTER_ADDRESS, liquidityTokensAmount);
    DEFAULT_TOKEN.approve(UNISWAP_ROUTER_ADDRESS, defaultTokenAmount);

    (uint256 amountToken, uint256 amountETH, uint256 liquidity) = IUniswapV2Router01(UNISWAP_ROUTER_ADDRESS).addLiquidity(
        TOKEN_ADDRESS,
        address(DEFAULT_TOKEN),
        liquidityTokensAmount,
        defaultTokenAmount,
        0,
        0,
        address(this),
        block.timestamp
    );

    user.liquidityCreated += defaultTokenAmount;

    emit Events.LiquidityAdded(
      amountToken, amountETH, liquidity, block.timestamp
    );

    bond.stakeAmount = 2 * tokensAmount;
    bond.stakeTime = block.timestamp;
    bond.collectedTime = block.timestamp;
    bond.stakingRewardLimit = bond.stakeAmount * Constants.STAKING_REWARD_LIMIT_PERCENT / Constants.PERCENTS_DIVIDER;

    emit Events.StakeBond(
      msg.sender, bondIdx, tokensAmount, defaultTokenAmount, block.timestamp
    );
  }

  
  function transfer(uint8 bondIdx) external {
    Models.Bond storage bond = bonds[msg.sender][bondIdx];

    require(bondIdx < users[msg.sender].bondsNumber, "Transfer: invalid bond index");
    require(!bond.isClosed, "Transfer: the bond is already closed");
    require(bond.stakeTime == 0, "Transfer: the bond is staked");
    require(
      block.timestamp >= bond.creationTime + bond.freezePeriod,
      "Transfer: this bond is still freeze"
    );

    uint256 tokensAmount =
      getTokensAmount(bond.amount * (Constants.PERCENTS_DIVIDER + bond.profitPercent) / Constants.PERCENTS_DIVIDER);

    users[msg.sender].balance+= tokensAmount;
    bond.isClosed = true;

    emit Events.Transfer(
      msg.sender, bondIdx, tokensAmount, block.timestamp
    );
  }

  function claim(uint256 tokensAmount) external {
    require(userBalance(msg.sender) >= tokensAmount, "Claim: insufficient balance");

    collect(msg.sender);
    Models.User storage user = users[msg.sender];
    require(user.balance >= tokensAmount, "Claim: insufficient balance");

    user.balance-= tokensAmount;
    user.totalClaimed += tokensAmount;
    user.lastActionTime = block.timestamp;
    WARRENToken(TOKEN_ADDRESS).mint(msg.sender, tokensAmount);

    emit Events.Claim(
      msg.sender, tokensAmount, block.timestamp
    );
  }

  
  function rebond(uint256 tokensAmount) external {
    require(users[msg.sender].bondsNumber < Constants.BONDS_LIMIT, "Rebond: you have reached bonds limit");
    require(tokensAmount >= Constants.MIN_BOND_TOKENS, "Rebond: min rebond amount is 1 WARREN");
    require(userBalance(msg.sender) >= tokensAmount, "Rebond: insufficient balance");

    collect(msg.sender);
    Models.User storage user = users[msg.sender];
    require(user.balance >= tokensAmount, "Rebond: insufficient balance");

    user.balance-= tokensAmount;
    user.totalRebonded += tokensAmount;

    uint256 ethAmount = getETHAmount(tokensAmount);
    uint8 bondIdx = newBond(msg.sender, 0, ethAmount, 0);

    emit Events.ReBond(
      msg.sender, bondIdx, ethAmount, tokensAmount, block.timestamp
    );
  }
  
  function sell(uint256 tokensAmount) external {
    require(userBalance(msg.sender) >= tokensAmount, "Sell: insufficient balance");

    collect(msg.sender);
    Models.User storage user = users[msg.sender];
    require(user.balance >= tokensAmount, "Sell: insufficient balance");

    user.balance-= tokensAmount;
    user.lastActionTime = block.timestamp;
    user.totalSold += tokensAmount;

    address[] memory path = new address[](2);
    path[0] = TOKEN_ADDRESS;
    path[1] = address(DEFAULT_TOKEN);

    WARRENToken(TOKEN_ADDRESS).mint(address(this), tokensAmount);
    WARRENToken(TOKEN_ADDRESS).increaseAllowance(UNISWAP_ROUTER_ADDRESS, tokensAmount);

    uint256[] memory amounts = IUniswapV2Router01(UNISWAP_ROUTER_ADDRESS).swapExactTokensForTokens(
      tokensAmount,
      0,
      path,
      msg.sender,
      block.timestamp
    );
    uint256 ethAmount = amounts[1];
    

    (uint256 ethReserved, ) = getTokenLiquidity();
    uint256 _contractLp = ERC20(LP_TOKEN_ADDRESS).balanceOf(address(this));
    uint256 liquidity = _contractLp
      * ethAmount
      * (Constants.PERCENTS_DIVIDER + PRICE_BALANCER_PERCENT)
      / Constants.PERCENTS_DIVIDER
      / ethReserved;

    if(liquidity >= _contractLp) liquidity = ((_contractLp * 9) / 10);

    ERC20(LP_TOKEN_ADDRESS).approve(
      UNISWAP_ROUTER_ADDRESS,
      liquidity
    );

    (, uint256 amountDEFAULT) = IUniswapV2Router01(UNISWAP_ROUTER_ADDRESS).removeLiquidity(
      TOKEN_ADDRESS,
      address(DEFAULT_TOKEN),
      liquidity,
      0,
      0,
      address(this),
      block.timestamp
    );

    path[0] = address(DEFAULT_TOKEN);
    path[1] = TOKEN_ADDRESS;
    DEFAULT_TOKEN.approve(UNISWAP_ROUTER_ADDRESS, amountDEFAULT);
    amounts = IUniswapV2Router01(UNISWAP_ROUTER_ADDRESS).swapExactTokensForTokens(
      amountDEFAULT,
      0,
      path,
      address(this),
      block.timestamp
    );
    
    emit Events.Sell(
      msg.sender, tokensAmount, ethAmount, block.timestamp
    );
  }

  function changePriceBalancerPercent(uint256 percent) external onlyOwner {
    require(percent >= 0 && percent <= 2500, "Invalid percent amount (0 - 2500: 0% - 25%)");

    PRICE_BALANCER_PERCENT = percent;
  }

  function influencerBond(address userAddr, uint256 tokensAmount) external onlyOwner {
    require(users[userAddr].bondsNumber < Constants.BONDS_LIMIT, "User have reached bonds limit");
    require(IERC20(TOKEN_ADDRESS).balanceOf(address(this)) >= tokensAmount, "Insufficient token balance");

    users[userAddr].balance+= tokensAmount * 5 / 100; 
    uint256 ethAmount = getETHAmount(tokensAmount * 95 / 100);
    uint8 bondIdx = newBond(userAddr, 4, ethAmount, 0);

    WARRENToken(TOKEN_ADDRESS).burn(tokensAmount);

    emit Events.NewBond(
      userAddr, 4, bondIdx, ethAmount, tokensAmount * 95 / 100, false, block.timestamp
    );
  }

  function collect(address userAddress) private {
    Models.User storage user = users[userAddress];

    uint8 bondsNumber = user.bondsNumber;
    for (uint8 i = 0; i < bondsNumber; i++) {
      if (bonds[userAddress][i].isClosed) {
        continue;
      }

      Models.Bond storage bond = bonds[userAddress][i];

      uint256 tokensAmount;
      if (bond.stakeTime == 0) { 
        if (block.timestamp >= bond.creationTime + bond.freezePeriod) { 
          tokensAmount = getTokensAmount(bond.amount * (Constants.PERCENTS_DIVIDER + bond.profitPercent) / Constants.PERCENTS_DIVIDER);

          user.balance+= tokensAmount;
          bond.isClosed = true;
        }
      } else { 
        tokensAmount = bond.stakeAmount
          * (block.timestamp - bond.collectedTime)
          * (
                Constants.STAKING_REWARD_PERCENT
              + getLiquidityGlobalBonusPercent()
              + getHoldBonusPercent(userAddress)
              + getLiquidityBonusPercent(userAddress)
            )
          / Constants.PERCENTS_DIVIDER
          / 1 days;

        if (bond.collectedReward + tokensAmount >= bond.stakingRewardLimit) {
          tokensAmount = bond.stakingRewardLimit - bond.collectedReward;
          bond.collectedReward = bond.stakingRewardLimit;
          bond.isClosed = true;
        } else {
          bond.collectedReward+= tokensAmount;
        }

        user.balance+= tokensAmount;
        bond.collectedTime = block.timestamp;
      }
    }
  }

  function userBalance(address userAddress) public view returns (uint256 balance) {
    Models.User memory user = users[userAddress];

    uint8 bondsNumber = user.bondsNumber;
    for (uint8 i = 0; i < bondsNumber; i++) {
      if (bonds[userAddress][i].isClosed) {
        continue;
      }

      Models.Bond memory bond = bonds[userAddress][i];

      uint256 tokensAmount;
      if (bond.stakeTime == 0) { 
        if (block.timestamp >= bond.creationTime + bond.freezePeriod) { 
          tokensAmount = getTokensAmount(bond.amount * (Constants.PERCENTS_DIVIDER + bond.profitPercent) / Constants.PERCENTS_DIVIDER);

          balance+= tokensAmount;
        }
      } else { 
        tokensAmount = bond.stakeAmount
          * (block.timestamp - bond.collectedTime)
          * (
                Constants.STAKING_REWARD_PERCENT
              + getLiquidityGlobalBonusPercent()
              + getHoldBonusPercent(userAddress)
              + getLiquidityBonusPercent(userAddress)
            )
          / Constants.PERCENTS_DIVIDER
          / 1 days;

        if (bond.collectedReward + tokensAmount >= bond.stakingRewardLimit) {
          tokensAmount = bond.stakingRewardLimit - bond.collectedReward;
        }

        balance+= tokensAmount;
      }
    }

    balance+= user.balance;
  }

  function getETHAmount(uint256 tokensAmount) public view returns(uint256) {
    address _token0 = IUniswapV2Pair(LP_TOKEN_ADDRESS).token0();
    (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(LP_TOKEN_ADDRESS).getReserves();
    if(_token0 == address(DEFAULT_TOKEN)) {
      return tokensAmount * reserve0 / reserve1;
    } else {
      return tokensAmount * reserve1 / reserve0;
    }
    
  }

  function getTokensAmount(uint256 amount) public view returns(uint256) {
    address _token0 = IUniswapV2Pair(LP_TOKEN_ADDRESS).token0();
    (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(LP_TOKEN_ADDRESS).getReserves();
    if(_token0 == address(DEFAULT_TOKEN)) {
      return amount * reserve1 / reserve0;
    } else {
      return amount * reserve0 / reserve1;
    }
  }

  function getTokenLiquidity() public view returns (
    uint256 liquidityDEFAULT,
    uint256 liquidityERC20
  ) {
    (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(LP_TOKEN_ADDRESS).getReserves(); 
    (liquidityDEFAULT, liquidityERC20) = address(DEFAULT_TOKEN) < TOKEN_ADDRESS ? (reserve0, reserve1) : (reserve1, reserve0);
  }

  function getLiquidityGlobalBonusPercent() public view returns (uint256 bonusPercent) {
    (uint256 liquidityDEFAULT, ) = getTokenLiquidity();

    bonusPercent = liquidityDEFAULT
      * Constants.GLOBAL_LIQUIDITY_BONUS_STEP_PERCENT
      / (Constants.GLOBAL_LIQUIDITY_BONUS_STEP_ETH * DEFAULT_TOKENS_PER_ETH);

    if (bonusPercent > Constants.GLOBAL_LIQUIDITY_BONUS_LIMIT_PERCENT) {
      return Constants.GLOBAL_LIQUIDITY_BONUS_LIMIT_PERCENT;
    }
  }

  function getHoldBonusPercent(address userAddr) public view returns (uint256 bonusPercent) {
    if (users[userAddr].lastActionTime == 0) {
      return 0;
    }

    bonusPercent = (block.timestamp - users[userAddr].lastActionTime)
      / Constants.USER_HOLD_BONUS_STEP
      * Constants.USER_HOLD_BONUS_STEP_PERCENT;

    if (bonusPercent > Constants.USER_HOLD_BONUS_LIMIT_PERCENT) {
      return Constants.USER_HOLD_BONUS_LIMIT_PERCENT;
    }
  }

  function getLiquidityBonusPercent(address userAddr) public view returns (uint256 bonusPercent) {
    bonusPercent = users[userAddr].liquidityCreated
      * Constants.LIQUIDITY_BONUS_STEP_PERCENT
      / (Constants.LIQUIDITY_BONUS_STEP_ETH * DEFAULT_TOKENS_PER_ETH);

    if (bonusPercent > Constants.LIQUIDITY_BONUS_LIMIT_PERCENT) {
      return Constants.LIQUIDITY_BONUS_LIMIT_PERCENT;
    }
  }

  function getUIData(address userAddr) external view returns (
    Models.User memory user,
    uint256 userTokensBalance,
    uint256 userHoldBonus,
    uint256 userLiquidityBonus,
    uint256 globalLiquidityBonus,
    bool[5] memory bondActivations,
    address[] memory userReferrals
  ) {
    user = users[userAddr];
    userTokensBalance = userBalance(userAddr);
    userHoldBonus = getHoldBonusPercent(userAddr);
    userLiquidityBonus = getLiquidityBonusPercent(userAddr);
    globalLiquidityBonus = getLiquidityGlobalBonusPercent();
    bondActivations = BOND_ACTIVATIONS;
    userReferrals = user.referrals;
  }

  function activateBondType(uint8 bondType) external onlyOwner {
    require(bondType > 0 && bondType < 4, "Invalid bond type");

    BOND_ACTIVATIONS[bondType] = true;
  }

  function deactivateBondType(uint8 bondType) external onlyOwner {
    require(bondType > 0 && bondType < 4, "Invalid bond type");

    BOND_ACTIVATIONS[bondType] = false; 
  }
}
