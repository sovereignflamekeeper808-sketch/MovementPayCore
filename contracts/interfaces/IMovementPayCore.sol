// SPDX-License-Identifier: PROPRIETARY
// 1CMC RLRJ — Movement Pay Core Settlement Interface
// Copyright (c) 2026 Robert Lee Russell Jr. All rights reserved.

pragma solidity ^0.8.24;

/**
 * @title IMovementPayCore
 * @notice Interface for the Movement Pay Core Settlement Engine
 * @dev Defines the settlement lifecycle for USDT-denominated transactions
 *      within the 1CMC RLRJ Sovereign Ecosystem
 */
interface IMovementPayCore {

    // ──────────────────────────────────────────────
    //  Enums
    // ──────────────────────────────────────────────

    enum SettlementStatus {
        Pending,        // Payment initiated, awaiting escrow deposit
        Escrowed,       // Funds locked in escrow
        Confirmed,      // On-chain confirmation received
        Settled,        // Clearing complete, funds released
        Refunded,       // Transaction refunded to payer
        Disputed        // Under dispute resolution
    }

    // ──────────────────────────────────────────────
    //  Structs
    // ──────────────────────────────────────────────

    struct Settlement {
        bytes32 settlementId;       // Unique settlement identifier
        address payer;              // Address initiating payment
        address payee;              // Address receiving payment
        uint256 amount;             // Settlement amount (USDT, 6 decimals)
        uint256 fee;                // Protocol fee amount
        SettlementStatus status;    // Current settlement status
        uint256 createdAt;          // Block timestamp of creation
        uint256 settledAt;          // Block timestamp of settlement
        bytes32 biometricHash;      // Movement Lens biometric auth hash
        string chain;               // Source chain identifier
    }

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event PaymentInitiated(
        bytes32 indexed settlementId,
        address indexed payer,
        address indexed payee,
        uint256 amount,
        bytes32 biometricHash
    );

    event FundsEscrowed(
        bytes32 indexed settlementId,
        uint256 amount,
        uint256 fee
    );

    event SettlementConfirmed(
        bytes32 indexed settlementId,
        uint256 settledAt
    );

    event SettlementRefunded(
        bytes32 indexed settlementId,
        address indexed payer,
        uint256 amount
    );

    event DisputeRaised(
        bytes32 indexed settlementId,
        address indexed raisedBy,
        string reason
    );

    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    // ──────────────────────────────────────────────
    //  Core Functions
    // ──────────────────────────────────────────────

    /**
     * @notice Initiate a new payment settlement
     * @param payee Recipient address
     * @param amount USDT amount (6 decimals)
     * @param biometricHash Movement Lens biometric authentication hash
     * @param chain Source chain identifier
     * @return settlementId Unique identifier for the settlement
     */
    function initiatePayment(
        address payee,
        uint256 amount,
        bytes32 biometricHash,
        string calldata chain
    ) external returns (bytes32 settlementId);

    /**
     * @notice Confirm and finalize a settlement
     * @param settlementId The settlement to confirm
     */
    function confirmSettlement(bytes32 settlementId) external;

    /**
     * @notice Refund a pending or escrowed settlement
     * @param settlementId The settlement to refund
     */
    function refundSettlement(bytes32 settlementId) external;

    /**
     * @notice Raise a dispute on a settlement
     * @param settlementId The settlement to dispute
     * @param reason Dispute reason
     */
    function raiseDispute(bytes32 settlementId, string calldata reason) external;

    /**
     * @notice Get settlement details
     * @param settlementId The settlement to query
     * @return settlement The settlement struct
     */
    function getSettlement(bytes32 settlementId) external view returns (Settlement memory);
}
