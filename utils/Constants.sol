// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Constants {
    // RPC URLs
    string public constant STORY_MAINNET_RPC = "https://mainnet.storyrpc.io";
    string public constant STORY_TESTNET_RPC = "https://aeneid.storyrpc.io";
        
    // story main net
    address public constant WETH = 0x1514000000000000000000000000000000000000;
    
    // Same addresses on both mainnet and testnet (AENEID)
    address public constant REGISTRATION_WORKFLOWS = 0xbe39E1C756e921BD25DF86e7AAa31106d1eb0424;
    address public constant IP_ASSET_REGISTRY = 0x77319B4031e6eF1250907aa00018B8B1c67a244b; 
    address public constant LICENSE_ATTACHMENT_WORKFLOWS = 0xcC2E862bCee5B6036Db0de6E06Ae87e524a79fd8;
    address public constant LICENSING_MODULE = 0x04fbd8a2e56dd85CFD5500A4A4DfA955B9f1dE6f;
    address public constant PILICENSE_TEMPLATE = 0x2E896b0b2Fdb7457499B56AAaA4AE55BCB4Cd316;
    address public constant ROYALTY_MODULE = 0xD2f60c40fEbccf6311f8B47c4f2Ec6b040400086;
    
    //https://github.com/0xstoryhunt/default-list/tree/main/src/constants
    // Mainnet addresses
    address public constant V3_DEPLOYER = 0x74014BbbE2702274c01acA0BD0c5389779f5A050;
    address public constant V3_FACTORY = 0xa111dDbE973094F949D78Ad755cd560F8737B7e2;
    address public constant SWAP_ROUTER = 0x1062916B1Be3c034C1dC6C26f682Daf1861A3909;
    address public constant QUOTER_V2 = 0x1434Ae03CfA29d314da73fC18013CCd04f100af6;
    address public constant NFT_POSITION_MANAGER = 0xb3823797B00ef062Aaa1c4B3c60149AFc6CCf7a3;

    // Testnet (AENEID) addresses
    address public constant V3_DEPLOYER_AENEID = 0x3D9300D311BA04EB3351663676cEE0748473d9A0;
    address public constant V3_FACTORY_AENEID = 0xB0d76e6C7aA7a78A00Af1A1083B4732a488700b4;
    address public constant SWAP_ROUTER_AENEID = 0x21bc5d68F6DA0E43A90f078bcCb04feddEdcC93b;
    address public constant QUOTER_V2_AENEID = 0x72897A551d217848E15c7d9f5981BfAd49b46969;
    address public constant NFT_POSITION_MANAGER_AENEID = 0xeE96404216dd0D6dbbe197ED1066B5CD414ef3b9;

    
    // IPWorld mainnet contracts 
    address public constant IPWORLD = 0xd0EFb8Cd4c7a3Eefe823Fe963af9661D8F0CB745;
    address public constant IPOWNER_VAULT = 0x81336266Ba5F26B8AFf7d2b2A2305F52A39292b2;
    
    // Example old token for testing
    address public constant SONA_TOKEN = 0x02353a3BD5c9668159cF9Fd54AC61b03212FCf41;
    
    // IPWorld deployment
    address public constant OWNER = 0x527b390cD37643F10dA8B8Dca980FA46EEe2f58b;
    address public constant EXPECTED_SIGNER = 0x527b390cD37643F10dA8B8Dca980FA46EEe2f58b;
    
    // IPWorld deployment parameters
    uint24 public constant BURN_SHARE = 500_000;
    uint24 public constant IP_OWNER_SHARE = 200_000;
    uint24 public constant BUYBACK_SHARE = 600_000;
    uint256 public constant BID_WALL_AMOUNT = 20 ether;
    uint64 public constant VESTING_DURATION = 90 days;

    // Licensing URL
    string public constant LICENSING_URL = "https://github.com/ipdotworld/protocol/blob/main/ip-token-license-v1.0.pdf";

    // IPWorld treasury
    address public constant TREASURY = 0x59E9a4942cfdB1974f6e9C55e105429698E7E7Ed;

    // NFT Collection Configuration
    string public constant NFT_NAME = "IP WORLD";
    string public constant NFT_SYMBOL = "IPWRLD";
    string public constant NFT_BASE_URI = "https://prod.api.ip.world/api/v1/ipas/metadata/";
    string public constant NFT_CONTRACT_URI = "https://prod.api.ip.world/api/v1/ipas/metadata/contract";
}

