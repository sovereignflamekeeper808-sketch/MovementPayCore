// SPDX-License-Identifier: PROPRIETARY
// 1CMC RLRJ - Mock USDT for Testnet Deployment
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDT
 * @notice Mock Tether token for testnet deployment and testing
 * @dev Mimics USDT with 6 decimals. NOT for production use.
 */
contract MockUSDT is ERC20 {
    constructor() ERC20("Tether USD (Mock)", "USDT") {
        // Mint 100M USDT to deployer for testing
        _mint(msg.sender, 100_000_000 * 10 ** decimals());
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Faucet - mint test USDT to any address
    function faucet(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
