// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

library UniV2Math {
    /// sqrt babylonian algo
    function sqrt(uint192 y) internal pure returns (uint192 z) {
        if (y > 3) {
            z = y;
            uint192 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
