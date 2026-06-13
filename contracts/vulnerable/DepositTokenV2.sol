// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ══════════════════════════════════════════════════════════════════════════════
// [취약점] 스토리지 레이아웃 충돌 — V2
//
// ❌ V1과 슬롯 순서가 뒤바뀌었다:
//   slot N   : kycRegistry  (address)  ← V1에서는 slot N+1
//   slot N+1 : totalMinted  (uint256)  ← V1에서는 slot N
//
// 결과: 업그레이드 후 kycRegistry 를 읽으면 V1의 totalMinted 숫자값을
//       주소로 해석 → 완전히 잘못된 컨트랙트를 참조
//
// 규칙:
//   1. 기존 변수 순서 절대 변경 금지
//   2. 새 변수는 무조건 맨 뒤에 추가
//   3. 쓰지 않는 변수도 삭제 금지 (주석 처리만)
// ══════════════════════════════════════════════════════════════════════════════

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract DepositTokenV2 is
    Initializable,
    ERC20Upgradeable,
    UUPSUpgradeable
{
    address public kycRegistry;  // ❌ slot N   ← V1에서는 slot N+1이었다
    uint256 public totalMinted;  // ❌ slot N+1 ← V1에서는 slot N이었다

    // 안전한 V2라면 이렇게 해야 한다:
    // uint256 public totalMinted;   // slot N   (V1과 동일)
    // address public kycRegistry;   // slot N+1 (V1과 동일)
    // address public newFeature;    // slot N+2 (새 변수는 뒤에 추가)

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _kycRegistry) public initializer {
        __ERC20_init("Deposit Token V2", "DTV2");
        kycRegistry = _kycRegistry;
    }

    function mint(address to, uint256 amount) external {
        totalMinted += amount;
        _mint(to, amount);
    }

    function _authorizeUpgrade(address)
        internal
        override
    {}
}
