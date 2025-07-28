// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {TokenInfoLibrary, TokenInfo} from "../../src/lib/TokenInfo.sol";

contract TokenInfoTest is Test {
    using TokenInfoLibrary for TokenInfo;

    function testEncodeDecode() public pure {
        TokenInfo info;
        int24[] memory startTickList = new int24[](3);
        startTickList[0] = int24(1);
        startTickList[1] = int24(2);
        startTickList[2] = int24(3);

        info = TokenInfoLibrary.encode(address(0x123), startTickList);
        assertEq(TokenInfo.unwrap(info), 0x0000000000030000020000010000000000000000000000000000000000000123);

        (address _ipaId, int24[] memory _startTickList) = info.decode();
        assertEq(_ipaId, address(0x123));
        assertEq(_startTickList.length, 3);
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(_startTickList[i], startTickList[i]);
        }

        startTickList[0] = int24(-1);
        startTickList[1] = int24(2);
        startTickList[2] = int24(-3);

        info = TokenInfoLibrary.encode(address(0x123), startTickList);
        assertEq(
            bytes32(TokenInfo.unwrap(info)), bytes32(0x000000fffffd000002ffffff0000000000000000000000000000000000000123)
        );

        (_ipaId, _startTickList) = info.decode();
        assertEq(_ipaId, address(0x123));
        assertEq(_startTickList.length, 3);
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(_startTickList[i], startTickList[i]);
        }

        startTickList[0] = int24(1);
        startTickList[1] = int24(0);
        startTickList[2] = int24(-1);

        info = TokenInfoLibrary.encode(address(0x123), startTickList);
        assertEq(
            bytes32(TokenInfo.unwrap(info)), bytes32(0x000000ffffff7777770000010000000000000000000000000000000000000123)
        );

        (_ipaId, _startTickList) = info.decode();
        assertEq(_ipaId, address(0x123));
        assertEq(_startTickList.length, 3);
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(_startTickList[i], startTickList[i]);
        }
    }
}
