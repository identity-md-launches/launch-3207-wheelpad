// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WheelPad} from "../src/WheelPad.sol";

/// @dev Deploys the token and runs the whole launch distribution in one call, the way a launch
/// factory does in a single transaction, and records what each step delivered.
contract WheelPadLaunchFixture {
    WheelPad public token;
    uint256 public deployerBalanceAfterConstructor;

    function launch(bytes32 salt, address distributor, address pool, address remainder, uint256 poolBps)
        external
        returns (WheelPad deployed)
    {
        deployed = new WheelPad{salt: salt}();
        token = deployed;
        deployerBalanceAfterConstructor = deployed.balanceOf(address(this));
        uint256 supply = deployed.totalSupply();
        uint256 swarm = supply / 10;
        uint256 seeded = supply * poolBps / 10_000;
        require(deployed.transfer(distributor, swarm), "swarm transfer returned false");
        require(deployed.transfer(pool, seeded), "seed transfer returned false");
        require(deployed.transfer(remainder, deployed.balanceOf(address(this))), "remainder transfer returned false");
    }

    function predict(bytes32 salt) external view returns (address) {
        bytes32 hash =
            keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(type(WheelPad).creationCode)));
        return address(uint160(uint256(hash)));
    }
}

/// @dev Edge cases and failure paths not covered by the base unit suite.
contract WheelPadEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WheelPad private token;
    address private alice = makeAddr("edge alice");
    address private bob = makeAddr("edge bob");
    address private spender = makeAddr("edge spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new WheelPad();
    }

    // ---------------------------------------------------------------- launch flow, one transaction

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_LaunchFlowInOneCallDeliversExactAmounts(bytes32 salt, uint256 rawBps) public {
        uint256 poolBps = bound(rawBps, 0, 9_000);
        address distributor = makeAddr("edge distributor");
        address pool = makeAddr("edge pool manager");
        address remainder = makeAddr("edge remainder");
        WheelPadLaunchFixture fixture = new WheelPadLaunchFixture();
        address predicted = fixture.predict(salt);

        WheelPad launched = fixture.launch(salt, distributor, pool, remainder, poolBps);

        assertEq(address(launched), predicted, "CREATE2 address is not deterministic");
        assertEq(fixture.deployerBalanceAfterConstructor(), SUPPLY, "constructor did not mint all to deployer");
        assertEq(launched.balanceOf(distributor), SUPPLY / 10, "distributor arrived short");
        assertEq(launched.balanceOf(pool), SUPPLY * poolBps / 10_000, "pool seed arrived short");
        assertEq(
            launched.balanceOf(remainder), SUPPLY - SUPPLY / 10 - SUPPLY * poolBps / 10_000, "remainder arrived short"
        );
        assertEq(launched.balanceOf(address(fixture)), 0, "factory kept tokens");
        assertEq(launched.totalSupply(), SUPPLY, "supply changed during launch");
    }

    function test_SameSaltCannotRedeployOverAnExistingToken() public {
        WheelPadLaunchFixture fixture = new WheelPadLaunchFixture();
        bytes32 salt = keccak256("edge salt");
        fixture.launch(salt, alice, bob, spender, 5_000);
        vm.expectRevert();
        fixture.launch(salt, alice, bob, spender, 5_000);
    }

    function test_EachDeploymentIsIndependent() public {
        vm.prank(alice);
        WheelPad second = new WheelPad();
        assertEq(second.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(second.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        vm.prank(alice);
        second.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 0);
    }

    // ---------------------------------------------------------------- boundaries

    function test_TransferExactBalanceThenOneWeiMoreFails() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
    }

    function test_TransferFromExactAllowanceThenOneWeiMoreFails() public {
        token.approve(spender, 7);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 7));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 7);
    }

    function test_MaxAllowanceCannotExceedBalance() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(spender);
        token.transferFrom(alice, bob, 11);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 10);
    }

    function test_MaxMinusOneAllowanceIsDecremented() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 5);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 6);
    }

    function test_SpendingAllowanceDoesNotEmitApproval() public {
        token.approve(spender, 10);
        vm.recordLogs();
        vm.prank(spender);
        token.transferFrom(address(this), alice, 4);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "transferFrom emitted more than the Transfer event");
        assertEq(logs[0].topics[0], Transfer.selector);
    }

    function test_SelfApprovalAllowsOwnerTransferFrom() public {
        token.approve(address(this), 3);
        assertTrue(token.transferFrom(address(this), alice, 3));
        assertEq(token.allowance(address(this), address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function test_ApprovingTokenContractGivesItNoPower() public {
        token.approve(address(token), SUPPLY);
        token.transfer(address(token), 100);
        // The token holds no code path that spends an allowance or moves its own balance.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 100));
        token.transferFrom(address(token), alice, 100);
        assertEq(token.balanceOf(address(token)), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100);
    }

    function test_ZeroAddressCannotBeImpersonatedToSpend() public {
        token.transfer(alice, 50);
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.transfer(alice, 0);
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.approve(alice, 1);
        assertEq(token.balanceOf(alice), 50);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FailedCallsLeaveNoTrace() public {
        token.approve(spender, 5);
        vm.recordLogs();
        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (address(this), alice, 6)));
        assertFalse(ok);
        vm.prank(alice);
        (ok,) = address(token).call(abi.encodeCall(token.transfer, (bob, 1)));
        assertFalse(ok);
        (ok,) = address(token).call(abi.encodeCall(token.approve, (address(0), 1)));
        assertFalse(ok);
        assertEq(vm.getRecordedLogs().length, 0, "a reverted call emitted an event");
        assertEq(token.allowance(address(this), spender), 5);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_MalformedCalldataIsRejected() public {
        // transfer selector with a truncated argument list must not succeed.
        (bool ok,) = address(token).call(abi.encodePacked(token.transfer.selector, bytes20(alice)));
        assertFalse(ok);
        (ok,) = address(token).call(abi.encodePacked(token.transfer.selector));
        assertFalse(ok);
        // a dirty upper word in the address argument is rejected by the ABI decoder.
        (ok,) = address(token).call(abi.encodePacked(token.transfer.selector, uint256(type(uint256).max), uint256(1)));
        assertFalse(ok);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RuntimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------- properties

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ArbitraryCalldataCannotChangeSupplyOrBalances(address caller, bytes calldata data) public {
        vm.assume(caller != address(this));
        token.transfer(alice, 1_000 ether);
        bytes4 sel = data.length >= 4 ? bytes4(data[:4]) : bytes4(0);
        // Exclude the three ERC-20 entrypoints whose state changes are legitimate and modelled elsewhere.
        if (sel == token.transfer.selector || sel == token.transferFrom.selector || sel == token.approve.selector) {
            return;
        }
        vm.prank(caller);
        (bool ok, bytes memory ret) = address(token).call(data);
        ok;
        ret;
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1_000 ether);
        assertEq(token.balanceOf(caller), caller == alice ? 1_000 ether : 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TransferBetweenArbitraryHolders(address from, address to, uint256 rawSeed, uint256 rawAmount)
        public
    {
        from = address(uint160(bound(uint160(from), 1, type(uint160).max)));
        to = address(uint160(bound(uint160(to), 1, type(uint160).max)));
        uint256 seeded = bound(rawSeed, 0, SUPPLY);
        token.transfer(from, seeded);
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 amount = bound(rawAmount, 0, fromBefore);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(from, to, amount);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));

        if (from == to) {
            assertEq(token.balanceOf(from), fromBefore);
        } else {
            assertEq(token.balanceOf(from), fromBefore - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ApproveOverwritesRatherThanAccumulates(uint256 first, uint256 second) public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, first);
        token.approve(spender, first);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, second);
        token.approve(spender, second);
        assertEq(token.allowance(address(this), spender), second);
        assertEq(token.allowance(spender, address(this)), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_InfiniteAllowanceSurvivesAnySpend(uint256 rawAmount, uint256 rawSecond) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 second = bound(rawSecond, 0, SUPPLY - amount);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        token.transferFrom(address(this), alice, amount);
        token.transferFrom(address(this), bob, second);
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(address(this)), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TransferFromRevertsWhenBalanceBelowAllowance(uint256 rawBalance, uint256 rawAmount) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, balance + 1, SUPPLY);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), SUPPLY, "failed transferFrom consumed allowance");
        assertEq(token.balanceOf(alice), balance);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_NonHolderCannotMoveAnything(address stranger, uint256 rawAmount) public {
        vm.assume(stranger != address(this) && stranger != address(0));
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        token.transferFrom(address(this), stranger, amount);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, stranger, 0, amount));
        token.transfer(address(this), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }
}
