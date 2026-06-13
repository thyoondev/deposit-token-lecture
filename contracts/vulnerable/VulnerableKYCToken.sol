// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ══════════════════════════════════════════════════════════════════════════════
// [취약점] KYC 우회 — _update 미구현으로 일부 경로 무방비
//
// transfer()에만 KYC 검사가 있고, transferFrom()과 mint()는 검사 없음.
// 공격자는 approve + transferFrom 조합으로 KYC 없이 토큰 이동 가능.
//
// 공격 시나리오:
//   1. KYC 없는 C가 KYC 있는 A에게 approve 요청
//   2. A가 C에게 approve(C, amount)
//   3. C가 transferFrom(A, C, amount) 호출 → KYC 없이 토큰 수신 성공
//
// 올바른 수정: transfer/transferFrom 개별 오버라이드 대신 _update 단일 오버라이드
//
// 감사 단골 Critical 패턴
// ══════════════════════════════════════════════════════════════════════════════

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IKYCRegistry {
    function isWhitelisted(address account) external view returns (bool);
}

contract VulnerableKYCToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    IKYCRegistry public kycRegistry;

    error NotWhitelisted(address account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address _kycRegistry) public initializer {
        __ERC20_init("Vulnerable KYC Token", "VKT");
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        kycRegistry = IKYCRegistry(_kycRegistry);
    }

    // ❌ 취약점: mint에 KYC 검사 없음 → KYC 미등록 주소에도 발행 가능
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // transfer에만 KYC 검사 → 부분 방어
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (!kycRegistry.isWhitelisted(to)) revert NotWhitelisted(to);
        return super.transfer(to, amount);
    }

    // ❌ 취약점: transferFrom 오버라이드 없음 → KYC 우회 가능
    // approve(B, amount) 후 B가 transferFrom(A, C, amount) 호출하면
    // KYC 미등록 C에게 토큰이 전달된다.

    // ── 올바른 수정 ──────────────────────────────────────────────────────────
    // transfer/transferFrom 개별 오버라이드 대신 _update를 단일 오버라이드:
    //
    // function _update(address from, address to, uint256 value) internal override {
    //     if (from != address(0) && !kycRegistry.isWhitelisted(from)) revert NotWhitelisted(from);
    //     if (to   != address(0) && !kycRegistry.isWhitelisted(to))   revert NotWhitelisted(to);
    //     super._update(from, to, value);
    // }
    // ─────────────────────────────────────────────────────────────────────────

    function _authorizeUpgrade(address)
        internal
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {}
}
