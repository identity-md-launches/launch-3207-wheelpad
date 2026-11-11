// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WheelPad} from "../src/WheelPad.sol";
import {WheelPadFactory} from "./helpers/WheelPadFactory.sol";

contract WheelPadTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WheelPad private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new WheelPad();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "WheelPad");
        assertEq(token.symbol(), "WHEELPAD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsMintEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new WheelPad();
    }

    function test_FactoryReceivesEntireSupplyAndLaunchTransfersAreExact() public {
        WheelPadFactory factory = new WheelPadFactory();
        WheelPad launched = factory.deploy(keccak256("WheelPad launch fixture"));
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);

        address distributor = makeAddr("distributor fixture");
        address pool = makeAddr("pool fixture");
        address remainder = makeAddr("remainder fixture");
        assertTrue(factory.move(launched, distributor, SUPPLY / 10));
        assertTrue(factory.move(launched, pool, SUPPLY * 8 / 10));
        assertTrue(factory.move(launched, remainder, SUPPLY / 10));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(launched.balanceOf(remainder), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, SUPPLY / 10));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), SUPPLY / 10);

        // Exercise exact transfers in both directions; this is not a DEX integration test.
        vm.prank(pool);
        assertTrue(launched.transfer(bob, 100 ether));
        vm.prank(bob);
        assertTrue(launched.transfer(pool, 100 ether));
        assertEq(launched.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndReturnsTrue() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 15 ether);
        assertTrue(token.transfer(alice, 15 ether));
        assertEq(token.balanceOf(alice), 15 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 15 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToTokenContractDoesNotBurn() public {
        assertTrue(token.transfer(address(token), 1 ether));
        assertEq(token.balanceOf(address(token)), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenTransferExceedsBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenSelfTransferExceedsBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertWhenTransferIsMaximumUint() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_RevertWhenTransferToZeroIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalEmitsEventAndDoesNotMoveTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 50 ether);
        assertTrue(token.approve(spender, 50 ether));
        assertEq(token.allowance(address(this), spender), 50 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ApprovalCanBeReplacedAndRevoked() public {
        token.approve(spender, 100);
        token.approve(spender, 30);
        assertEq(token.allowance(address(this), spender), 30);
        token.approve(spender, 0);
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function test_ApprovalIsIndependentOfBalanceAndOtherOwners() public {
        token.approve(spender, 10);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenApprovingZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
    }

    function test_TransferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        token.approve(spender, 50 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 20 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 20 ether));
        assertEq(token.allowance(address(this), spender), 30 ether);
        assertEq(token.balanceOf(alice), 20 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
        assertEq(token.balanceOf(spender), 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 30 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 30 ether);
    }

    function test_InfiniteAllowanceIsNotDecremented() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 100 ether));
        assertTrue(token.transferFrom(address(this), bob, 200 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(bob), 200 ether);
    }

    function test_DelegatedSelfTransferConsumesAllowanceWithoutMovingBalance() public {
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 100));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowanceForValidAddresses() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenTransferFromHasInsufficientAllowance() public {
        token.approve(spender, 5);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 5, 6));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 6);
        assertEq(token.allowance(address(this), spender), 5);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenUnapprovedCallerUsesAnotherSpendersAllowance() public {
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenOwnerCallsTransferFromWithoutSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function test_FailedTransferFromPreservesAllowanceWhenBalanceIsInsufficient() public {
        vm.prank(alice);
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10));
        vm.prank(spender);
        token.transferFrom(alice, bob, 10);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_FailedTransferFromPreservesAllowanceWhenRecipientIsZero() public {
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertWhenZeroTransferFromUsesInvalidAddresses() public {
        // Allowance validation runs before the transfer and rejects its zero owner.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(alice, address(0), 0);
    }

    function test_DeployerCannotTakeAnotherHoldersTokens() public {
        token.transfer(alice, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 100);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_NoMintBurnAdminOrUpgradeEntrypoints() public {
        bytes[] memory calls = new bytes[](14);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("freeze(address)", alice);
        calls[8] = abi.encodeWithSignature("seize(address)", alice);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[10] = abi.encodeWithSignature("initialize(address)", bob);
        calls[11] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[12] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[13] = abi.encodeWithSignature("owner()");
        token.transfer(alice, 100);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess, "deployer reached an unsupported entrypoint");
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess, "stranger reached an unsupported entrypoint");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
    }

    function test_RejectsNativeCurrencyAndUnknownCalls() public {
        vm.deal(address(this), 1 ether);
        (bool received,) = address(token).call{value: 1 ether}("");
        assertFalse(received);
        (bool unknown,) = address(token).call(hex"deadbeef");
        assertFalse(unknown);
        (bool payableTransfer,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (alice, 1)));
        assertFalse(payableTransfer);
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_DeploymentMintsOnlyToImmediateCaller(address deployer) public {
        vm.assume(deployer != address(0));
        vm.prank(deployer);
        WheelPad instance = new WheelPad();
        assertEq(instance.balanceOf(deployer), SUPPLY);
        assertEq(instance.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalStoresExactValue(uint256 amount) public {
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(address(this), spender), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_TransferFromUpdatesBalancesAndAllowance(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approval = bound(rawApproval, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, approval);
        token.approve(spender, approval);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approval - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertWhenTransferExceedsBalance(uint256 rawBalance, uint256 rawExcess) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 excess = bound(rawExcess, 1, type(uint256).max - balance);
        token.transfer(alice, balance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + excess)
        );
        vm.prank(alice);
        token.transfer(bob, balance + excess);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertWhenTransferFromExceedsAllowance(uint256 rawApproval, uint256 rawExcess) public {
        uint256 approval = bound(rawApproval, 0, SUPPLY - 1);
        uint256 amount = approval + bound(rawExcess, 1, SUPPLY - approval);
        token.approve(spender, approval);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
