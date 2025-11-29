# :Dket Smart Contracts

**:Dket(디켓)** 의 블록체인 스마트 컨트랙트 리포지토리입니다.
이 프로젝트는 **Solidity 0.8.30**으로 작성되었으며, NFT 티켓 발행, 리세일(Resale), 그리고 영지식 증명(ZKP) 검증 로직을 포함하고 있습니다.

모든 컴파일과 배포는 **[Remix IDE](https://remix.ethereum.org/)** 환경에서 수행되었습니다.

## 🌐 Deployed Addresses (Sepolia Testnet)

| Contract | Address | Note |
| :--- | :--- | :--- |
| **DketNFT** | `0xF0A34dd5e4713C582e196B3eadc8D38DeeE07d4E` | [View on Etherscan](https://sepolia.etherscan.io/address/0xF0A34dd5e4713C582e196B3eadc8D38DeeE07d4E) |
| **DketResale** | `0x00dD90DAf34A16c62846542bA0bF83D85E794515` | [View on Etherscan](https://sepolia.etherscan.io/address/0x00dD90DAf34A16c62846542bA0bF83D85E794515) |

---

## 🛠 Tech Stack

### Language & Framework
* **Solidity 0.8.30** (Compiler Version)
* **Remix IDE** (Compilation & Deployment)

### Libraries
* **OpenZeppelin**: ERC721URIStorage, Ownable, EIP712, ReentrancyGuard, ECDSA
* **Chainlink VRF (v2)**: 온체인 난수 생성 (Randomness)
* **SnarkJS**: ZKP Verifier Contract Generation (Plonk)

---

## 📂 Project Structure

이 리포지토리는 배포 스크립트 없이 순수 컨트랙트 파일(`demo/contracts/`)로만 구성되어 있습니다.

```bash
dket-blockchain
└── demo
    └── contracts
        ├── DketNFT.sol            # NFT 티켓 발행 및 VRF 연동
        ├── DketResale.sol         # 2차 거래(Resale) 및 EIP-712 서명 검증
        ├── VerifierAdapter.sol    # 여러 ZKP Verifier를 통합 관리하는 어댑터
        ├── IVerifier.sol          # Verifier 인터페이스
        ├── winVerifier_plonk.sol  # 당첨 증명(WinProof) 검증 컨트랙트
        └── ownVerifier_plonk.sol  # 소유 증명(OwnProof) 검증 컨트랙트
````

-----

## 🚀 Deployment Guide (Remix IDE)

### 1\. Setup (Compiler Settings)

  * **Compiler Version:** `0.8.30`
  * **Optimization:** **Enabled** (Runs: 200)
      * `DketNFT.sol` 등 주요 컨트랙트 배포 시 가스 최적화를 위해 이 설정이 필수적입니다.

### 2\. Deployment Order (Dependency Chain)

컨트랙트 간 의존성이 있으므로 반드시 아래 순서대로 배포해야 합니다.

#### Step 1: ZKP Verifiers 배포

  * `winVerifier_plonk.sol` 배포 -\> **Address(WinVerifier)** 획득
  * `ownVerifier_plonk.sol` 배포 -\> **Address(OwnVerifier)** 획득

#### Step 2: VerifierAdapter 배포

  * Constructor Input: `_winVerifier`, `_ownVerifier` 주소 입력
  * **Address(VerifierAdapter)** 획득

#### Step 3: DketNFT 배포 (Main Contract)

  * **Optimization 설정 확인** 후 배포.
  * Constructor Input:
      * `_subscriptionId`: Chainlink VRF Subscription ID만 입력 (나머지 설정은 컨트랙트 내장)
  * **Address(DketNFT)** 획득

#### Step 4: DketResale 배포

  * Constructor Input: `Address(DketNFT)`

### 3\. Post-Deployment Setup (Permission)

배포 후, 리세일 컨트랙트가 NFT 소유권을 이전할 수 있도록 권한을 설정해야 합니다.

1.  **DketNFT**: `setTransferAgent(Address(DketResale), true)` 호출
2.  **DketNFT**: `setVerifier(Address(VerifierAdapter))` 호출 (ZKP 검증기 연결)

-----

## 🔑 Key Contracts & Logic

### 1\. DketNFT.sol

  * **Fair Randomness:** Chainlink VRF를 통해 난수를 생성하여 공정성을 확보합니다. (메타데이터 셔플링은 이 난수를 시드로 사용하여 오프체인에서 수행됩니다.)
  * **Lazy Minting & Transfer:** 관리자가 선민팅(Pre-minting)한 티켓을 보관하고 있다가, 검증을 통과한 **실제 구매자(Verified Buyer)** 에게 티켓을 전송합니다.
      * **추첨 판매:** ZKP(`WinProof`)를 제출한 당첨자에게 전송.
      * **잔여석 판매:** 당첨자 결제 종료 후, 일반 구매자에게 전송.

### 2\. DketResale.sol

  * **System-Authorized Trading (EIP-712):** 모든 리세일 거래는 시스템(백엔드)이 생성한 서명을 컨트랙트가 검증하는 방식으로 이루어집니다.
      * **Race Condition 방지:** 시스템이 거래 순서를 제어하여 중복 구매를 방지합니다.
      * **외부 거래 차단:** 오픈씨(OpenSea) 등 외부 마켓이 아닌, 오직 :Dket 시스템을 통한 거래만 승인합니다.
  * **Price Cap & Royalty:** 거래 가격은 원가의 120% 상한이 적용되며, 수익의 10%는 자동으로 개최자에게 정산됩니다.

### 3\. VerifierAdapter.sol & \*\_plonk.sol

  * **Zero-Knowledge Proof:** `winVerifier`는 추첨 당첨 사실을, `ownVerifier`는 티켓 실소유 사실을 검증합니다.
  * **Privacy:** 개인정보 노출 없이 Merkle Root와 Nullifier Hash 만으로 유효성을 검증합니다.

-----

## 📜 License

This project is licensed under the MIT License.
