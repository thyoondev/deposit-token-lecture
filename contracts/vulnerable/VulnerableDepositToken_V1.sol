// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ══════════════════════════════════════════════════════════════════════════════
// [취약점] 초기화 미보호
//
// 취약점 1: constructor에 _disableInitializers() 누락
//   → Implementation 컨트랙트를 누구나 직접 initialize() 가능
//   → UPGRADER_ROLE 탈취 → selfdestruct로 Implementation 파괴
//   → Proxy가 빈 코드를 가리켜 서비스 전체 중단
//
// 취약점 2: initialize()에 initializer modifier 누락
//   → Proxy에 배포된 후에도 재호출 가능 → 권한 재탈취
//
// 취약점 3: _authorizeUpgrade()에 접근 제어 없음
//   → 누구나 업그레이드 가능
//
// 실제 사고: 2022 Audius ($6M 피해)
// ══════════════════════════════════════════════════════════════════════════════

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract VulnerableDepositToken_V1 is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE   = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ❌ 취약점 1: _disableInitializers() 없음
    constructor() {
        // 안전한 코드:
        // _disableInitializers();
    }

    // ❌ 취약점 2: initializer modifier 없음 → 재호출 가능
    function initialize(address admin) public /* initializer */ {
        __ERC20_init("Vulnerable Token", "VT");
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // ❌ 취약점 3: onlyRole 없음 → 누구나 업그레이드 가능
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        // onlyRole(UPGRADER_ROLE) ← 이 한 줄이 빠져 있다
    {}
}
