// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// RWAComplianceToken — ERC-20 token representing a Real-World Asset with
// ERC-3643-style on-chain compliance hooks. Only KYC-whitelisted addresses
// may hold or receive tokens. Used for real estate tokenization, invoice
// receivables, and securities issuance on Avalanche C-Chain.
//
// OZ 5.x: inherits ERC20Pausable + Ownable. Uses _update() hook (NOT
// _beforeTokenTransfer which was removed in OZ 5.x).

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RWAComplianceToken is ERC20Pausable, Ownable {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------
    event WhitelistAdded(address indexed account);
    event WhitelistRemoved(address indexed account);
    event FreezeStatusChanged(address indexed account, bool frozen);
    event ComplianceRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------
    mapping(address => bool) private _whitelist;
    mapping(address => bool) private _frozen;

    /// @notice Optional external ERC-3643 identity registry address.
    address public complianceRegistry;

    uint8 private immutable _tokenDecimals;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param name_         ERC-20 token name
    /// @param symbol_       ERC-20 token symbol
    /// @param decimals_     Token decimal places (stored as immutable)
    /// @param initialOwner_ Contract owner; auto-whitelisted on deployment
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address initialOwner_
    ) ERC20(name_, symbol_) Ownable(initialOwner_) {
        require(initialOwner_ != address(0), "RWA: zero owner");
        _tokenDecimals = decimals_;
        // Auto-whitelist the owner so they can receive minted tokens
        _whitelist[initialOwner_] = true;
        emit WhitelistAdded(initialOwner_);
    }

    // -------------------------------------------------------------------------
    // Decimals override
    // -------------------------------------------------------------------------

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    // -------------------------------------------------------------------------
    // Whitelist management (onlyOwner)
    // -------------------------------------------------------------------------

    function addToWhitelist(address account) external onlyOwner {
        require(!_whitelist[account], "RWA: already whitelisted");
        _whitelist[account] = true;
        emit WhitelistAdded(account);
    }

    function removeFromWhitelist(address account) external onlyOwner {
        require(_whitelist[account], "RWA: not whitelisted");
        _whitelist[account] = false;
        emit WhitelistRemoved(account);
    }

    function isWhitelisted(address account) external view returns (bool) {
        return _whitelist[account];
    }

    // -------------------------------------------------------------------------
    // Freeze management (onlyOwner)
    // -------------------------------------------------------------------------

    function setFrozen(address account, bool frozen_) external onlyOwner {
        _frozen[account] = frozen_;
        emit FreezeStatusChanged(account, frozen_);
    }

    function isFrozen(address account) external view returns (bool) {
        return _frozen[account];
    }

    // -------------------------------------------------------------------------
    // External registry (onlyOwner)
    // -------------------------------------------------------------------------

    function setComplianceRegistry(address registry_) external onlyOwner {
        address old = complianceRegistry;
        complianceRegistry = registry_;
        emit ComplianceRegistryUpdated(old, registry_);
    }

    // -------------------------------------------------------------------------
    // Mint / burn (onlyOwner)
    // -------------------------------------------------------------------------

    /// @notice Mint tokens to a whitelisted, unfrozen address.
    function mintCompliant(address to, uint256 amount) external onlyOwner {
        require(_whitelist[to], "RWA: recipient not whitelisted");
        require(!_frozen[to], "RWA: recipient is frozen");
        _mint(to, amount);
    }

    /// @notice Forcibly burn tokens from any address (regulatory action).
    function forceBurn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    // -------------------------------------------------------------------------
    // Pause circuit breaker (onlyOwner)
    // -------------------------------------------------------------------------

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // -------------------------------------------------------------------------
    // OZ 5.x compliance hook — gates all mint/transfer/burn operations
    // -------------------------------------------------------------------------

    /// @dev Called by ERC-20 core for every balance mutation.
    ///      - Mint  (from == address(0)):  whitelist/freeze enforced in mintCompliant().
    ///      - Burn  (to   == address(0)):  if caller is NOT owner, require sender not frozen.
    ///      - Transfer (both non-zero):    require both parties whitelisted AND not frozen.
    ///      Always calls super._update() last to preserve ERC20Pausable pause check.
    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20Pausable)
    {
        if (from != address(0) && to != address(0)) {
            // Transfer path: both must be whitelisted and not frozen
            require(_whitelist[from], "RWA: sender not whitelisted");
            require(!_frozen[from], "RWA: sender is frozen");
            require(_whitelist[to], "RWA: recipient not whitelisted");
            require(!_frozen[to], "RWA: recipient is frozen");
        } else if (to == address(0)) {
            // Burn path: if caller is not the owner, sender must not be frozen
            if (msg.sender != owner()) {
                require(!_frozen[from], "RWA: sender is frozen");
            }
        }
        // Mint path (from == address(0)): compliance enforced in mintCompliant()
        super._update(from, to, amount);
    }
}
