// scripts/deploy.js
//
// 배포 순서:
// 1. KYCRegistry 배포 (UUPS Proxy)
// 2. DepositToken 배포 (UUPS Proxy) — KYCRegistry 주소 전달
// 3. 운영 Role 분리 예시 (주석 처리 — 실제 운영 시 멀티시그로 전환)
// 4. 초기 KYC 등록 (deployer 자신)
//
// ethers v6: contract.address → await contract.getAddress()

const { ethers, upgrades } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("=".repeat(50));
  console.log("배포 계정:", deployer.address);
  console.log(
    "계정 잔액:",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    "ETH"
  );
  console.log("=".repeat(50));

  // ─── 1. KYCRegistry 배포 ───────────────────────────────────────────────────
  console.log("\n[1/4] KYCRegistry 배포 중...");
  const KYCRegistry = await ethers.getContractFactory("KYCRegistry");
  const kycRegistry = await upgrades.deployProxy(
    KYCRegistry,
    [deployer.address],
    { kind: "uups" }
  );
  await kycRegistry.waitForDeployment();

  const kycRegistryAddress = await kycRegistry.getAddress();
  console.log("  KYCRegistry Proxy :", kycRegistryAddress);
  console.log(
    "  KYCRegistry Impl  :",
    await upgrades.erc1967.getImplementationAddress(kycRegistryAddress)
  );

  // ─── 2. DepositToken 배포 ──────────────────────────────────────────────────
  console.log("\n[2/4] DepositToken 배포 중...");
  const DepositToken = await ethers.getContractFactory("DepositToken");
  const depositToken = await upgrades.deployProxy(
    DepositToken,
    [
      "Korean Won Token",   // name
      "KWT",                // symbol
      deployer.address,     // admin
      kycRegistryAddress,   // kycRegistry
    ],
    { kind: "uups" }
  );
  await depositToken.waitForDeployment();

  const depositTokenAddress = await depositToken.getAddress();
  console.log("  DepositToken Proxy:", depositTokenAddress);
  console.log(
    "  DepositToken Impl :",
    await upgrades.erc1967.getImplementationAddress(depositTokenAddress)
  );

  // ─── 3. Role 부여 예시 ─────────────────────────────────────────────────────
  // 실제 운영에서는 각 Role을 별도 계정(또는 멀티시그)에 분산한다.
  // 예시: 별도 minter 계정이 있다면 아래와 같이 Role을 부여한다.
  // const minterAddress = "0xYourMinterAddress";
  // const MINTER_ROLE = await depositToken.MINTER_ROLE();
  // await depositToken.grantRole(MINTER_ROLE, minterAddress);
  // console.log("  MINTER_ROLE 부여 →", minterAddress);

  console.log("\n[3/4] Role 설정...");
  console.log("  (deployer가 모든 Role 보유: MINTER, BURNER, PAUSER, UPGRADER)");

  // ─── 4. 초기 KYC 등록 예시 ────────────────────────────────────────────────
  console.log("\n[4/4] 초기 KYC 등록 예시 (deployer 자신)...");
  await kycRegistry.addToWhitelist(deployer.address);
  console.log("  KYC 등록:", deployer.address);

  // ─── 배포 요약 ─────────────────────────────────────────────────────────────
  console.log("\n" + "=".repeat(50));
  console.log("배포 완료 요약");
  console.log("=".repeat(50));
  console.log("KYCRegistry  :", kycRegistryAddress);
  console.log("DepositToken :", depositTokenAddress);
  console.log("=".repeat(50));

  // 배포 주소를 파일로 저장 (필요 시 주석 해제)
  // const fs = require("fs");
  // fs.writeFileSync("deployed-addresses.json", JSON.stringify({
  //   kycRegistry: kycRegistryAddress,
  //   depositToken: depositTokenAddress,
  // }, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
