https://github.com/thyoondev/deposit-token-lecture
# 컴파일
npx hardhat compile

# 테스트 (32케이스)
npx hardhat test

# 커버리지
npx hardhat coverage

# 가스 리포트 포함 테스트
REPORT_GAS=true npx hardhat test

# 특정 그룹만
npx hardhat test --grep "mint"
npx hardhat test --grep "freeze|frozen"

로컬 노드 배포는 터미널 두 개 필요합니다:

# 터미널 1
npx hardhat node

# 터미널 2
npx hardhat run scripts/deploy.js
