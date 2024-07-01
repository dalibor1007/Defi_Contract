// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Metadata.sol";
import "./common/Context.sol";
import "./common/Ownable.sol";
import "./tokens/ERC20.sol";
import "./tokens/ERC20Burnable.sol";

contract WARRENToken is ERC20, ERC20Burnable, Ownable {

  address public PULSEX_ROUTER_ADDRESS;
  address public LP_TOKEN_ADDRESS;
  address public mainContractAddress;

  constructor() ERC20("WARREN", "WARREN") {
    _mint(msg.sender, 1_000_000 * 10 ** decimals()); //EDIT::KEEP OR REMOVE?
  }

  function setMainContractAddress(address contractAddress) external onlyOwner {
    require(mainContractAddress == address(0), "Main contract address already configured");

    mainContractAddress = contractAddress;
  }

  function mint(address to, uint256 amount) public {
    require(msg.sender == mainContractAddress, "Mint: only main contract can mint tokens");

    _mint(to, amount);
  }

  function setLPTokenAddress(address lpTokenAddress) external onlyOwner {
    require(LP_TOKEN_ADDRESS == address(0), "Owner: LP token address already configured");

    LP_TOKEN_ADDRESS = lpTokenAddress;
  }

  function setRouterAddress(address pulsexRouterAddress) external onlyOwner {
    require(PULSEX_ROUTER_ADDRESS == address(0), "Router address already configured");

    PULSEX_ROUTER_ADDRESS = pulsexRouterAddress;
  }

  function _beforeTokenTransfer(address from, address to, uint256 ) internal view override {
    if (LP_TOKEN_ADDRESS == address(0)) {
      return;
    }

    if (from == LP_TOKEN_ADDRESS || from == PULSEX_ROUTER_ADDRESS) {
      require(
           to == mainContractAddress 
        || to == PULSEX_ROUTER_ADDRESS 
        || to == LP_TOKEN_ADDRESS 
        || to == address(0), 
        "Transfer: only main contract can buy tokens"
      );
    }
  }

}
