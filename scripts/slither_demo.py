#!/usr/bin/env python3
"""
실습 5 — Slither 보안 분석 데모 (5 시나리오)

실행: python3 scripts/slither_demo.py
     python3 scripts/slither_demo.py 2     # 특정 시나리오만

참고: Slither 0.11.x + OZ v5 UUPS 조합에서 unprotected-upgrade 자동 탐지가
      제한적이므로 function-summary 파서로 동일 정보를 출력합니다.
"""

import subprocess, json, sys, re
from pathlib import Path
from collections import defaultdict

BASE = Path(__file__).resolve().parent.parent
FLAGS = ["--compile-force-framework", "hardhat", "--filter-paths", "node_modules"]

# ── helpers ─────────────────────────────────────────────────────────────────

def slither(*extra, json_mode=False):
    cmd = ["slither", str(BASE)] + FLAGS + list(extra)
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=BASE)
    if json_mode:
        try:
            return json.loads(r.stdout)
        except Exception:
            return {}
    return r.stdout, r.stderr  # (stdout, stderr)

def check_upgradeability(v1, v2):
    # --filter-paths는 slither-check-upgradeability가 미지원 → 제외
    cmd = ["slither-check-upgradeability", str(BASE), v1,
           "--new-contract-name", v2,
           "--compile-force-framework", "hardhat"]
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=BASE)
    return r.stdout + r.stderr

def parse_fs(stderr_text):
    """function-summary 파서 → {contract: [{name, visibility, modifiers, calls}]}"""
    contracts = {}
    current = None
    for line in stderr_text.split("\n"):
        m = re.match(r"^Contract (\w+)$", line.strip())
        if m:
            current = m.group(1)
            contracts[current] = []
            continue
        if current and line.strip().startswith("|") and not line.strip().startswith("+-"):
            cols = [c.strip() for c in line.split("|")[1:-1]]
            if cols and cols[0] and "Function" not in cols[0]:
                contracts[current].append(dict(
                    name    = cols[0],
                    vis     = cols[1] if len(cols) > 1 else "",
                    mods    = cols[2] if len(cols) > 2 else "[]",
                    calls   = cols[5] if len(cols) > 5 else "",
                ))
    return contracts

def get_fs():
    _, stderr = slither("--print", "function-summary")
    return parse_fs(stderr)

def sec(n, title):
    bar = "═" * 62
    print(f"\n{bar}")
    print(f"  [{n}] {title}")
    print(bar)

def ok(msg):   print(f"  ✅  {msg}")
def fail(msg): print(f"  ❌  {msg}")
def warn(msg): print(f"  ⚠️   {msg}")
def note(msg): print(f"  ℹ️   {msg}")

# ── Scenario 0: 정상 코드 스모크 테스트 ────────────────────────────────────

def s0():
    sec(0, "정상 코드 스모크 테스트")
    print("  대상: contracts/KYCRegistry.sol, contracts/DepositToken.sol\n")
    data = slither("--exclude-informational", "--exclude-low", "--json", "-", json_mode=True)
    findings = [
        f for f in data.get("results", {}).get("detectors", [])
        if not any("vulnerable" in str(e.get("source_mapping", {}).get("filename_short", ""))
                   for e in f.get("elements", []))
        and not all("node_modules" in str(e.get("source_mapping", {}).get("filename_short", ""))
                    for e in f.get("elements", []))
    ]
    if not findings:
        ok("High/Medium 취약점 0건 — 정상 통과")
    else:
        for f in findings:
            fail(f'[{f["impact"]}] {f["check"]}: {f.get("description","")[:70]}')

# ── Scenario 1: 초기화 미보호 ───────────────────────────────────────────────

def s1(fs):
    sec(1, "초기화 미보호 — VulnerableDepositToken_V1")
    print("  참조 사고: 2022 Audius ($6M)\n")

    vuln = fs.get("VulnerableDepositToken_V1", [])
    safe = fs.get("DepositToken", [])

    # ① initialize modifier 비교
    print("  [검사 1] initialize() — initializer modifier 존재 여부")
    v_init = next((f for f in vuln if "initialize" in f["name"] and f["vis"] == "public"), None)
    s_init = next((f for f in safe if "initialize" in f["name"] and f["vis"] == "public"), None)
    if v_init:
        if "initializer" in v_init["mods"]:
            ok(f'VulnerableDepositToken_V1.{v_init["name"]}  mods={v_init["mods"]}')
        else:
            fail(f'VulnerableDepositToken_V1.{v_init["name"]}  mods={v_init["mods"]}  → 재호출 가능!')
    if s_init:
        ok(f'DepositToken.{s_init["name"]}  mods={s_init["mods"]}')

    # ② _authorizeUpgrade modifier 비교
    print("\n  [검사 2] _authorizeUpgrade() — 접근 제어 modifier 존재 여부")
    v_auth = [f for f in vuln if "_authorizeUpgrade" in f["name"] and f["vis"] == "internal"]
    s_auth = [f for f in safe if "_authorizeUpgrade" in f["name"] and f["vis"] == "internal"]

    for f in v_auth:
        if f["mods"] == "[]":
            fail(f'VulnerableDepositToken_V1._authorizeUpgrade  mods={f["mods"]}  → 누구나 업그레이드!')
        else:
            ok(f'VulnerableDepositToken_V1._authorizeUpgrade  mods={f["mods"]}')
        break  # 첫 번째(오버라이드)만
    for f in s_auth:
        if f["mods"] != "[]":
            ok(f'DepositToken._authorizeUpgrade               mods={f["mods"]}')
            break

    print("\n  [수정 방법]")
    print("    constructor() { _disableInitializers(); }   // 추가")
    print("    function initialize(...) public initializer { ... }  // initializer 추가")
    print("    function _authorizeUpgrade(...) internal override onlyRole(UPGRADER_ROLE) {}")

# ── Scenario 2: 스토리지 레이아웃 충돌 ─────────────────────────────────────

def s2():
    sec(2, "스토리지 레이아웃 충돌 — DepositTokenV1 → DepositTokenV2")
    print("  명령어: slither-check-upgradeability . DepositTokenV1 --new-contract-name DepositTokenV2\n")

    out = check_upgradeability("DepositTokenV1", "DepositTokenV2")
    found = False
    for line in out.split("\n"):
        line = line.strip()
        if "Different variables" in line:
            fail(line)
            found = True
        elif "DepositTokenV1." in line or "DepositTokenV2." in line:
            if found:
                print(f"    {line}")

    if not found:
        note("slither-check-upgradeability 결과 없음 — 수동 확인 필요")

    print("\n  [슬롯 비교]")
    print("    V1:  slot N   = totalMinted (uint256)")
    print("         slot N+1 = kycRegistry (address)")
    print("    V2:  slot N   = kycRegistry (address)  ← 순서 뒤바뀜!")
    print("         slot N+1 = totalMinted (uint256)   ← 순서 뒤바뀜!")
    print("\n  [수정 방법] 새 변수는 무조건 기존 변수 뒤에 추가, 기존 순서 절대 변경 금지")

# ── Scenario 3: KYC 우회 ────────────────────────────────────────────────────

def s3(fs):
    sec(3, "KYC 우회 — VulnerableKYCToken")
    print("  transfer()에만 KYC 검사, transferFrom()은 무방비\n")

    vuln = fs.get("VulnerableKYCToken", [])
    safe = fs.get("DepositToken", [])

    # transfer 항목 개수 분석 (오버라이드 여부)
    def count_fn(rows, name_key):
        return [f for f in rows if name_key in f["name"]]

    v_transfers     = count_fn(vuln, "transfer(address,uint256)")
    v_transferfroms = count_fn(vuln, "transferFrom(")
    s_updates       = count_fn(safe, "_update(")

    print("  [검사 1] transfer() 오버라이드 여부 (항목 수로 판별)")
    if len(v_transfers) > 2:
        fail(f'VulnerableKYCToken.transfer    항목 수={len(v_transfers)}  → 커스텀 오버라이드 존재 (KYC 체크 있음)')
    else:
        note(f'VulnerableKYCToken.transfer    항목 수={len(v_transfers)}')

    print("\n  [검사 2] transferFrom() 오버라이드 여부")
    if len(v_transferfroms) <= 2:
        fail(f'VulnerableKYCToken.transferFrom 항목 수={len(v_transferfroms)}  → 오버라이드 없음! KYC 검사 우회 가능')
    else:
        ok(f'VulnerableKYCToken.transferFrom 항목 수={len(v_transferfroms)}  → 오버라이드 존재')

    print("\n  [검사 3] _update() 단일 진입점 존재 여부")
    if not s_updates:
        fail("VulnerableKYCToken._update 오버라이드 없음 → 우회 경로 존재")
    else:
        ok("DepositToken._update 오버라이드 있음")

    # Slither 탐지 가능한 findings
    data = slither("--json", "-", json_mode=True)
    hits = [f for f in data.get("results", {}).get("detectors", [])
            if any("VulnerableKYCToken" in str(e) for e in f.get("elements", []))]
    if hits:
        print("\n  [Slither 자동 탐지]")
        for h in hits:
            note(f'[{h["impact"]}] {h["check"]}: {h.get("description","").split(chr(10))[0][:70]}')

    print("\n  [공격 시나리오]")
    print("    1. KYC 없는 C가 KYC 있는 A에게 충분한 approve 요청")
    print("    2. A가 approve(C, amount)")
    print("    3. C가 transferFrom(A, C, amount) 호출 → KYC 없이 토큰 수신!")
    print("\n  [수정 방법] transfer/transferFrom 개별 오버라이드 대신 _update 단일 오버라이드:")
    print("    function _update(address from, address to, uint256 value) internal override {")
    print("        if (to != address(0) && !kycRegistry.isWhitelisted(to)) revert NotWhitelisted(to);")
    print("        super._update(from, to, value);")
    print("    }")

# ── Scenario 4: 업그레이드 권한 누락 ───────────────────────────────────────

def s4(fs):
    sec(4, "업그레이드 권한 누락 — VulnerableUpgradeToken")
    print("  참조 사고: 2020 dForce 패턴\n")
    print("  명령어: slither . --detect unprotected-upgrade (OZ v5 제한으로 대체 분석)\n")

    vuln = fs.get("VulnerableUpgradeToken", [])
    safe = fs.get("DepositToken", [])

    print("  [검사] _authorizeUpgrade() 접근 제어 modifier")
    v_auth = [f for f in vuln if "_authorizeUpgrade" in f["name"] and f["vis"] == "internal"]
    s_auth = [f for f in safe if "_authorizeUpgrade" in f["name"] and f["vis"] == "internal"]

    for f in v_auth:
        if f["mods"] == "[]":
            fail(f'VulnerableUpgradeToken._authorizeUpgrade  mods={f["mods"]}  → 누구나 업그레이드 가능!')
        else:
            ok(f'VulnerableUpgradeToken._authorizeUpgrade  mods={f["mods"]}')
        break
    for f in s_auth:
        if f["mods"] != "[]":
            ok(f'DepositToken._authorizeUpgrade            mods={f["mods"]}')
            break

    print("\n  [취약 공격 흐름]")
    print("    1. 공격자가 악의적 Implementation 배포 (자기 자신을 admin으로)")
    print("    2. upgradeToAndCall(악의적Impl, '') 호출 → _authorizeUpgrade 통과 (빈 함수)")
    print("    3. 컨트랙트 전체 탈취 완료")
    print("\n  [수정 방법]")
    print("    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}")
    print("    + UPGRADER_ROLE은 반드시 TimelockController + 멀티시그 조합으로 운영")

# ── Scenario 5: freeze 우회 ─────────────────────────────────────────────────

def s5(fs):
    sec(5, "freeze 우회 — VulnerableFreezeToken")
    print("  transfer()에만 freeze 검사, approve+transferFrom으로 우회 가능\n")

    vuln = fs.get("VulnerableFreezeToken", [])
    safe = fs.get("DepositToken", [])

    def count_fn(rows, name_key):
        return [f for f in rows if name_key in f["name"]]

    v_transfers     = count_fn(vuln, "transfer(address,uint256)")
    v_transferfroms = count_fn(vuln, "transferFrom(")

    print("  [검사 1] transfer() 오버라이드 여부")
    if len(v_transfers) > 2:
        fail(f'VulnerableFreezeToken.transfer    항목 수={len(v_transfers)}  → 커스텀 오버라이드 (freeze 체크 있음)')
    else:
        note(f'VulnerableFreezeToken.transfer    항목 수={len(v_transfers)}')

    print("\n  [검사 2] transferFrom() 오버라이드 여부")
    if len(v_transferfroms) <= 2:
        fail(f'VulnerableFreezeToken.transferFrom 항목 수={len(v_transferfroms)}  → 오버라이드 없음! freeze 우회 가능')
    else:
        ok(f'VulnerableFreezeToken.transferFrom 항목 수={len(v_transferfroms)}  → 오버라이드 존재')

    print("\n  [공격 시나리오]")
    print("    1. AML 의심 계정 A가 freeze 당하기 전에 approve(B, 전 잔액)")
    print("    2. A가 freeze됨 (transfer 차단)")
    print("    3. B가 transferFrom(A, B, 전 잔액) 호출 → 성공! (freeze 검사 없음)")
    print("    4. 동결이 무력화됨 → 규제 준수 실패, 라이선스 위험")
    print("\n  [수정 방법] transfer 오버라이드 대신 _update 단일 오버라이드:")
    print("    function _update(address from, address to, uint256 value) internal override {")
    print("        if (from != address(0) && _frozen[from]) revert AccountFrozen(from);")
    print("        super._update(from, to, value);")
    print("    }")

# ── main ────────────────────────────────────────────────────────────────────

def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "all"

    print("\n" + "█" * 62)
    print("  Slither 보안 분석 데모 — 2026 KISA 예금토큰 강의")
    print("█" * 62)
    print(f"\n  프로젝트: {BASE}")
    print("  Slither 버전:", end=" ")
    v = subprocess.run(["slither", "--version"], capture_output=True, text=True)
    print(v.stdout.strip() or v.stderr.strip())

    # function-summary는 한 번만 파싱 (컴파일 1회)
    print("\n  [function-summary 파싱 중 — 약 20초 소요]", flush=True)
    fs = get_fs()

    run_all = (arg == "all")

    if run_all or arg == "0": s0()
    if run_all or arg == "1": s1(fs)
    if run_all or arg == "2": s2()
    if run_all or arg == "3": s3(fs)
    if run_all or arg == "4": s4(fs)
    if run_all or arg == "5": s5(fs)

    print("\n" + "═" * 62)
    print("  분석 완료")
    print("═" * 62 + "\n")

if __name__ == "__main__":
    main()
