// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {WheelPad} from "../../src/WheelPad.sol";

/// @dev Local deployment fixture; this is not a launch application contract.
contract WheelPadFactory {
    function deploy(bytes32 salt) external returns (WheelPad) {
        return new WheelPad{salt: salt}();
    }

    function move(WheelPad token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}
