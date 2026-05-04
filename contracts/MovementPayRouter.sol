// SPDX-License-Identifier: PROPRIETARY
// 1CMC RLRJ - Sovereign Ecosystem | BitcoinUnlimited Cross-Chain Router
// Author: Robert Lee Russell Jr.
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MovementPayRouter is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ROUTER_ROLE = keccak256("ROUTER_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    IERC20 public immutable usdt;

    enum ChainPriority { None, Primary, Secondary }

    struct ChainConfig {
        uint256 chainId;
        string name;
        ChainPriority priority;
        bool active;
        uint256 totalRouted;
    }

    mapping(uint256 => ChainConfig) public chains;
    uint256[] public supportedChainIds;

    struct BridgeRequest {
        bytes32 requestId;
        address sender;
        uint256 amount;
        uint256 sourceChainId;
        uint256 destChainId;
        uint256 timestamp;
        bool completed;
    }

    mapping(bytes32 => BridgeRequest) public bridgeRequests;
    uint256 public bridgeNonce;
    uint256 public totalBridged;

    event ChainRegistered(uint256 indexed chainId, string name, ChainPriority priority);
    event ChainStatusUpdated(uint256 indexed chainId, bool active);
    event BridgeInitiated(bytes32 indexed requestId, address indexed sender, uint256 amount, uint256 sourceChainId, uint256 destChainId);
    event BridgeCompleted(bytes32 indexed requestId, uint256 amount);

    constructor(address _usdt) {
        require(_usdt != address(0), "MPR: zero USDT");
        usdt = IERC20(_usdt);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ROUTER_ROLE, msg.sender);
        _grantRole(BRIDGE_ROLE, msg.sender);
    }

    function registerChain(
        uint256 chainId,
        string calldata name,
        ChainPriority priority
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(chains[chainId].chainId == 0, "MPR: chain exists");
        require(priority != ChainPriority.None, "MPR: invalid priority");
        chains[chainId] = ChainConfig({
            chainId: chainId,
            name: name,
            priority: priority,
            active: true,
            totalRouted: 0
        });
        supportedChainIds.push(chainId);
        emit ChainRegistered(chainId, name, priority);
    }

    function setChainStatus(
        uint256 chainId,
        bool active
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(chains[chainId].chainId != 0, "MPR: unknown chain");
        chains[chainId].active = active;
        emit ChainStatusUpdated(chainId, active);
    }

    function initiateBridge(
        uint256 amount,
        uint256 destChainId
    ) external nonReentrant returns (bytes32 requestId) {
        require(amount > 0, "MPR: zero amount");
        require(chains[destChainId].active, "MPR: dest chain inactive");
        requestId = keccak256(
            abi.encodePacked(msg.sender, amount, destChainId, block.timestamp, bridgeNonce)
        );
        usdt.safeTransferFrom(msg.sender, address(this), amount);
        bridgeRequests[requestId] = BridgeRequest({
            requestId: requestId,
            sender: msg.sender,
            amount: amount,
            sourceChainId: block.chainid,
            destChainId: destChainId,
            timestamp: block.timestamp,
            completed: false
        });
        bridgeNonce++;
        emit BridgeInitiated(requestId, msg.sender, amount, block.chainid, destChainId);
    }

    function completeBridge(
        bytes32 requestId,
        address recipient
    ) external nonReentrant onlyRole(BRIDGE_ROLE) {
        BridgeRequest storage request = bridgeRequests[requestId];
        require(!request.completed, "MPR: already completed");
        require(request.amount > 0, "MPR: unknown request");
        request.completed = true;
        totalBridged += request.amount;
        chains[request.destChainId].totalRouted += request.amount;
        usdt.safeTransfer(recipient, request.amount);
        emit BridgeCompleted(requestId, request.amount);
    }

    function getSupportedChains() external view returns (uint256[] memory) {
        return supportedChainIds;
    }

    function getRouterBalance() external view returns (uint256) {
        return usdt.balanceOf(address(this));
    }
}
