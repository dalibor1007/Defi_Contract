// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol';
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Metadata.sol";
import "./common/Context.sol";
import "./common/Ownable.sol";
import "./tokens/ERC20.sol";
import "./tokens/ERC20Burnable.sol";
import "./WARRENToken.sol";


contract Fomo is Ownable {

  address public PULSEX_ROUTER_ADDRESS;
  address public LP_TOKEN_ADDRESS;
  address public mainContractAddress;

  constructor() {
  }

  function setMainContractAddress(address contractAddress) external onlyOwner {
    require(mainContractAddress == address(0), "Main contract address already configured");

    mainContractAddress = contractAddress;
  }

}
