// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ── 수강생 실습용 템플릿 ──────────────────────────────────────────────────────
// 이 파일은 Hardhat 컴파일 대상이 아닙니다 (student-templates/ 디렉토리).
// 직접 채워서 contracts/DepositToken.sol에 복사하세요.
// ─────────────────────────────────────────────────────────────────────────────

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IKYCRegistry {
    function isWhitelisted(address account) external view returns (bool);
}

/// @title DepositToken (템플릿)
contract DepositToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    // TODO 1: Role 상수 5개를 keccak256("...")으로 선언하세요.
    bytes32 public constant MINTER_ROLE    = /* TODO */;
    bytes32 public constant BURNER_ROLE    = /* TODO */;
    bytes32 public constant PAUSER_ROLE    = /* TODO */;
    bytes32 public constant UPGRADER_ROLE  = /* TODO */;
    bytes32 public constant KYC_ADMIN_ROLE = /* TODO */;

    // 이 선언은 수정하지 마세요 — 테스트에서 revertedWithCustomError로 검증합니다.
    error NotWhitelisted(address account);
    error AccountFrozen(address account);

    // TODO 2: IKYCRegistry 타입의 public 변수 kycRegistry를 선언하세요.
    /* TODO */

    // TODO 3: 주소 → bool 동결 상태 매핑을 private으로 선언하세요. 변수명: _frozen
    /* TODO */

    event AccountFreezeUpdated(address indexed account, bool frozen);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // TODO 4: _disableInitializers() 호출
        /* TODO */
    }

    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        address kycRegistryAddress
    ) public initializer {
        // TODO 5: 부모 init 3개 호출
        //         __ERC20_init(name, symbol)
        //         __ERC20Pausable_init()
        //         __AccessControl_init()
        //         (OZ v5 UUPSUpgradeable는 별도 init 없음)
        /* TODO */

        // TODO 6: admin에게 6개 Role 모두 부여
        //         DEFAULT_ADMIN_ROLE, MINTER, BURNER, PAUSER, UPGRADER, KYC_ADMIN
        /* TODO */

        // TODO 7: kycRegistry = IKYCRegistry(kycRegistryAddress)
        /* TODO */
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        // TODO 8: _mint(to, amount) 호출
        //
        // ⚠️  주의: mint 함수 안에 KYC 명시적 체크를 추가하면 안 됩니다.
        //    이유: mint 시 from == address(0)인데, 명시적 체크를 추가하면
        //          to == address(0) 케이스에서 ERC20InvalidReceiver 대신
        //          NotWhitelisted 에러가 먼저 나와 테스트가 깨집니다.
        //    KYC 검사는 아래 _update 훅이 전담합니다.
        /* TODO */
    }

    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        // TODO 9: _burn(from, amount) 호출
        /* TODO */
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        // TODO 10: _pause() 호출
        /* TODO */
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        // TODO 11: _unpause() 호출
        /* TODO */
    }

    function freeze(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // TODO 12: _frozen[account] = true, AccountFreezeUpdated 이벤트 emit
        /* TODO */
    }

    function unfreeze(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // TODO 13: _frozen[account] = false, 이벤트 emit
        /* TODO */
    }

    function isFrozen(address account) external view returns (bool) {
        // TODO 14: _frozen[account] 반환
        /* TODO */
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        // TODO 15: from != address(0)일 때 _frozen[from] 검사 → AccountFrozen revert
        /* TODO */

        // TODO 16: from != address(0)일 때 KYC 검사 → NotWhitelisted revert
        /* TODO */

        // TODO 17: to != address(0)일 때 KYC 검사 → NotWhitelisted revert
        /* TODO */

        // TODO 18: super._update(from, to, value) 호출
        //          (Pause 검사는 ERC20PausableUpgradeable._update가 처리)
        /* TODO */
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        // TODO 19: onlyRole(UPGRADER_ROLE) 추가
    {
        /* TODO */
    }
}
