// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ══════════════════════════════════════════════════════════════════════════════
// [취약점] 스토리지 레이아웃 충돌 — V1
//
// 커스텀 변수 슬롯 순서:
//   slot N   : totalMinted  (uint256)
//   slot N+1 : kycRegistry  (address)
//
// V2에서 순서가 뒤바뀌면 업그레이드 후 kycRegistry가 totalMinted 값을 읽어
// 잘못된 주소를 참조하게 된다.
//
// 검증: slither-check-upgradeability
//   contracts/vulnerable/DepositTokenV1.sol DepositTokenV1 \
//   contracts/vulnerable/DepositTokenV2.sol DepositTokenV2
// ══════════════════════════════════════════════════════════════════════════════

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract DepositTokenV1 is
    Initializable,
    ERC20Upgradeable,
    UUPSUpgradeable
{
    uint256 public totalMinted;   // slot N
    address public kycRegistry;  // slot N+1

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _kycRegistry) public initializer {
        __ERC20_init("Deposit Token V1", "DTV1");
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
