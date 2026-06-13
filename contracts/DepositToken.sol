// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ─────────────────────────────────────────────────────────────────────────────
// 예금토큰 설계 원칙
//
// 1. 업그레이드 가능성: 규제 변경이나 기능 추가를 위해 UUPS 패턴 적용
// 2. 역할 분리(RBAC): 발행·소각·일시정지·업그레이드 권한을 별도 Role로 분리
//    → 운영 리스크 최소화 (단일 키 타협 시 피해 범위 제한)
// 3. KYC/AML 준수: 모든 전송 경로(mint/transfer/transferFrom)에서 KYC 검증
// 4. 계정 동결: 자금세탁 의심 계정을 즉시 동결하는 긴급 통제 수단
// ─────────────────────────────────────────────────────────────────────────────

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// KYCRegistry 인터페이스만 필요하므로 interface를 정의하여 결합도를 낮춘다.
interface IKYCRegistry {
    function isWhitelisted(address account) external view returns (bool);
}

/// @title DepositToken
/// @notice 은행 예금을 표현하는 ERC-20 기반 예금토큰
/// @dev UUPS Upgradeable + RBAC + KYC + Freeze + Pause 제어 레이어 포함
contract DepositToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    // ─── Role 상수 ─────────────────────────────────────────────────────────────
    bytes32 public constant MINTER_ROLE    = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE    = keccak256("BURNER_ROLE");
    bytes32 public constant PAUSER_ROLE    = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE  = keccak256("UPGRADER_ROLE");
    bytes32 public constant KYC_ADMIN_ROLE = keccak256("KYC_ADMIN_ROLE");

    // ─── Custom Errors ─────────────────────────────────────────────────────────
    error NotWhitelisted(address account);
    error AccountFrozen(address account);

    // ─── 상태 변수 ─────────────────────────────────────────────────────────────
    IKYCRegistry public kycRegistry;

    // 동결된 계정 추적: 개인 AML 조사 또는 법원 명령 시 사용
    mapping(address => bool) private _frozen;

    // ─── 이벤트 ────────────────────────────────────────────────────────────────
    event AccountFreezeUpdated(address indexed account, bool frozen);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ─── 초기화 ────────────────────────────────────────────────────────────────
    /// @param name  토큰 이름 (예: "Korean Won Token")
    /// @param symbol 토큰 심볼 (예: "KWT")
    /// @param admin 모든 초기 Role을 받을 관리자 주소
    /// @param kycRegistryAddress 배포된 KYCRegistry Proxy 주소
    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        address kycRegistryAddress
    ) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Pausable_init();
        __AccessControl_init();
        // OZ v5의 UUPSUpgradeable는 별도 init 함수가 없다 (상속만으로 충분).

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE,        admin);
        _grantRole(BURNER_ROLE,        admin);
        _grantRole(PAUSER_ROLE,        admin);
        _grantRole(UPGRADER_ROLE,      admin);
        _grantRole(KYC_ADMIN_ROLE,     admin);

        kycRegistry = IKYCRegistry(kycRegistryAddress);
    }

    // ─── 발행 ──────────────────────────────────────────────────────────────────
    /// @notice 예금 발행
    /// @dev KYC 검증은 _update 훅에서 일괄 처리한다.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // ─── 소각 ──────────────────────────────────────────────────────────────────
    /// @notice 예금 상환 — BURNER_ROLE만 강제 소각 가능 (사용자 자가 소각 비활성)
    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    // ─── 일시정지 ──────────────────────────────────────────────────────────────
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ─── 계정 동결 ─────────────────────────────────────────────────────────────
    /// @notice 동결은 "발신 차단"이지 "수신 차단"이 아님 (_update 참고)
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

    // ─── 전송 제어 오버라이드 ──────────────────────────────────────────────────
    /// @notice ERC-20의 모든 토큰 이동(mint/transfer/burn)은 이 함수를 통과한다
    /// @dev OZ v5에서 _beforeTokenTransfer 대신 _update를 오버라이드한다.
    ///
    ///      검사 순서:
    ///      1. Freeze 검사 — 개별 계정 제재 (from만 차단, to는 수신 허용)
    ///      2. KYC 검사 — 규제 준수
    ///      3. Pause 검사 — super._update(ERC20PausableUpgradeable)가 처리
    ///
    ///      from == address(0): mint → 발신자 검사 불필요
    ///      to   == address(0): burn → 수신자 검사 불필요
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        // ① 계정 동결 검사 (mint는 from == address(0)이므로 제외)
        if (from != address(0) && _frozen[from]) {
            revert AccountFrozen(from);
        }

        // ② KYC 검사
        if (from != address(0) && !kycRegistry.isWhitelisted(from)) {
            revert NotWhitelisted(from);
        }
        if (to != address(0) && !kycRegistry.isWhitelisted(to)) {
            revert NotWhitelisted(to);
        }

        // ③ Pause 검사는 ERC20PausableUpgradeable._update가 처리
        //    C3 선형화: ERC20PausableUpgradeable → ERC20Upgradeable 순으로 자동 호출
        super._update(from, to, value);
    }

    // ─── 업그레이드 인가 ───────────────────────────────────────────────────────
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}
}
