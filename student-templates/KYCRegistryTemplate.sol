// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ── 수강생 실습용 템플릿 ──────────────────────────────────────────────────────
// 이 파일은 Hardhat 컴파일 대상이 아닙니다 (student-templates/ 디렉토리).
// 직접 채워서 contracts/KYCRegistry.sol에 복사하세요.
// ─────────────────────────────────────────────────────────────────────────────

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title KYCRegistry (템플릿)
contract KYCRegistry is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    // TODO 1: KYC_ADMIN_ROLE을 keccak256("KYC_ADMIN_ROLE")로 선언하세요.
    bytes32 public constant KYC_ADMIN_ROLE = /* TODO */;

    // TODO 2: UPGRADER_ROLE도 동일한 방식으로 선언하세요.
    bytes32 public constant UPGRADER_ROLE = /* TODO */;

    // TODO 3: address → bool 화이트리스트 매핑을 private으로 선언하세요.
    //         변수명: _whitelist
    /* TODO */

    // 이 이벤트 시그니처는 수정하지 마세요 — 테스트가 이걸 참조합니다.
    event KYCStatusUpdated(address indexed account, bool status);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // TODO 4: 구현 컨트랙트 자체의 초기화를 영구 차단하는 함수를 호출하세요.
        /* TODO */
    }

    function initialize(address admin) public initializer {
        // TODO 5: AccessControl의 __init() 함수를 호출하세요.
        //         (OZ v5 UUPSUpgradeable는 별도 init 없음)
        /* TODO */

        // TODO 6: admin에게 DEFAULT_ADMIN_ROLE, KYC_ADMIN_ROLE, UPGRADER_ROLE을 부여하세요.
        /* TODO */
    }

    function addToWhitelist(address account) external onlyRole(KYC_ADMIN_ROLE) {
        // TODO 7: _whitelist[account] = true 후 KYCStatusUpdated 이벤트 emit
        /* TODO */
    }

    function removeFromWhitelist(address account) external onlyRole(KYC_ADMIN_ROLE) {
        // TODO 8: _whitelist[account] = false 후 이벤트 emit
        /* TODO */
    }

    function batchAddToWhitelist(address[] calldata accounts)
        external
        onlyRole(KYC_ADMIN_ROLE)
    {
        // TODO 9: accounts 배열을 순회하며 화이트리스트 추가 + 이벤트 emit
        /* TODO */
    }

    function isWhitelisted(address account) external view returns (bool) {
        // TODO 10: _whitelist[account]를 반환하세요.
        /* TODO */
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        // TODO 11: onlyRole(UPGRADER_ROLE) 추가
    {
        /* TODO */
    }
}
