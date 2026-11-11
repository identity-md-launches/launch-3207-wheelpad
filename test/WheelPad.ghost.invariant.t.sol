// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {WheelPad} from "../src/WheelPad.sol";

/// @dev Drives the token from a wider actor set than the base invariant suite: the deployer
/// contract, the token's own address and arbitrary fuzzed addresses, with both valid and invalid
/// calls (zero addresses, over-balance, over-allowance) and arbitrary calldata. It never reverts
/// itself; it records what succeeded in ghost variables and checks each outcome against the rules.
contract WheelPadGhostHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WheelPad internal immutable token;
    address[] internal actors;
    mapping(address => bool) internal known;

    // Ghosts.
    mapping(address => uint256) public ghostIn;
    mapping(address => uint256) public ghostOut;
    uint256 public ghostSuccessfulMoves;
    uint256 public ghostRejected;
    uint256 public ghostUnexpectedSuccess;
    uint256 public ghostAllowanceViolations;

    constructor(WheelPad token_, address deployer) {
        token = token_;
        _add(deployer);
        _add(address(token_));
        _add(makeAddr("ghost alice"));
        _add(makeAddr("ghost bob"));
        _add(makeAddr("ghost carol"));
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _add(address a) internal {
        if (a == address(0) || known[a]) return;
        known[a] = true;
        actors.push(a);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// Adds a fuzzed address to the actor set (bounded so the sum check stays cheap).
    function addActor(address a) external {
        if (actors.length < 12) _add(a);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, uint8 mode) external {
        address from = _actor(fromSeed);
        address to = mode % 4 == 3 ? address(0) : _actor(toSeed);
        uint256 bal = token.balanceOf(from);
        uint256 amount;
        if (mode % 4 == 1) amount = bound(amountSeed, bal + 1, type(uint256).max);
        else amount = bound(amountSeed, 0, bal);
        bool shouldSucceed = to != address(0) && amount <= bal;
        uint256 toBefore = token.balanceOf(to);

        vm.prank(from);
        (bool ok, bytes memory ret) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        if (ok != shouldSucceed) ++ghostUnexpectedSuccess;
        if (!ok) {
            ++ghostRejected;
            if (token.balanceOf(from) != bal) ++ghostUnexpectedSuccess;
            return;
        }
        if (!abi.decode(ret, (bool))) ++ghostUnexpectedSuccess;
        _record(from, to, amount, bal, toBefore);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool zeroSpender) external {
        address owner = _actor(ownerSeed);
        address spender = zeroSpender ? address(0) : _actor(spenderSeed);
        uint256 bal = token.balanceOf(owner);
        vm.prank(owner);
        (bool ok,) = address(token).call(abi.encodeCall(token.approve, (spender, amount)));
        if (ok == zeroSpender) ++ghostUnexpectedSuccess;
        if (ok && token.allowance(owner, spender) != amount) ++ghostAllowanceViolations;
        if (!ok) ++ghostRejected;
        if (token.balanceOf(owner) != bal) ++ghostUnexpectedSuccess;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed, uint8 mode)
        external
    {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = mode % 5 == 4 ? address(0) : _actor(toSeed);
        uint256 bal = token.balanceOf(from);
        uint256 allowed = token.allowance(from, spender);
        uint256 limit = bal < allowed ? bal : allowed;
        uint256 amount;
        if (mode % 5 == 1 && limit < type(uint256).max) amount = bound(amountSeed, limit + 1, type(uint256).max);
        else amount = bound(amountSeed, 0, limit);
        bool shouldSucceed = to != address(0) && amount <= limit;
        uint256 toBefore = token.balanceOf(to);

        vm.prank(spender);
        (bool ok, bytes memory ret) = address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        if (ok != shouldSucceed) ++ghostUnexpectedSuccess;
        if (!ok) {
            ++ghostRejected;
            if (token.allowance(from, spender) != allowed || token.balanceOf(from) != bal) {
                ++ghostAllowanceViolations;
            }
            return;
        }
        if (!abi.decode(ret, (bool))) ++ghostUnexpectedSuccess;
        uint256 expectedAllowance = allowed == type(uint256).max ? allowed : allowed - amount;
        if (token.allowance(from, spender) != expectedAllowance) ++ghostAllowanceViolations;
        _record(from, to, amount, bal, toBefore);
    }

    /// Arbitrary calldata from an arbitrary actor must not move anything unless it is one of the
    /// three ERC-20 mutators, which the functions above model.
    function poke(uint256 callerSeed, bytes calldata data) external {
        if (data.length >= 4) {
            bytes4 sel = bytes4(data[:4]);
            if (sel == token.transfer.selector || sel == token.transferFrom.selector || sel == token.approve.selector) {
                return;
            }
        }
        address caller = _actor(callerSeed);
        uint256 before = token.balanceOf(caller);
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        ok;
        if (token.balanceOf(caller) != before || token.totalSupply() != SUPPLY) ++ghostUnexpectedSuccess;
    }

    function _record(address from, address to, uint256 amount, uint256 fromBefore, uint256 toBefore) internal {
        ++ghostSuccessfulMoves;
        if (from != to) {
            ghostOut[from] += amount;
            ghostIn[to] += amount;
            if (token.balanceOf(from) != fromBefore - amount || token.balanceOf(to) != toBefore + amount) {
                ++ghostUnexpectedSuccess;
            }
        } else if (token.balanceOf(from) != fromBefore) {
            ++ghostUnexpectedSuccess;
        }
    }
}

contract WheelPadGhostInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WheelPad private token;
    WheelPadGhostHandler private handler;

    function setUp() public {
        // This test contract is the deployer and actor 0, so it starts with the whole supply.
        token = new WheelPad();
        handler = new WheelPadGhostHandler(token, address(this));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_SupplyIsFixedAndFullyAccountedFor() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.actorAt(i));
        }
        assertEq(sum, SUPPLY, "tokens left the tracked actor set");
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// Every balance equals its starting balance plus ghost inflows minus ghost outflows.
    function invariant_BalancesMatchGhostFlows() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            address a = handler.actorAt(i);
            uint256 start = i == 0 ? SUPPLY : 0;
            assertEq(token.balanceOf(a) + handler.ghostOut(a), start + handler.ghostIn(a));
        }
    }

    function invariant_NoCallBrokeTheRules() public view {
        assertEq(handler.ghostUnexpectedSuccess(), 0, "a call succeeded or failed against the rules");
        assertEq(handler.ghostAllowanceViolations(), 0, "an allowance moved against the rules");
    }

    /// Guards against a vacuous run: each sequence must have exercised both accepted and rejected calls.
    function afterInvariant() public view {
        assertGt(handler.ghostSuccessfulMoves(), 0, "no transfer succeeded in this sequence");
        assertGt(handler.ghostRejected(), 0, "no invalid call was attempted in this sequence");
    }

    function invariant_NativeCurrencyNeverHeld() public view {
        assertEq(address(token).balance, 0);
    }
}

