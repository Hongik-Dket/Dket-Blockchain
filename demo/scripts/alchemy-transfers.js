import { Network, Alchemy } from 'alchemy-sdk';
import dotenv from 'dotenv';

dotenv.config(); // .env 파일 로드

const settings = {
  apiKey: process.env.ALCHEMY_API_KEY, // 보안상 API 키는 환경 변수에서 가져오는 게 좋음!
  network: Network.ETH_MAINNET, // 이더리움 메인넷
};

const alchemy = new Alchemy(settings);

async function getSentTransactions() {
  try {
    const response = await alchemy.core.getAssetTransfers({
      fromBlock: "0x0",
      fromAddress: "0x994b342dd87fc825f66e51ffa3ef71ad818b6893",
      category: ["erc721", "external", "erc20"], // NFT, ETH 전송, ERC-20 토큰 모두 조회
    });

    console.log("📌 해당 주소의 트랜잭션 내역:", response);
  } catch (error) {
    console.error("🚨 Alchemy 요청 실패:", error);
  }
}

// 실행
getSentTransactions();