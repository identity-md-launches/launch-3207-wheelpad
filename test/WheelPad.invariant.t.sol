// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {WheelPad} from "../src/WheelPad.sol";

/// @dev A separate balance/allowance model exercises successful and rejected sequences.
contract WheelPadHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WheelPad private immutable token;
    address[4] public actors;
    mapping(address => uint256) public modelBalance;
    mapping(address => mapping(address => uint256)) public modelAllowance;

    constructor(WheelPad token_) {
        token = token_;
        actors[0] = makeAddr("model alice");
        actors[1] = makeAddr("model bob");
        actors[2] = makeAddr("model carol");
        actors[3] = makeAddr("model dave");
        modelBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool exceedsBalance) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = exceedsBalance ? modelBalance[from] + 1 : bound(amountSeed, 0, modelBalance[from]);

        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertEq(success, !exceedsBalance, "transfer success disagrees with the model");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            modelBalance[from] -= amount;
            modelBalance[to] += amount;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = unlimited ? type(uint256).max : bound(amountSeed, 0, SUPPLY);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        modelAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool exceedsLimit)
        external
    {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = modelAllowance[from][spender];
        uint256 limit = modelBalance[from] < allowed ? modelBalance[from] : allowed;
        uint256 amount = exceedsLimit ? limit + 1 : bound(amountSeed, 0, limit);

        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        assertEq(success, !exceedsLimit, "transferFrom success disagrees with the model");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            modelBalance[from] -= amount;
            modelBalance[to] += amount;
            if (allowed != type(uint256).max) {
                modelAllowance[from][spender] -= amount;
            }
        }
    }
}

contract WheelPadInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WheelPad private token;
    WheelPadHandler private handler;

    function setUp() public {
        token = new WheelPad();
        handler = new WheelPadHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_TotalSupplyAndAggregateBalancesStayFixed() public view {
        uint256 aggregate;
        for (uint256 i; i < 4; ++i) {
            aggregate += token.balanceOf(handler.actors(i));
        }
        assertEq(aggregate, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_BalancesAndAllowancesMatchIndependentModel() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.modelBalance(owner));
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.modelAllowance(owner, spender));
            }
        }
    }
}
