// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ─────────────────────────────────────────────────────────────────────────────
// 왜 KYCRegistry를 별도 컨트랙트로 분리하는가?
//
// 1. 단일 책임 원칙(SRP): 화이트리스트 상태 관리 책임을 DepositToken에서 분리한다.
// 2. 재사용성: 여러 토큰 컨트랙트가 하나의 KYCRegistry를 공유할 수 있다.
// 3. 업그레이드 독립성: KYC 로직 변경 시 토큰 컨트랙트를 건드리지 않아도 된다.
// ─────────────────────────────────────────────────────────────────────────────

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title KYCRegistry
/// @notice 규제 준수를 위한 KYC/AML 화이트리스트 레지스트리
/// @dev UUPS Upgradeable + AccessControl 조합
///      - 업그레이드 가능 구조: 규제 변경 시 로직 교체 가능
///      - Role 기반 접근 제어: KYC 운영자 권한 분리
contract KYCRegistry is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    // ─── Role 상수 ─────────────────────────────────────────────────────────────
    bytes32 public constant KYC_ADMIN_ROLE = keccak256("KYC_ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE  = keccak256("UPGRADER_ROLE");

    // ─── 상태 변수 ─────────────────────────────────────────────────────────────
    // private으로 선언하여 직접 접근을 차단하고 isWhitelisted()를 통해서만 조회하도록 강제한다.
    mapping(address => bool) private _whitelist;

    // ─── 이벤트 ────────────────────────────────────────────────────────────────
    // 단일 이벤트로 추가/제거를 모두 표현한다. bool status로 온체인 감사 로그를 단순화한다.
    event KYCStatusUpdated(address indexed account, bool status);

    // ─── 업그레이드 가능 컨트랙트의 생성자 처리 ───────────────────────────────────
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ─── 초기화 ────────────────────────────────────────────────────────────────
    /// @notice Proxy 배포 시 최초 한 번만 호출되는 초기화 함수
    /// @param admin DEFAULT_ADMIN_ROLE 및 초기 권한을 받을 주소
    function initialize(address admin) public initializer {
        __AccessControl_init();
        // OZ v5의 UUPSUpgradeable는 별도 init 함수가 없다 (상속만으로 충분).

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(KYC_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    // ─── KYC 관리 함수 ──────────────────────────────────────────────────────────

    /// @notice 단일 주소를 화이트리스트에 추가한다
    function addToWhitelist(address account) external onlyRole(KYC_ADMIN_ROLE) {
        _whitelist[account] = true;
        emit KYCStatusUpdated(account, true);
    }

    /// @notice 단일 주소를 화이트리스트에서 제거한다
    function removeFromWhitelist(address account) external onlyRole(KYC_ADMIN_ROLE) {
        _whitelist[account] = false;
        emit KYCStatusUpdated(account, false);
    }

    /// @notice 다수 주소를 한 번에 화이트리스트에 추가한다
    /// @dev calldata 사용: 함수 인수를 메모리에 복사하지 않아 가스를 절약한다
    function batchAddToWhitelist(address[] calldata accounts)
        external
        onlyRole(KYC_ADMIN_ROLE)
    {
        for (uint256 i = 0; i < accounts.length; i++) {
            _whitelist[accounts[i]] = true;
            emit KYCStatusUpdated(accounts[i], true);
        }
    }

    // ─── 조회 함수 ─────────────────────────────────────────────────────────────

    /// @notice 주소의 KYC 승인 여부를 반환한다
    function isWhitelisted(address account) external view returns (bool) {
        return _whitelist[account];
    }

    // ─── 업그레이드 인가 ───────────────────────────────────────────────────────
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}
}
