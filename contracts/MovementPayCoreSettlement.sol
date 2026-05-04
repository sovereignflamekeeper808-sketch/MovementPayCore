// SPDX-License-Identifier: PROPRIETARY
// 1CMC RLRJ — Movement Pay Core Settlement Engine
// Copyright (c) 2026 Robert Lee Russell Jr. All rights reserved.
//
// This contract is the primary settlement engine for the 1CMC RLRJ
// Sovereign Ecosystem. It processes USDT-denominated transactions
// initiated through Movement Lens biometric authentication and
// cleared through BitcoinUnlimited protocol layer.

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IMovementPayCore.sol";

contract MovementPayCoreSettlement is
    IMovementPayCore,
    ReentrancyGuard,
    Pausable,
    AccessControl
{
    using SafeERC20 for IERC20;

    bytes32 public constant FOUNDER_ROLE = keccak256("FOUNDER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant DISPUTE_RESOLVER_ROLE = keccak256("DISPUTE_RESOLVER_ROLE");

    IERC20 public immutable usdt;
    address public treasury;
    uint256 public feeBasisPoints;
    uint256 public constant MAX_FEE_BPS = 500;
    uint256 public constant MIN_SETTLEMENT_AMOUNT = 1e6;
    uint256 public constant MAX_SETTLEMENT_AMOUNT = 1e12;
    uint256 public constant SETTLEMENT_EXPIRY = 24 hours;
    uint256 private _nonce;
    uint256 public totalVolumeSettled;
    uint256 public totalFeesCollected;
    uint256 public totalSettlements;

    mapping(bytes32 => Settlement) private _settlements;
    mapping(address => uint256) public activeSettlementCount;
    mapping(address => uint256) public userVolumeSettled;
    mapping(bytes32 => uint256) public biometricLastUsed;

    error InvalidAmount(uint256 amount);
    error InvalidAddress(address addr);
    error InvalidSettlement(bytes32 settlementId);
    error InvalidStatus(SettlementStatus current, SettlementStatus expected);
    error SettlementExpired(bytes32 settlementId);
    error BiometricReplayDetected(bytes32 biometricHash);
    error FeeTooHigh(uint256 requested, uint256 maximum);
    error SelfPaymentNotAllowed();

    constructor(
        address _usdt,
        address _treasury,
        uint256 _feeBasisPoints,
        address _founder

    function initiatePayment(
        address payee,
        uint256 amount,
        bytes32 biometricHash,
        string calldata chain
    )
        external
        override
        nonReentrant
        whenNotPaused
        returns (bytes32 settlementId)
    {
        if (payee == address(0)) revert InvalidAddress(payee);
        if (payee == msg.sender) revert SelfPaymentNotAllowed();
        if (amount < MIN_SETTLEMENT_AMOUNT || amount > MAX_SETTLEMENT_AMOUNT)
            revert InvalidAmount(amount);
        if (
            biometricHash != bytes32(0) &&
            block.timestamp - biometricLastUsed[biometricHash] < 5
        ) {
            revert BiometricReplayDetected(biometricHash);
        }
        biometricLastUsed[biometricHash] = block.timestamp;
        settlementId = keccak256(
            abi.encodePacked(
                msg.sender,
                payee,
                amount,
                block.timestamp,
                _nonce++
            )
        );
        uint256 fee = (amount * feeBasisPoints) / 10_000;
        _settlements[settlementId] = Settlement({
            settlementId: settlementId,
            payer: msg.sender,
            payee: payee,
            amount: amount,
            fee: fee,
            status: SettlementStatus.Escrowed,
            createdAt: block.timestamp,
            settledAt: 0,
            biometricHash: biometricHash,
            chain: chain
        });
        usdt.safeTransferFrom(msg.sender, address(this), amount);
        activeSettlementCount[msg.sender]++;
        totalSettlements++;
        emit PaymentInitiated(settlementId, msg.sender, payee, amount, biometricHash);
        emit FundsEscrowed(settlementId, amount, fee);
        return settlementId;
    }

    function confirmSettlement(bytes32 settlementId)
        external
        override
        nonReentrant
        whenNotPaused
        onlyRole(OPERATOR_ROLE)
    {
        Settlement storage settlement = _settlements[settlementId];
        if (settlement.payer == address(0)) revert InvalidSettlement(settlementId);
        if (settlement.status != SettlementStatus.Escrowed)
            revert InvalidStatus(settlement.status, SettlementStatus.Escrowed);
        if (block.timestamp > settlement.createdAt + SETTLEMENT_EXPIRY)
            revert SettlementExpired(settlementId);
        settlement.status = SettlementStatus.Settled;
        settlement.settledAt = block.timestamp;
        uint256 netAmount = settlement.amount - settlement.fee;
        usdt.safeTransfer(settlement.payee, netAmount);

    function refundSettlement(bytes32 settlementId)
        external
        override
        nonReentrant
    {
        Settlement storage settlement = _settlements[settlementId];
        if (settlement.payer == address(0)) revert InvalidSettlement(settlementId);
        if (settlement.status != SettlementStatus.Escrowed)
            revert InvalidStatus(settlement.status, SettlementStatus.Escrowed);
        bool isOperator = hasRole(OPERATOR_ROLE, msg.sender);
        bool isPayerAfterExpiry = (
            msg.sender == settlement.payer &&
            block.timestamp > settlement.createdAt + SETTLEMENT_EXPIRY
        );
        if (!isOperator && !isPayerAfterExpiry) {
            revert InvalidSettlement(settlementId);
        }
        settlement.status = SettlementStatus.Refunded;
        settlement.settledAt = block.timestamp;
        usdt.safeTransfer(settlement.payer, settlement.amount);
        activeSettlementCount[settlement.payer]--;
        emit SettlementRefunded(settlementId, settlement.payer, settlement.amount);
    }

    function raiseDispute(bytes32 settlementId, string calldata reason)
        external
        override

    function resolveDispute(bytes32 settlementId, bool settleToPayee)
        external
        nonReentrant
        onlyRole(DISPUTE_RESOLVER_ROLE)
    {
        Settlement storage settlement = _settlements[settlementId];
        if (settlement.payer == address(0)) revert InvalidSettlement(settlementId);
        if (settlement.status != SettlementStatus.Disputed)
            revert InvalidStatus(settlement.status, SettlementStatus.Disputed);
        if (settleToPayee) {
            settlement.status = SettlementStatus.Settled;
            settlement.settledAt = block.timestamp;
            uint256 netAmount = settlement.amount - settlement.fee;
            usdt.safeTransfer(settlement.payee, netAmount);
            if (settlement.fee > 0) {
                usdt.safeTransfer(treasury, settlement.fee);
                totalFeesCollected += settlement.fee;
            }
            totalVolumeSettled += settlement.amount;
            emit SettlementConfirmed(settlementId, block.timestamp);
        } else {
            settlement.status = SettlementStatus.Refunded;
            settlement.settledAt = block.timestamp;
            usdt.safeTransfer(settlement.payer, settlement.amount);
            emit SettlementRefunded(settlementId, settlement.payer, settlement.amount);
        }
        activeSettlementCount[settlement.payer]--;
    }

    function batchConfirmSettlements(bytes32[] calldata settlementIds)
        external
        nonReentrant
        whenNotPaused
        onlyRole(OPERATOR_ROLE)
    {
        for (uint256 i = 0; i < settlementIds.length; i++) {
            Settlement storage settlement = _settlements[settlementIds[i]];
            if (
                settlement.payer == address(0) ||
                settlement.status != SettlementStatus.Escrowed ||
                block.timestamp > settlement.createdAt + SETTLEMENT_EXPIRY
            ) {
                continue;
            }
            settlement.status = SettlementStatus.Settled;
            settlement.settledAt = block.timestamp;
            uint256 netAmount = settlement.amount - sett

    function getSettlement(bytes32 settlementId)
        external
        view
        override
        returns (Settlement memory)
    {
        return _settlements[settlementId];
    }

    function calculateFee(uint256 amount)
        external
        view
        override
        returns (uint256)
    {
        return (amount * feeBasisPoints) / 10_000;
    }

    function isExpired(bytes32 settlementId)
        external
        view
        override
        returns (bool)
    {
        Settlement storage settlement = _settlements[settlementId];
        return block.timestamp > settlement.createdAt + SETTLEMENT_EXPIRY;
    }

    function escrowBalance()
        external
        view
        override
        returns (uint256)
    {
        return usdt.balanceOf(address(this));
    }

    function setFeeBasisPoints(uint256 newFeeBps)
        external
        onlyRole(FOUNDER_ROLE)
    {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh(newFeeBps);
        uint256 oldFee = feeBasisPoints;
        feeBasisPoints = newFeeBps;
        emit FeeUpdated(oldFee, newFeeBps);
    }

    function setTreasury(address newTreasury)
        external
        onlyRole(FOUNDER_ROLE)
    {
        if (newTreasury == address(0)) revert InvalidAddress(newTreasury);
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    function pause() external onlyRole(FOUNDER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(FOUNDER_ROLE) {
        _unpause();
    }

    function emergencyWithdraw(address token, uint256 amount)
        external
        nonReentrant
        onlyRole(FOUNDER_ROLE)
    {
        require(paused(), "Must be paused");
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}lement.fee;
            usdt.safeTransfer(settlement.payee, netAmount);
            if (settlement.fee > 0) {
                usdt.safeTransfer(treasury, settlement.fee);
                totalFeesCollected += settlement.fee;
            }
            activeSettlementCount[settlement.payer]--;
            totalVolumeSettled += settlement.amount;
            emit SettlementConfirmed(settlementIds[i], block.timestamp);
        }
    }
    {
        Settlement storage settlement = _settlements[settlementId];
        if (settlement.payer == address(0)) revert InvalidSettlement(settlementId);
        if (settlement.status != SettlementStatus.Escrowed)
            revert InvalidStatus(settlement.status, SettlementStatus.Escrowed);
        if (msg.sender != settlement.payer && msg.sender != settlement.payee)
            revert InvalidSettlement(settlementId);
        settlement.status = SettlementStatus.Disputed;
        emit DisputeRaised(settlementId, msg.sender, reason);
    }
        if (settlement.fee > 0) {
            usdt.safeTransfer(treasury, settlement.fee);
            totalFeesCollected += settlement.fee;
        }
        activeSettlementCount[settlement.payer]--;
        totalVolumeSettled += settlement.amount;
        userVolumeSettled[settlement.payer] += settlement.amount;
        userVolumeSettled[settlement.payee] += settlement.amount;
        emit SettlementConfirmed(settlementId, block.timestamp);
    }
    ) {
        if (_usdt == address(0)) revert InvalidAddress(_usdt);
        if (_treasury == address(0)) revert InvalidAddress(_treasury);
        if (_founder == address(0)) revert InvalidAddress(_founder);
        if (_feeBasisPoints > MAX_FEE_BPS) revert FeeTooHigh(_feeBasisPoints, MAX_FEE_BPS);
        usdt = IERC20(_usdt);
        treasury = _treasury;
        feeBasisPoints = _feeBasisPoints;
        _grantRole(DEFAULT_ADMIN_ROLE, _founder);
        _grantRole(FOUNDER_ROLE, _founder);
        _grantRole(OPERATOR_ROLE, _founder);
        _grantRole(DISPUTE_RESOLVER_ROLE, _founder);
    }
