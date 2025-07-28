// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

type TokenInfo is uint256;

library TokenInfoLibrary {
    uint8 internal constant MAX_LP = 4;

    function encode(address ipaId, int24[] memory startTickList) internal pure returns (TokenInfo tokenInfo) {
        assembly {
            let length := mload(startTickList)
            tokenInfo := ipaId
            for { let i := 0 } lt(i, length) {} {
                i := add(i, 1)
                let startTick := mload(add(startTickList, mul(i, 0x20)))
                /// @dev 0x777777 is a sentinel value used to represent tick 0, since 0 indicates empty/no tick
                if eq(startTick, 0) { startTick := 0x777777 }
                tokenInfo := or(tokenInfo, shl(add(136, mul(i, 24)), and(0xffffff, startTick)))
            }
        }
    }

    function decode(TokenInfo tokenInfo) internal pure returns (address ipaId, int24[] memory startTickList) {
        startTickList = new int24[](MAX_LP);
        assembly {
            ipaId := and(tokenInfo, 0xffffffffffffffffffffffffffffffffffffffff)
            tokenInfo := shr(160, tokenInfo)
            let length := 0
            for { let startTick := and(0xffffff, tokenInfo) } gt(startTick, 0) { startTick := and(0xffffff, tokenInfo) }
            {
                length := add(length, 1)
                /// @dev 0x777777 is a sentinel value used to represent tick 0, since 0 indicates empty/no tick
                if eq(startTick, 0x777777) { startTick := 0 }
                mstore(add(startTickList, mul(0x20, length)), startTick)
                tokenInfo := shr(24, tokenInfo)
            }
            mstore(startTickList, length)
        }
    }

    function updateTokenInfo(mapping(address token => TokenInfo) storage map, address token, address ipaId) internal {
        TokenInfo tokenInfo = map[token];
        assembly {
            tokenInfo := or(and(tokenInfo, 0xffffffffffffffffffffffff0000000000000000000000000000000000000000), ipaId)
        }
        map[token] = tokenInfo;
    }
}
