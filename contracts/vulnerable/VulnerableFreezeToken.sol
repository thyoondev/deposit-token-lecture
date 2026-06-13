// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ══════════════════════════════════════════════════════════════════════════════
// [취약점] freeze 우회 — transferFrom으로 동결 회피 가능
//
// transfer()에만 _frozen 검사가 있고, transferFrom()은 무방비.
// 동결 대상자가 미리 approve해 둔 경우 제3자가 동결 후에도 자금을 꺼낼 수 있다.
//
// 공격 시나리오:
//   1. AML 의심 계정 A가 freeze 당하기 전 approve(B, 전 잔액)
//   2. A가 freeze됨
//   3. B가 transferFrom(A, B, 전 잔액) 호출 → 성공! (freeze 검사 없음)
//   4. 동결은 명목상이고 실효성은 0
//
// 규제 준수 관점: 예금토큰에서 동결은 법원 명령·AML 핵심 도구
//                 우회되면 라이선스 위험까지 발생
//
// 올바른 수정: transfer/transferFrom 대신 _update 단일 오버라이드로 통일
// ══════════════════════════════════════════════════════════════════════════════

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract VulnerableFreezeToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    mapping(address => bool) private _frozen;

    event AccountFreezeUpdated(address indexed account, bool frozen);

    error AccountFrozen(address account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
        __ERC20_init("Vulnerable Freeze Token", "VFT");
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function freeze(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _frozen[account] = true;
        emit AccountFreezeUpdated(account, true);
    }

    function unfreeze(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _frozen[account] = false;
        emit AccountFreezeUpdated(account, false);
    }

    function isFrozen(address account) external view returns (bool) {
        return _frozen[account];
    }

    // transfer에만 freeze 검사 → 부분 방어
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (_frozen[msg.sender]) revert AccountFrozen(msg.sender);
        return super.transfer(to, amount);
    }

    // ❌ 취약점: transferFrom 오버라이드 없음 → approve 후 freeze 우회 가능

    // ── 올바른 수정 ──────────────────────────────────────────────────────────
    // function _update(address from, address to, uint256 value) internal override {
    //     if (from != address(0) && _frozen[from]) revert AccountFrozen(from);
    //     super._update(from, to, value);
    // }
    // ─────────────────────────────────────────────────────────────────────────

    function _authorizeUpgrade(address)
        internal
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {}
}
