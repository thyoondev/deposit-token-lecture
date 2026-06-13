// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ══════════════════════════════════════════════════════════════════════════════
// [취약점] 업그레이드 권한 누락
//
// _authorizeUpgrade()에 onlyRole modifier가 없어 누구나 업그레이드 가능.
// 공격자가 악의적 Implementation을 배포 후 upgradeToAndCall()을 호출하면
// 컨트랙트 전체가 탈취된다.
//
// Slither 탐지: unprotected-upgrade (Severity: High)
// 실제 사고: 2020 dForce 패턴
// ══════════════════════════════════════════════════════════════════════════════

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract VulnerableUpgradeToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE   = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
        __ERC20_init("Vulnerable Upgrade Token", "VUT");
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // ❌ 취약점: onlyRole(UPGRADER_ROLE) 없음 → 누구나 업그레이드 가능
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        // onlyRole(UPGRADER_ROLE) ← 이 한 줄이 빠져 있다
    {}
}
