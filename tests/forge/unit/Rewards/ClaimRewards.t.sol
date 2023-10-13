// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { IERC20Token } from 'src/interfaces/pool/IPool.sol';

import { RewardsHelperContract } from './RewardsDSTestPlus.sol';

/**
    Stake should be possible regardless pool balance:
    1. stake nft with enough balance - staker should receive rewards for bucket update
    2. stake nft without enough balance - staker should receive portion of reward for bucket update
    3. stake nft with no balance - staker should not receive any token but should be able to stake
 */
contract ClaimRewardsOnStakeTest is RewardsHelperContract {
    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _lender;
    address internal _lender1;

    uint256 tokenIdOne;
    uint256 tokenIdTwo;
    uint256[] depositIndexes;

    function setUp() public {
        _startTest();

        // borrowers
        _borrower = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");

        _lender = makeAddr("lender");
        _lender1 = makeAddr("lender1");

        // instantiate test minters
        _minterOne   = makeAddr("minterOne");
        _minterTwo   = makeAddr("minterTwo");

        // instantiate test bidder
        _bidder      = makeAddr("bidder");
        deal(address(_ajna), _bidder, 900_000_000 * 10**18);

        changePrank(_bidder);
        _ajnaToken.approve(address(_pool), type(uint256).max);
        _quoteOne.approve(address(_pool), type(uint256).max);
        _quoteTwo.approve(address(_pool), type(uint256).max);

        // instantiate test updater
        _updater     = makeAddr("updater");
        _updater2    = makeAddr("updater2");

        _mintCollateralAndApproveTokens(_borrower,  1_000 * 1e18);
        _mintQuoteAndApproveTokens(_borrower,   200_000 * 1e18);

        _mintCollateralAndApproveTokens(_borrower2,  1_000 * 1e18);
        _mintQuoteAndApproveTokens(_borrower2,   200_000 * 1e18);

        _mintCollateralAndApproveTokens(_borrower3,  1_000 * 1e18);
        _mintQuoteAndApproveTokens(_borrower3,   200_000 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);

        _mintQuoteAndApproveTokens(_minterOne,  500_000_000 * 1e18);
        _mintQuoteAndApproveTokens(_minterTwo,  500_000_000 * 1e18);

        skip(10);

        // configure NFT position
        depositIndexes = new uint256[](5);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;

        tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });
        tokenIdTwo = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterTwo,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        _stakeToken({
            pool:    address(_pool),
            owner:   _minterOne,
            tokenId: tokenIdOne
        });

        _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 82.625038077222056449 * 1e18,
            borrowAmount: 300 * 1e18,
            limitIndex:   2555,
            pool:         address(_pool)
        });
    }

    function testClaimOnStakeWithInsufficientFunds() external {
        
        uint256 stakeSnapshot = vm.snapshot();

        // 1. stake nft with enough balance - staker should receive rewards for bucket update
        _stakeToken({
            pool:    address(_pool),
            owner:   _minterTwo,
            tokenId: tokenIdTwo
        });
        uint256 minterTwoBalance = _ajnaToken.balanceOf(_minterTwo);
        assertEq(minterTwoBalance, 4.131251903861097650 * 1e18);

        vm.revertTo(stakeSnapshot);

        // 2. stake nft without enough balance - staker should receive portion of reward for bucket update
        // burn rewards manager tokens and leave less tokens than rewards available
        changePrank(address(_rewardsManager));
        IERC20Token(address(_ajnaToken)).burn(99_999_999 * 1e18);

        _stakeToken({
            pool:    address(_pool),
            owner:   _minterTwo,
            tokenId: tokenIdTwo
        });
        minterTwoBalance = _ajnaToken.balanceOf(_minterTwo);
        assertEq(minterTwoBalance, 1 * 1e18);
    }

    function testClaimOnStakeWithNoBalance() external {
        // 3. stake nft with no balance - staker should not receive any token but should be able to stake
        // burn all rewards manager tokens
        changePrank(address(_rewardsManager));
        IERC20Token(address(_ajnaToken)).burn(100_000_000 * 1e18);

        _stakeToken({
            pool:    address(_pool),
            owner:   _minterTwo,
            tokenId: tokenIdTwo
        });
        uint256 minterTwoBalance = _ajnaToken.balanceOf(_minterTwo);
        assertEq(minterTwoBalance, 0);
    }
}

/**
    Exchange rate update should be possible regardless pool balance
    1. update with enough balance - staker should receive rewards for bucket update
    2. update without enough balance - staker should receive portion of reward for bucket update (available balance)
    3. update with no balance - staker should not receive any token but should be able to update
 */
contract ClaimRewardsOnExchangeRateUpdateTest is ClaimRewardsOnStakeTest {

    function testClaimOnUpdateRateWithInsufficientFunds() external {
        uint256 updateSnapshot = vm.snapshot();

        // 1. update with enough balance - staker should receive rewards for bucket update
        _updateExchangeRates({
            updater: _updater,
            pool:    address(_pool),
            indexes: depositIndexes,
            reward:  4.131251903861097650 * 1e18
        });

        uint256 updaterBalance = _ajnaToken.balanceOf(_updater);
        assertEq(updaterBalance, 4.131251903861097650 * 1e18);

        vm.revertTo(updateSnapshot);

        // 2. update without enough balance - staker should receive portion of reward for bucket update
        // burn rewards manager tokens and leave less tokens than rewards available
        changePrank(address(_rewardsManager));
        IERC20Token(address(_ajnaToken)).burn(99_999_999 * 1e18);

        _updateExchangeRates({
            updater: _updater,
            pool:    address(_pool),
            indexes: depositIndexes,
            reward:  4.131251903861097650 * 1e18
        });
        updaterBalance = _ajnaToken.balanceOf(_updater);
        assertEq(updaterBalance, 1 * 1e18);
    }

    function testClaimOnUpdateRateWithNoBalance() external {
        // 3. update with no balance - staker should not receive any token but should be able to update rate
        // burn all rewards manager tokens
        changePrank(address(_rewardsManager));
        IERC20Token(address(_ajnaToken)).burn(_ajnaToken.balanceOf(address(_rewardsManager)));

        _updateExchangeRates({
            updater: _updater,
            pool:    address(_pool),
            indexes: depositIndexes,
            reward:  4.131251903861097650 * 1e18
        });
        uint256 updaterBalance = _ajnaToken.balanceOf(_updater);
        assertEq(updaterBalance, 0);
    }
}

/**
    Claim Rewards should be constrained by pool balance and user provided limit:
    1. claim rewards with balance > rewards and rewards > limit - staker should receive rewards
    2. claim rewards with balance > rewards and rewards < limit - tx should revert
    3. claim rewards with balance < rewards and balance > limit - staker should receive balance
    4. claim rewards with balance < rewards and balance < limit - tx should revert
    5. claim rewards with balance = 0 and limit != 0 - tx should revert
    6. claim rewards with balance = 0 and limit = 0 - staker should receive no token
 */
contract ClaimRewardsTest is ClaimRewardsOnStakeTest {

    function testClaimOnClaimRewardsWithBalance() external {
        uint256 claimSnapshot = vm.snapshot();

        // 1. claim rewards with balance > rewards and rewards > limit - staker should receive rewards
        _claimRewards({
            pool:               address(_pool),
            from:               _minterOne,
            tokenId:            tokenIdOne,
            minAmountToReceive: 19 * 1e18,
            reward:             24.787511423166585895 * 1e18,
            epochsClaimed:      _epochsClaimedArray(1,0)
        });
        uint256 minterOneBalance = _ajnaToken.balanceOf(_minterOne);
        assertEq(minterOneBalance, 24.787511423166585895 * 1e18);

        vm.revertTo(claimSnapshot);

        // 2. claim rewards with balance > rewards and rewards < limit - tx should revert
        _assertClaimRewardsInsufficientLiquidityRevert(
            _minterOne,
            tokenIdOne,
            25 * 1e18
        );
    }

    function testClaimOnClaimRewardsWithInsufficientFunds() external {
        // burn rewards manager tokens to drive balance < reward
        changePrank(address(_rewardsManager));
        IERC20Token(address(_ajnaToken)).burn(99_999_990 * 1e18);

        uint256 claimSnapshot = vm.snapshot();

        // 3. claim rewards with balance < rewards and balance > limit - staker should receive balance
        _claimRewards({
            pool:               address(_pool),
            from:               _minterOne,
            tokenId:            tokenIdOne,
            minAmountToReceive: 5 * 1e18,
            reward:             24.787511423166585895 * 1e18,
            epochsClaimed:      _epochsClaimedArray(1,0)
        });
        uint256 minterOneBalance = _ajnaToken.balanceOf(_minterOne);
        assertEq(minterOneBalance, 10 * 1e18);

        vm.revertTo(claimSnapshot);

        // 4. claim rewards with balance < rewards and balance < limit - tx should revert
        _assertClaimRewardsInsufficientLiquidityRevert(
            _minterOne,
            tokenIdOne,
            11 * 1e18
        );
        _assertClaimRewardsInsufficientLiquidityRevert(
            _minterOne,
            tokenIdOne,
            25 * 1e18
        );
    }

    function testClaimOnClaimRewardsWithNoBalance() external {
        // burn all rewards manager tokens
        changePrank(address(_rewardsManager));
        IERC20Token(address(_ajnaToken)).burn(_ajnaToken.balanceOf(address(_rewardsManager)));

        // 5. claim rewards with balance = 0 and limit != 0 - tx should revert
        _assertClaimRewardsInsufficientLiquidityRevert(
            _minterOne,
            tokenIdOne,
            11 * 1e18
        );
        _assertClaimRewardsInsufficientLiquidityRevert(
            _minterOne,
            tokenIdOne,
            25 * 1e18
        );

        // 6. claim rewards with balance = 0 and limit = 0 - staker should receive no token
        _claimRewards({
            pool:               address(_pool),
            from:               _minterOne,
            tokenId:            tokenIdOne,
            minAmountToReceive: 0,
            reward:             24.787511423166585895 * 1e18,
            epochsClaimed:      _epochsClaimedArray(1,0)
        });
        uint256 minterOneBalance = _ajnaToken.balanceOf(_minterOne);
        assertEq(minterOneBalance, 0);
    }
}

/**
    Unstake should be constrained by pool balance:
    1. unstake with balance > rewards - staker should receive rewards
    2. unstake with balance < rewards - tx should revert
 */
contract ClaimRewardsOnUnstakeTest is ClaimRewardsOnStakeTest {

    function testClaimOnUnstakeWithBalance() external {
        // 1. unstake with balance > rewards - staker should receive rewards
        _unstakeToken({
            owner:                     _minterOne,
            pool:                      address(_pool),
            tokenId:                   tokenIdOne,
            claimedArray:              _epochsClaimedArray(1, 0),
            reward:                    24.787511423166585895 * 1e18,
            indexes:                   depositIndexes,
            updateExchangeRatesReward: 4.131251903861097650 * 1e18
        });
        uint256 minterOneBalance = _ajnaToken.balanceOf(_minterOne);
        assertEq(minterOneBalance, 24.787511423166585895 * 1e18);
    }

    function testClaimOnUnstakeWithInsufficientFunds() external {
        // burn rewards manager tokens to drive balance < reward
        changePrank(address(_rewardsManager));
        IERC20Token(address(_ajnaToken)).burn(99_999_990 * 1e18);

        uint256 unstakeSnapshot = vm.snapshot();

        // 2. unstake with balance < rewards - tx should revert
        _assertUnstakeInsufficientLiquidityRevert(_minterOne, tokenIdOne);

        // emergency unstake should unstake without any reward
        _emergencyUnstakeToken({
            owner:   _minterOne,
            pool:    address(_pool),
            tokenId: tokenIdOne
        });
        uint256 minterOneBalance = _ajnaToken.balanceOf(_minterOne);
        assertEq(minterOneBalance, 0);

        vm.revertTo(unstakeSnapshot);

        // burn all rewards manager tokens
        changePrank(address(_rewardsManager));
        IERC20Token(address(_ajnaToken)).burn(_ajnaToken.balanceOf(address(_rewardsManager)));

        _assertUnstakeInsufficientLiquidityRevert(_minterOne, tokenIdOne);

        // emergency unstake should unstake without any reward
        _emergencyUnstakeToken({
            owner:   _minterOne,
            pool:    address(_pool),
            tokenId: tokenIdOne
        });
        minterOneBalance = _ajnaToken.balanceOf(_minterOne);
        assertEq(minterOneBalance, 0);
    }
}
