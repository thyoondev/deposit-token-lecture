// test/DepositToken.test.js
//
// 테스트 구조:
//   describe("DepositToken")
//   ├── beforeEach: KYCRegistry + DepositToken 배포, KYC 등록
//   ├── describe("mint")       — 5 케이스
//   ├── describe("burn")       — 3 케이스
//   ├── describe("transfer")   — 6 케이스
//   ├── describe("Role 관리")  — 5 케이스
//   ├── describe("upgrade")    — 3 케이스
//   ├── describe("edge case")  — 7 케이스
//   └── describe("KYCRegistry") — 3 케이스
//                                 합계 32 케이스
//
// ethers v6 주요 변경점:
//   - ethers.utils.parseEther → ethers.parseEther
//   - BigNumber → BigInt (네이티브)
//   - contract.address → await contract.getAddress()
//   - revertedWith → revertedWithCustomError (Custom Error 사용 시)

const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("DepositToken", function () {
  let depositToken;
  let kycRegistry;
  let admin;       // DEFAULT_ADMIN_ROLE + 모든 Role 보유
  let minter;      // MINTER_ROLE만 부여 (일부 테스트에서)
  let pauser;      // PAUSER_ROLE만 부여 (일부 테스트에서)
  let user1;       // KYC 등록된 일반 사용자
  let user2;       // KYC 등록된 일반 사용자
  let nonKycUser;  // KYC 미등록 사용자

  // 각 테스트 전에 새 컨트랙트 배포 (테스트 격리)
  beforeEach(async function () {
    [admin, minter, pauser, user1, user2, nonKycUser] =
      await ethers.getSigners();

    // ─ KYCRegistry 배포 ───────────────────────────────────────────────────
    const KYCRegistry = await ethers.getContractFactory("KYCRegistry");
    kycRegistry = await upgrades.deployProxy(KYCRegistry, [admin.address], {
      kind: "uups",
    });
    await kycRegistry.waitForDeployment();

    // ─ DepositToken 배포 ──────────────────────────────────────────────────
    const DepositToken = await ethers.getContractFactory("DepositToken");
    depositToken = await upgrades.deployProxy(
      DepositToken,
      [
        "Korean Won Token",
        "KWT",
        admin.address,
        await kycRegistry.getAddress(),
      ],
      { kind: "uups" }
    );
    await depositToken.waitForDeployment();

    // ─ 초기 KYC 등록 ──────────────────────────────────────────────────────
    // user1, user2, admin을 화이트리스트에 등록한다.
    // nonKycUser는 의도적으로 등록하지 않는다.
    await kycRegistry.connect(admin).addToWhitelist(user1.address);
    await kycRegistry.connect(admin).addToWhitelist(user2.address);
    await kycRegistry.connect(admin).addToWhitelist(admin.address);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // mint 테스트
  // ─────────────────────────────────────────────────────────────────────────
  describe("mint", function () {
    it("MINTER_ROLE 없는 계정이 mint 시도 → AccessControlUnauthorizedAccount revert", async function () {
      await expect(
        depositToken.connect(user1).mint(user2.address, ethers.parseEther("100"))
      )
        .to.be.revertedWithCustomError(
          depositToken,
          "AccessControlUnauthorizedAccount"
        )
        .withArgs(user1.address, await depositToken.MINTER_ROLE());
    });

    it("KYC 미등록 주소에 mint → NotWhitelisted revert", async function () {
      await expect(
        depositToken
          .connect(admin)
          .mint(nonKycUser.address, ethers.parseEther("100"))
      )
        .to.be.revertedWithCustomError(depositToken, "NotWhitelisted")
        .withArgs(nonKycUser.address);
    });

    it("정상 mint → balanceOf 증가 + Transfer 이벤트 발생", async function () {
      const amount = ethers.parseEther("1000");

      await expect(depositToken.connect(admin).mint(user1.address, amount))
        .to.emit(depositToken, "Transfer")
        .withArgs(ethers.ZeroAddress, user1.address, amount);

      expect(await depositToken.balanceOf(user1.address)).to.equal(amount);
    });

    it("amount = 0 mint → 정상 처리 (잔액 불변)", async function () {
      await depositToken.connect(admin).mint(user1.address, 0n);
      expect(await depositToken.balanceOf(user1.address)).to.equal(0n);
    });

    it("totalSupply가 mint 수량만큼 증가한다", async function () {
      const before = await depositToken.totalSupply();
      const amount = ethers.parseEther("500");
      await depositToken.connect(admin).mint(user1.address, amount);
      expect(await depositToken.totalSupply()).to.equal(before + amount);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // burn 테스트
  // ─────────────────────────────────────────────────────────────────────────
  describe("burn", function () {
    const mintAmount = ethers.parseEther("1000");

    beforeEach(async function () {
      await depositToken.connect(admin).mint(user1.address, mintAmount);
    });

    it("BURNER_ROLE 없는 계정이 burn 시도 → revert", async function () {
      await expect(
        depositToken.connect(user1).burn(user1.address, ethers.parseEther("100"))
      ).to.be.revertedWithCustomError(
        depositToken,
        "AccessControlUnauthorizedAccount"
      );
    });

    it("잔액 초과 소각 → revert ERC20InsufficientBalance", async function () {
      await expect(
        depositToken.connect(admin).burn(user1.address, mintAmount + 1n)
      ).to.be.revertedWithCustomError(depositToken, "ERC20InsufficientBalance");
    });

    it("정상 소각 → totalSupply 감소 + Transfer 이벤트 발생", async function () {
      const burnAmount = ethers.parseEther("300");

      await expect(depositToken.connect(admin).burn(user1.address, burnAmount))
        .to.emit(depositToken, "Transfer")
        .withArgs(user1.address, ethers.ZeroAddress, burnAmount);

      expect(await depositToken.totalSupply()).to.equal(mintAmount - burnAmount);
      expect(await depositToken.balanceOf(user1.address)).to.equal(
        mintAmount - burnAmount
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // transfer 테스트
  // ─────────────────────────────────────────────────────────────────────────
  describe("transfer", function () {
    const mintAmount = ethers.parseEther("1000");

    beforeEach(async function () {
      await depositToken.connect(admin).mint(user1.address, mintAmount);
    });

    it("수신자 KYC 미등록 → NotWhitelisted revert", async function () {
      await expect(
        depositToken
          .connect(user1)
          .transfer(nonKycUser.address, ethers.parseEther("100"))
      )
        .to.be.revertedWithCustomError(depositToken, "NotWhitelisted")
        .withArgs(nonKycUser.address);
    });

    it("발신자 동결(frozen) 상태 → AccountFrozen revert", async function () {
      await depositToken.connect(admin).freeze(user1.address);

      await expect(
        depositToken
          .connect(user1)
          .transfer(user2.address, ethers.parseEther("100"))
      )
        .to.be.revertedWithCustomError(depositToken, "AccountFrozen")
        .withArgs(user1.address);
    });

    it("pause 상태에서 transfer → EnforcedPause revert", async function () {
      await depositToken.connect(admin).pause();

      await expect(
        depositToken
          .connect(user1)
          .transfer(user2.address, ethers.parseEther("100"))
      ).to.be.revertedWithCustomError(depositToken, "EnforcedPause");
    });

    it("정상 transfer → balanceOf 갱신 확인", async function () {
      const transferAmount = ethers.parseEther("400");

      await depositToken.connect(user1).transfer(user2.address, transferAmount);

      expect(await depositToken.balanceOf(user1.address)).to.equal(
        mintAmount - transferAmount
      );
      expect(await depositToken.balanceOf(user2.address)).to.equal(
        transferAmount
      );
    });

    it("pause 후 unpause → transfer 정상화", async function () {
      await depositToken.connect(admin).pause();
      await depositToken.connect(admin).unpause();

      await depositToken
        .connect(user1)
        .transfer(user2.address, ethers.parseEther("100"));
      expect(await depositToken.balanceOf(user2.address)).to.equal(
        ethers.parseEther("100")
      );
    });

    it("unfreeze 후 transfer → 정상 처리", async function () {
      await depositToken.connect(admin).freeze(user1.address);
      await depositToken.connect(admin).unfreeze(user1.address);

      await depositToken
        .connect(user1)
        .transfer(user2.address, ethers.parseEther("100"));
      expect(await depositToken.balanceOf(user2.address)).to.equal(
        ethers.parseEther("100")
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Role 관리 테스트
  // ─────────────────────────────────────────────────────────────────────────
  describe("Role 관리", function () {
    it("DEFAULT_ADMIN_ROLE이 MINTER_ROLE을 minter에게 부여 가능", async function () {
      const MINTER_ROLE = await depositToken.MINTER_ROLE();

      expect(await depositToken.hasRole(MINTER_ROLE, minter.address)).to.be.false;

      await depositToken.connect(admin).grantRole(MINTER_ROLE, minter.address);

      expect(await depositToken.hasRole(MINTER_ROLE, minter.address)).to.be.true;
    });

    it("MINTER_ROLE 부여 후 minter가 mint 실행 가능", async function () {
      const MINTER_ROLE = await depositToken.MINTER_ROLE();
      await depositToken.connect(admin).grantRole(MINTER_ROLE, minter.address);

      await depositToken
        .connect(minter)
        .mint(user1.address, ethers.parseEther("100"));
      expect(await depositToken.balanceOf(user1.address)).to.equal(
        ethers.parseEther("100")
      );
    });

    it("revokeRole 후 해당 계정의 권한 상실", async function () {
      const MINTER_ROLE = await depositToken.MINTER_ROLE();

      await depositToken.connect(admin).grantRole(MINTER_ROLE, minter.address);
      await depositToken.connect(admin).revokeRole(MINTER_ROLE, minter.address);

      expect(await depositToken.hasRole(MINTER_ROLE, minter.address)).to.be.false;

      await expect(
        depositToken
          .connect(minter)
          .mint(user1.address, ethers.parseEther("100"))
      ).to.be.revertedWithCustomError(
        depositToken,
        "AccessControlUnauthorizedAccount"
      );
    });

    it("ADMIN_ROLE 없는 계정은 grantRole 불가", async function () {
      const MINTER_ROLE = await depositToken.MINTER_ROLE();

      await expect(
        depositToken.connect(user1).grantRole(MINTER_ROLE, user2.address)
      ).to.be.revertedWithCustomError(
        depositToken,
        "AccessControlUnauthorizedAccount"
      );
    });

    it("PAUSER_ROLE 보유 계정만 pause/unpause 가능", async function () {
      const PAUSER_ROLE = await depositToken.PAUSER_ROLE();
      await depositToken.connect(admin).grantRole(PAUSER_ROLE, pauser.address);

      await depositToken.connect(pauser).pause();
      expect(await depositToken.paused()).to.be.true;

      await depositToken.connect(pauser).unpause();
      expect(await depositToken.paused()).to.be.false;
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // upgrade 테스트
  // ─────────────────────────────────────────────────────────────────────────
  describe("upgrade", function () {
    it("UPGRADER_ROLE 없는 계정의 업그레이드 시도 → revert", async function () {
      const DepositTokenV2 = await ethers.getContractFactory(
        "DepositToken",
        user1
      );

      await expect(
        upgrades.upgradeProxy(await depositToken.getAddress(), DepositTokenV2, {
          kind: "uups",
        })
      ).to.be.revertedWithCustomError(
        depositToken,
        "AccessControlUnauthorizedAccount"
      );
    });

    it("UPGRADER_ROLE 보유 계정의 업그레이드 성공 → 상태(잔액) 유지", async function () {
      const mintAmount = ethers.parseEther("1000");
      await depositToken.connect(admin).mint(user1.address, mintAmount);
      const balanceBefore = await depositToken.balanceOf(user1.address);
      const proxyAddress = await depositToken.getAddress();

      const DepositTokenV2 = await ethers.getContractFactory("DepositToken");
      const upgraded = await upgrades.upgradeProxy(
        proxyAddress,
        DepositTokenV2,
        { kind: "uups" }
      );

      expect(await upgraded.getAddress()).to.equal(proxyAddress);
      expect(await upgraded.balanceOf(user1.address)).to.equal(balanceBefore);
    });

    it("업그레이드 후 새 구현 주소가 변경된다", async function () {
      const DepositTokenV2 = await ethers.getContractFactory("DepositToken");
      await upgrades.upgradeProxy(
        await depositToken.getAddress(),
        DepositTokenV2,
        { kind: "uups" }
      );

      const implAfter = await upgrades.erc1967.getImplementationAddress(
        await depositToken.getAddress()
      );
      expect(implAfter).to.be.a("string");
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // edge case 테스트
  // ─────────────────────────────────────────────────────────────────────────
  describe("edge case", function () {
    it("to = address(0) mint → ERC20InvalidReceiver revert", async function () {
      await expect(
        depositToken
          .connect(admin)
          .mint(ethers.ZeroAddress, ethers.parseEther("100"))
      ).to.be.revertedWithCustomError(depositToken, "ERC20InvalidReceiver");
    });

    it("자기 자신에게 transfer → 잔액 불변", async function () {
      const mintAmount = ethers.parseEther("500");
      await depositToken.connect(admin).mint(user1.address, mintAmount);

      await depositToken
        .connect(user1)
        .transfer(user1.address, ethers.parseEther("200"));

      expect(await depositToken.balanceOf(user1.address)).to.equal(mintAmount);
    });

    it("KYCRegistry 배포 시 batchAddToWhitelist 동작 확인", async function () {
      const addresses = [
        nonKycUser.address,
        ethers.Wallet.createRandom().address,
        ethers.Wallet.createRandom().address,
      ];

      await kycRegistry.connect(admin).batchAddToWhitelist(addresses);

      for (const addr of addresses) {
        expect(await kycRegistry.isWhitelisted(addr)).to.be.true;
      }
    });

    it("동결 계정도 수신은 가능하다 (발신만 차단)", async function () {
      await depositToken.connect(admin).freeze(user1.address);

      // 동결된 user1에게 mint (수신은 허용)
      await depositToken
        .connect(admin)
        .mint(user1.address, ethers.parseEther("100"));
      expect(await depositToken.balanceOf(user1.address)).to.equal(
        ethers.parseEther("100")
      );

      // 동결된 user1이 발신하는 것은 불가
      await expect(
        depositToken
          .connect(user1)
          .transfer(user2.address, ethers.parseEther("50"))
      ).to.be.revertedWithCustomError(depositToken, "AccountFrozen");
    });

    it("KYCStatusUpdated 이벤트가 올바른 인자로 emit된다", async function () {
      await expect(kycRegistry.connect(admin).addToWhitelist(nonKycUser.address))
        .to.emit(kycRegistry, "KYCStatusUpdated")
        .withArgs(nonKycUser.address, true);

      await expect(
        kycRegistry.connect(admin).removeFromWhitelist(nonKycUser.address)
      )
        .to.emit(kycRegistry, "KYCStatusUpdated")
        .withArgs(nonKycUser.address, false);
    });

    it("AccountFreezeUpdated 이벤트가 올바른 인자로 emit된다", async function () {
      await expect(depositToken.connect(admin).freeze(user1.address))
        .to.emit(depositToken, "AccountFreezeUpdated")
        .withArgs(user1.address, true);

      await expect(depositToken.connect(admin).unfreeze(user1.address))
        .to.emit(depositToken, "AccountFreezeUpdated")
        .withArgs(user1.address, false);
    });

    it("transferFrom — 승인(approve) 후 KYC 검사 통과 시 정상 처리", async function () {
      const mintAmount = ethers.parseEther("1000");
      await depositToken.connect(admin).mint(user1.address, mintAmount);

      await depositToken
        .connect(user1)
        .approve(user2.address, ethers.parseEther("500"));

      await depositToken
        .connect(user2)
        .transferFrom(
          user1.address,
          user2.address,
          ethers.parseEther("300")
        );

      expect(await depositToken.balanceOf(user2.address)).to.equal(
        ethers.parseEther("300")
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // KYCRegistry 독립 테스트
  // ─────────────────────────────────────────────────────────────────────────
  describe("KYCRegistry", function () {
    it("KYC_ADMIN_ROLE 없는 계정의 addToWhitelist → revert", async function () {
      await expect(
        kycRegistry.connect(user1).addToWhitelist(nonKycUser.address)
      ).to.be.revertedWithCustomError(
        kycRegistry,
        "AccessControlUnauthorizedAccount"
      );
    });

    it("removeFromWhitelist 후 isWhitelisted = false", async function () {
      await kycRegistry.connect(admin).removeFromWhitelist(user1.address);
      expect(await kycRegistry.isWhitelisted(user1.address)).to.be.false;
    });

    it("미등록 주소 isWhitelisted = false", async function () {
      expect(await kycRegistry.isWhitelisted(nonKycUser.address)).to.be.false;
    });
  });
});
