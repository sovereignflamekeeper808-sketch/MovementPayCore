// SPDX-License-Identifier: PROPRIETARY
// 1CMC RLRJ — Movement Pay Core Multi-Signature Treasury
// Copyright (c) 2026 Robert Lee Russell Jr. All rights reserved.

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MovementPayMultiSig is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Transaction {
        address token;
        address to;
        uint256 amount;
        uint256 confirmations;
        bool executed;
        uint256 createdAt;
        string description;
    }

    address[] public signers;
    uint256 public requiredConfirmations;
    uint256 public transactionCount;

    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => mapping(address => bool)) public confirmations;
    mapping(address => bool) public isSigner;

    event TransactionSubmitted(uint256 indexed txId, address indexed submitter, address token, address to, uint256 amount);
    event TransactionConfirmed(uint256 indexed txId, address indexed signer);
    event TransactionRevoked(uint256 indexed txId, address indexed signer);
    event TransactionExecuted(uint256 indexed txId);
    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event RequirementChanged(uint256 required);

    error NotSigner();
    error AlreadyConfirmed();
    error NotConfirmed();
    error AlreadyExecuted();
    error InsufficientConfirmations();
    error InvalidParameters();
    error TransactionExpired();

    modifier onlySigner() {
        if (!isSigner[msg.sender]) revert NotSigner();
        _;
    }

    modifier txExists(uint256 txId) {
        if (txId >= transactionCount) revert InvalidParameters();
        _;
    }

    modifier notExecuted(uint256 txId) {
        if (transactions[txId].executed) revert AlreadyExecuted();
        _;
    }

    constructor(address[] memory _signers, uint256 _required) {
        if (_signers.length < 2 || _required < 2 || _required > _signers.length)
            revert InvalidParameters();

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            if (signer == address(0) || isSigner[signer]) revert InvalidParameters();
            isSigner[signer] = true;
            signers.push(signer);
        }

        requiredConfirmations = _required;
    }

    function submitTransaction(
        address token,
        address to,
        uint256 amount,
        string calldata description
    ) external onlySigner returns (uint256 txId) {
        if (to == address(0) || amount == 0) revert InvalidParameters();

        txId = transactionCount++;
        transactions[txId] = Transaction({
            token: token,
            to: to,
            amount: amount,
            confirmations: 1,
            executed: false,
            createdAt: block.timestamp,
            description: description
        });

        confirmations[txId][msg.sender] = true;

        emit TransactionSubmitted(txId, msg.sender, token, to, amount);
        emit TransactionConfirmed(txId, msg.sender);

        return txId;
    }

    function confirmTransaction(uint256 txId)
        external
        onlySigner
        txExists(txId)
        notExecuted(txId)
    {
        if (confirmations[txId][msg.sender]) revert AlreadyConfirmed();

        confirmations[txId][msg.sender] = true;
        transactions[txId].confirmations++;

        emit TransactionConfirmed(txId, msg.sender);
    }

    function revokeConfirmation(uint256 txId)
        external
        onlySigner
        txExists(txId)
        notExecuted(txId)
    {
        if (!confirmations[txId][msg.sender]) revert NotConfirmed();

        confirmations[txId][msg.sender] = false;
        transactions[txId].confirmations--;

        emit TransactionRevoked(txId, msg.sender);
    }

    function executeTransaction(uint256 txId)
        external
        nonReentrant
        onlySigner
        txExists(txId)
        notExecuted(txId)
    {
        Transaction storage txn = transactions[txId];

        if (txn.confirmations < requiredConfirmations)
            revert InsufficientConfirmations();

        if (block.timestamp > txn.createdAt + 72 hours)
            revert TransactionExpired();

        txn.executed = true;

        IERC20(txn.token).safeTransfer(txn.to, txn.amount);

        emit TransactionExecuted(txId);
    }

    function getSigners() external view returns (address[] memory) {
        return signers;
    }

    function getTransaction(uint256 txId) external view returns (Transaction memory) {
        return transactions[txId];
    }

    function getConfirmationCount(uint256 txId) external view returns (uint256) {
        return transactions[txId].confirmations;
    }

    receive() external payable {}
}
