// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import 'src/PoolInfoUtils.sol';
import 'src/RewardsManager.sol';
import 'src/PositionManager.sol';
import 'src/interfaces/rewards/IRewardsManager.sol';

import { ERC20Pool }           from 'src/ERC20Pool.sol';
import { RewardsHelperContract }   from './RewardsDSTestPlus.sol';

contract RewardsManagerTest is RewardsHelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _lender;
    address internal _lender1;
    
    uint256 constant BLOCKS_IN_DAY = 7200;
    mapping (uint256 => address) internal tokenIdToMinter;
    mapping (address => uint256) internal minterToBalance;

    function setUp() external {

        // borrowers
        _borrower = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");

        _lender = makeAddr("lender");
        _lender1 = makeAddr("lender1");

        // instantiate test minters
        _minterOne   = makeAddr("minterOne");
        _minterTwo   = makeAddr("minterTwo");
        _minterThree = makeAddr("minterThree");
        _minterFour  = makeAddr("minterFour");
        _minterFive  = makeAddr("minterFive");

        // instantiate test bidder
        _bidder      = makeAddr("bidder");
        deal(address(_ajna), _bidder, 900_000_000 * 10**18);

        vm.prank(_bidder);
        _ajnaToken.approve(address(_pool), type(uint256).max);
        vm.prank(_bidder);
        ERC20(address(_quoteOne)).approve(address(_pool), type(uint256).max);
        ERC20(address(_quoteTwo)).approve(address(_pool), type(uint256).max);

        // instantiate test updater
        _updater     = makeAddr("updater");
        _updater2    = makeAddr("updater2");

        _mintCollateralAndApproveTokens(_borrower,  100 * 1e18);
        _mintQuoteAndApproveTokens(_borrower,   200_000 * 1e18);

        _mintCollateralAndApproveTokens(_borrower2,  1_000 * 1e18);
        _mintQuoteAndApproveTokens(_borrower2,   200_000 * 1e18);

        _mintCollateralAndApproveTokens(_borrower3,  1_000 * 1e18);
        _mintQuoteAndApproveTokens(_borrower3,   200_000 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);

        _mintQuoteAndApproveTokens(_minterOne,  500_000_000 * 1e18);
        _mintQuoteAndApproveTokens(_minterTwo,  500_000_000 * 1e18);
    }

    function testDeployWith0xAddressRevert() external {
        PositionManager positionManager = new PositionManager(_poolFactory, new ERC721PoolFactory(_ajna));

        vm.expectRevert(IRewardsManagerErrors.DeployWithZeroAddress.selector);
        new RewardsManager(address(0), positionManager);
    }

    function testStakeToken() external {
        skip(10);

        // configure NFT position one
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 9;
        depositIndexes[1] = 1;
        depositIndexes[2] = 2;
        depositIndexes[3] = 3;
        depositIndexes[4] = 4;

        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        // configure NFT position two
        depositIndexes = new uint256[](4);
        depositIndexes[0] = 5;
        depositIndexes[1] = 1;
        depositIndexes[2] = 3;
        depositIndexes[3] = 12;
        uint256 tokenIdTwo = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterTwo,
            mintAmount: 1_000 * 1e18,
            pool:       address(_poolTwo)
        });

        // check only owner of an NFT can deposit it into the rewards contract
        _assertNotOwnerOfDepositRevert({
            from: _minterTwo,
            tokenId: tokenIdOne
        });

        // minterOne deposits their NFT into the rewards contract
        _stakeToken({
            pool:    address(_pool),
            owner:   _minterOne,
            tokenId: tokenIdOne
        });

        // minterTwo deposits their NFT into the rewards contract
        _stakeToken({
            pool:    address(_poolTwo),
            owner:   _minterTwo,
            tokenId: tokenIdTwo
        });
    }

    function testUnstakeToken() external {
        skip(10);

        // configure NFT position one
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 9;
        depositIndexes[1] = 1;
        depositIndexes[2] = 2;
        depositIndexes[3] = 3;
        depositIndexes[4] = 4;

        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        // check only owner of an NFT can deposit it into the rewards contract
        _assertNotOwnerOfDepositRevert({
            from: _minterTwo,
            tokenId: tokenIdOne
        });

        // minterOne deposits their NFT into the rewards contract
        _stakeToken({
            pool:    address(_pool),
            owner:   _minterOne,
            tokenId: tokenIdOne
        });

        // only owner should be able to withdraw the NFT
        _assertNotOwnerOfDepositUnstakeRevert({
            from: _minterTwo,
            tokenId: tokenIdOne
        });

        uint256[] memory claimedArray = new uint256[](0);

        _unstakeToken({
            pool:              address(_pool),
            owner:             _minterOne,
            tokenId:           tokenIdOne,
            claimedArray:      claimedArray, // no rewards as no reserve auctions have occured
            reward:            0,
            indexes:           depositIndexes,
            updateExchangeRatesReward: 0
        });
    }

    function testUnstakeTokenAfterBurnNoInterest() external {
        skip(10);
        ERC20Pool pool = ERC20Pool(address(_pool));

        // deposit into a high and low bucket
        deal(address(_quoteOne), _minterOne, 400 * 1e18);
        changePrank(_minterOne);
        _quoteOne.approve(address(_pool), type(uint256).max);
        _pool.addQuoteToken(200 * 1e18, 2_000, type(uint256).max);
        _pool.addQuoteToken(200 * 1e18, 4_000, type(uint256).max);
        skip(1 hours);

        // draw debt between the buckets
        uint256 borrowAmount = 100 * 1e18;
        uint256 limitIndex = 3_000;
        assertGt(_pool.depositSize(), borrowAmount);
        (
            uint256 collateralToPledge
        ) = _createTestBorrower(address(_pool), _borrower, borrowAmount, limitIndex);
        pool.drawDebt(_borrower, borrowAmount, limitIndex, collateralToPledge);
        skip(3 days);
        (,,, uint256 htpIndex,,) = _poolUtils.poolPricesInfo(address(_pool));
        assertLt(htpIndex, 4_000);

        // mint LP NFT and memorialize position for only the bucket which did not earn interest
        (uint256 lpBalance, ) = _pool.lenderInfo(4000, _minterOne);
        assertGt(lpBalance, 0);
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 4_000;
        uint256[] memory lpBalances = new uint256[](1);
        lpBalances[0] = lpBalance;
        changePrank(_minterOne);
        _pool.increaseLPAllowance(address(_positionManager), indexes, lpBalances);
        IPositionManagerOwnerActions.MintParams memory mintParams = IPositionManagerOwnerActions.MintParams(
            _minterOne, address(_pool), keccak256("ERC20_NON_SUBSET_HASH"));
        uint256 tokenId = _positionManager.mint(mintParams);
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);
        _registerLender(address(_positionManager), indexes);
        skip(4 days);

        // stake rewards
        _stakeToken(address(_pool), _minterOne, tokenId);
        skip(7 days);

        // repay debt to accumulate some reserves
        changePrank(_borrower);
        pool.repayDebt(_borrower, type(uint256).max, collateralToPledge, _borrower, MAX_FENWICK_INDEX);
        skip(2 hours);
        
        // burn
        changePrank(_bidder);
        pool.kickReserveAuction();
        skip(11 hours);
        _ajnaToken.approve(address(_pool), type(uint256).max);
        (,, uint256 curClaimableReservesRemaining,,) = _poolUtils.poolReservesInfo(address(_pool));
        _pool.takeReserves(curClaimableReservesRemaining);
 
        // unstake with no interest earned
        changePrank(_minterOne);
        vm.expectEmit(true, true, true, true);
        emit Unstake(_minterOne, address(_pool), tokenId);
        _rewardsManager.unstake(tokenId);
        assertEq(PositionManager(address(_positionManager)).ownerOf(tokenId), _minterOne);
    }

    function testUnstakeNoBurn() external {
        skip(10);
        ERC20Pool pool = ERC20Pool(address(_pool));

        // deposit into some buckets and mint an NFT
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2000;
        indexes[1] = 2500;
        indexes[2] = 3000;
        uint256 tokenId = _mintAndMemorializePositionNFT({
            indexes:    indexes,
            minter:     _minterOne,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        // draw debt
        uint256 borrowAmount = 1_500 * 1e18;
        uint256 limitIndex = 2_500;
        assertEq(_pool.depositIndex(borrowAmount), limitIndex);
        assertGt(_pool.depositSize(), borrowAmount);
        (
            uint256 collateralToPledge
        ) = _createTestBorrower(address(_pool), _borrower, borrowAmount, limitIndex);
        pool.drawDebt(_borrower, borrowAmount, limitIndex, collateralToPledge);
        skip(3 days);

        // stake rewards
        _stakeToken(address(_pool), _minterOne, tokenId);
        skip(7 days);

        // repay debt to accumulate some reserves
        changePrank(_borrower);
        pool.repayDebt(_borrower, type(uint256).max, collateralToPledge, _borrower, MAX_FENWICK_INDEX);
        skip(2 hours);
        
        // start auction, but no burn
        changePrank(_bidder);
        pool.kickReserveAuction();
        skip(11 hours);
 
        // unstake
        changePrank(_minterOne);
        vm.expectEmit(true, true, true, true);
        emit Unstake(_minterOne, address(_pool), tokenId);
        _rewardsManager.unstake(tokenId);
        assertEq(PositionManager(address(_positionManager)).ownerOf(tokenId), _minterOne);
    }

    function testUpdateExchangeRatesAndClaimRewards() external {
        skip(10);

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 9;
        depositIndexes[1] = 1;
        depositIndexes[2] = 2;
        depositIndexes[3] = 3;
        depositIndexes[4] = 4;

        // mint memorialize and deposit NFT
        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        _stakeToken({
            pool:    address(_pool),
            owner:   _minterOne,
            tokenId: tokenIdOne
        });

        // borrower takes actions providing reserves enabling reserve auctions
        // bidder takes reserve auctions by providing ajna tokens to be burned
        uint256 tokensToBurn = _triggerReserveAuctions({
            borrower:     _borrower,
            borrowAmount: 300 * 1e18,
            limitIndex:   3,
            pool:         address(_pool),
            tokensToBurn: 81.799378162662704349 * 1e18
        });

        // call update exchange rate to enable claiming rewards
        _updateExchangeRates({
            updater: _updater,
            pool:    address(_pool),
            indexes: depositIndexes,
            reward:  4.089968908133134138 * 1e18
        });

        // check only deposit owner can claim rewards
        _assertNotOwnerOfDepositRevert({
            from:    _updater,
            tokenId: tokenIdOne
        });

        // claim rewards accrued since deposit
        _claimRewards({
            pool:          address(_pool),
            from:          _minterOne,
            tokenId:       tokenIdOne,
            reward:        40.899689081331351737 * 1e18,
            epochsClaimed: _epochsClaimedArray(1, 0)
        });

        // check can't claim rewards twice
        _assertAlreadyClaimedRevert({
            from:    _minterOne,
            tokenId: tokenIdOne
        });

        _assertStake({
            owner:         _minterOne,
            pool:          address(_pool),
            tokenId:       tokenIdOne,
            burnEvent:     1,
            rewardsEarned: 0
        });
        assertEq(_ajnaToken.balanceOf(_minterOne), 40.899689081331351737 * 1e18);

        _assertBurn({
            pool:             address(_pool),
            epoch:            1,
            timestamp:        block.timestamp - 24 hours,
            burned:           81.799378162662704349 * 1e18,
            tokensToBurn:     tokensToBurn,
            interest:         6.443638300196908069 * 1e18
        });

        skip(2 weeks);

        // check can't call update exchange rate after the update period has elapsed
        uint256 updateRewards = _rewardsManager.updateBucketExchangeRatesAndClaim(address(_pool), depositIndexes);
        assertEq(updateRewards, 0);
    }

    function testWithdrawAndClaimRewardsNoExchangeRateUpdate() external {
        skip(10);

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;

        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        // epoch 0 - 1 is checked for rewards 
        _stakeToken({
            pool:    address(_pool),
            owner:   _minterOne,
            tokenId: tokenIdOne
        });

        // first reserve auction happens successfully -> epoch 1
        uint256 tokensToBurn = _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 81.799378162662704349 * 1e18,
            borrowAmount: 300 * 1e18,
            limitIndex:   2_555,
            pool:         address(_pool)
        });

        // call update exchange rate to enable claiming for epoch 0 - 1
        _updateExchangeRates({
            updater: _updater,
            pool:    address(_pool),
            indexes: depositIndexes,
            reward:  4.089968908133134138 * 1e18
        });

        _assertBurn({
            pool:             address(_pool),
            epoch:            1,
            timestamp:        block.timestamp - 24 hours,
            burned:           81.799378162662704349 * 1e18,
            tokensToBurn:     tokensToBurn,
            interest:         6.443638300196908069 * 1e18
        });


        // second reserve auction happens successfully -> epoch 2
        tokensToBurn += _triggerReserveAuctions({
            borrower:     _borrower, 
            borrowAmount: 300 * 1e18,
            limitIndex:   2555,
            pool:         address(_pool),
            tokensToBurn: 150.531521503946490109 * 1e18
        });

        // check owner can withdraw the NFT and rewards will be automatically claimed
        _unstakeToken({
            owner:                     _minterOne,
            pool:                      address(_pool),
            tokenId:                   tokenIdOne,
            claimedArray:              _epochsClaimedArray(2, 0),
            reward:                    78.702367919037406995 * 1e18,
            indexes:                   depositIndexes,
            updateExchangeRatesReward: 3.436607167064188546 * 1e18
        });
    }

    function testWithdrawAndClaimRewardsNoReserveTake() external {

        // healthy epoch, bad epoch

        skip(10);

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;

        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: 1000 * 1e18,
            pool: address(_pool)
        });

        // epoch 0 - 1 is checked for rewards
        _stakeToken({
            pool:    address(_pool),
            owner:   _minterOne,
            tokenId: tokenIdOne
        });

        // first reserve auction happens successfully Staker should receive rewards epoch 0 - 1
        uint256 tokensToBurn = _triggerReserveAuctions({
            borrower: _borrower,
            tokensToBurn: 81.799378162662704349 * 1e18,
            borrowAmount: 300 * 1e18,
            limitIndex: 2555,
            pool: address(_pool)
        });

        //call update exchange rate to enable claiming rewards for epoch 0 - 1
        _updateExchangeRates({
            updater: _updater,
            pool:    address(_pool),
            indexes: depositIndexes,
            reward:  4.089968908133134138 * 1e18
        });

        skip(2 weeks);

        // first reserve auction happens successfully Staker should receive rewards epoch 0 - 1
        _triggerReserveAuctionsNoTake({
            borrower: _borrower,
            borrowAmount: 300 * 1e18,
            limitIndex: 2555,
            pool: address(_pool)
        });

        _assertBurn({
            pool:             address(_pool),
            epoch:            1,
            timestamp:        block.timestamp - (2 weeks + 26 weeks + 24 hours),
            burned:           81.799378162662704349 * 1e18,
            tokensToBurn:     tokensToBurn,
            interest:         6.443638300196908069 * 1e18
        });

        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_pool),
            indexes:        depositIndexes,
            reward:         3.399661193610840835 * 1e18
        });
    }

    // two lenders stake their positions in the pool
    // staker one bucket bankrupt, staker two bucket active
    // interest accrued to both buckets, but staker one receives no rewards
    function testClaimRewardsBankruptBucket() external {

        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);

        changePrank(_minterOne);
        _quote.approve(address(_positionManager), type(uint256).max);
        _pool.approveLPTransferors(transferors);

        changePrank(_minterTwo);
        _quote.approve(address(_positionManager), type(uint256).max);
        _pool.approveLPTransferors(transferors);

        /*****************************/
        /*** Initialize Pool State ***/
        /*****************************/

        // MinterOne adds Quote token accross 5 prices
        _addInitialLiquidity({
            from:   _minterOne,
            amount: 2_000 * 1e18,
            index:  _i9_91
        });
        _addInitialLiquidity({
            from:   _minterOne,
            amount: 5_000 * 1e18,
            index:  _i9_81
        });
        _addInitialLiquidity({
            from:   _minterOne,
            amount: 11_000 * 1e18,
            index:  _i9_72
        });
        _addInitialLiquidity({
            from:   _minterOne,
            amount: 25_000 * 1e18,
            index:  _i9_62
        });
        _addInitialLiquidity({
            from:   _minterOne,
            amount: 30_000 * 1e18,
            index:  _i9_52
        });

        // first borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   2 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     19.25 * 1e18,
            indexLimit: _i9_91,
            newLup:     9.917184843435912074 * 1e18
        });

        // second borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       _borrower2,
            amount:     9_710 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        /*****************************/
        /*** Lenders Deposits NFTs ***/
        /*****************************/

        // set deposit indexes
        uint256[] memory depositIndexes = new uint256[](1);
        uint256[] memory depositIndexes2 = new uint256[](1);
        depositIndexes[0] = _i9_91;
        depositIndexes2[0] = _i9_81;

        // ERC20Pool pool = ERC20Pool(address(_pool));

        // stake NFT position one
        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: 2_000 * 1e18,
            pool:       address(_pool)
        });

        _stakeToken({
            pool:    address(_pool),
            owner:   _minterOne,
            tokenId: tokenIdOne
        });


        // stake NFT position two
        uint256 tokenIdTwo = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes2,
            minter:     _minterTwo,
            mintAmount: 5_000 * 1e18,
            pool:       address(_pool)
        });
        _stakeToken({
            pool:    address(_pool),
            owner:   _minterTwo,
            tokenId: tokenIdTwo
        });

        /***********************************/
        /*** Borrower Bankrupts A Bucket ***/
        /***********************************/

        // Skip to make borrower two undercollateralized
        skip(100 days);

        // all QT was inserted when minting NFT, provide more to kick
        deal(address(_quote), _minterTwo, 10_000 * 1e18);

        _kick({
            from:           _minterTwo,
            borrower:       _borrower2,
            debt:           9_976.561670003961916237 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           98.533942419792216457 * 1e18,
            transferAmount: 98.533942419792216457 * 1e18
        });

        // skip ahead so take can be called on the loan
        skip(10 hours);

        // take entire collateral
        _take({
            from:            _minterTwo,
            borrower:        _borrower2,
            maxCollateral:   1_000 * 1e18,
            bondChange:      6.531114528261135360 * 1e18,
            givenAmount:     653.111452826113536000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        _settle({
            from:        _minterTwo,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 9_891.935520844277346922 * 1e18
        });

        // bucket is insolvent, balances are reset
        _assertBucket({
            index:        _i9_91,
            lpBalance:    0, // bucket is bankrupt
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        // lower priced bucket isn't bankrupt, but exchange rate has decreased
        _assertBucket({
            index:        _i9_81,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      4_936.865619773958009217 * 1e18,
            exchangeRate: 0.493686561977395801 * 1e18
        });

        /***********************/
        /*** Reserve Auction ***/
        /***********************/

        // skip some time to accumulate reserves
        skip(1000 days);

        // update pool reserves
        _pool.updateInterest();

        // start reserve auction
        _kickReserveAuction({
            pool: address(_pool),
            bidder: _bidder
        });

        // allow time to pass for the reserve price to decrease
        skip(24 hours);

        (
            ,
            ,
            uint256 curClaimableReservesRemaining,
            ,
        ) = _poolUtils.poolReservesInfo(address(_pool));

        // take claimable reserves
        changePrank(_bidder);
        _pool.takeReserves(curClaimableReservesRemaining);

        /*********************/
        /*** Claim Rewards ***/
        /*********************/
        // _minterOne withdraws and claims rewards, rewards should be 0
        _unstakeToken({
            owner:                     _minterOne,
            pool:                      address(_pool),
            tokenId:                   tokenIdOne,
            claimedArray:              _epochsClaimedArray(1, 0),
            reward:                    0,
            indexes:                   depositIndexes,
            updateExchangeRatesReward: 0
        });

        // _minterTwo withdraws and claims rewards, rewards should be 0 as their bucket exchange rate decreased
        _unstakeToken({
            owner:                     _minterTwo,
            pool:                      address(_pool),
            tokenId:                   tokenIdTwo,
            claimedArray:              _epochsClaimedArray(1, 0),
            reward:                    0,
            indexes:                   depositIndexes2,
            updateExchangeRatesReward: 0
        });
    }

    function testClaimRewardsCap() external {
        skip(10);
        
        /***************************/
        /*** Lender Deposits NFT ***/
        /***************************/
        
        // set deposit indexes
        uint256[] memory depositIndexes = new uint256[](2);
        uint256[] memory depositIndex1 = new uint256[](1);
        uint256[] memory depositIndex2 = new uint256[](1);
        depositIndexes[0] = 2770;
        depositIndexes[1] = 2771;
        depositIndex1[0] = 2771;
        depositIndex2[0] = 2770;
        
        // configure NFT position one
        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: 10_000 * 1e18,
            pool:       address(_pool)
        });

        _stakeToken({
            pool:    address(_pool),
            owner:   _minterOne,
            tokenId: tokenIdOne
        });
        
        /************************************/
        /*** Borrower One Accrue Interest ***/
        /************************************/
        
        // borrower borrows
        (uint256 collateralToPledge) = _createTestBorrower(address(_pool), _borrower, 10_000 * 1e18, 2770);
 
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     5 * 1e18,
            limitIndex:         2770,
            collateralToPledge: collateralToPledge,
            newLup:             1_004.989662429170775094 * 1e18
        });

        // pass time to allow interest to accrue
        skip(2 hours);

        // borrower repays their loan
        (uint256 debt, , ) = _pool.borrowerInfo(_borrower);
        _repayDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToRepay:      debt,
            amountRepaid:       5.004807692307692310 * 1e18,
            collateralToPull:   0,
            newLup:             1_004.989662429170775094 * 1e18
        });

        /*****************************/
        /*** First Reserve Auction ***/
        /*****************************/
        // start reserve auction
        _kickReserveAuction({
            pool: address(_pool),
            bidder: _bidder
        });

        // _borrower now takes out more debt to accumulate more interest
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     2_000 * 1e18,
            limitIndex:         2770,
            collateralToPledge: 0,
            newLup:             1_004.989662429170775094 * 1e18
        });

        // allow time to pass for the reserve price to decrease
        skip(24 hours);

        _takeReserves({
            pool: address(_pool),
            from: _bidder
        });

        (,, uint256 tokensBurned) = IPool(address(_pool)).burnInfo(IPool(address(_pool)).currentBurnEpoch());

        // recorder updates the change in exchange rates in the first index
        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_pool),
            indexes:        depositIndex1,
            reward:         0.007104600671645296 * 1e18
        });
        assertEq(_ajnaToken.balanceOf(_updater), .007104600671645296 * 1e18);

        _assertBurn({
            pool:      address(_pool),
            epoch:     0,
            timestamp: 0,
            burned:    0,
            interest:  0,
            tokensToBurn: 0
        });

        _assertBurn({
            pool:             address(_pool),
            epoch:            1,
            timestamp:        block.timestamp - 24 hours,
            burned:           0.284184026893324971 * 1e18,
            interest:         0.000048562908902619 * 1e18,
            tokensToBurn:     tokensBurned
        });

        // skip more time to allow more interest to accrue
        skip(10 days);

        // borrower repays their loan again
        (debt, , ) = _pool.borrowerInfo(_borrower);
        _repayDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToRepay:      debt,
            amountRepaid:       2001.900281182536528586 * 1e18,
            collateralToPull:   0,
            newLup:             1_004.989662429170775094 * 1e18
        });

        // recorder updates the change in exchange rates in the second index
        _updateExchangeRates({
            updater:        _updater2,
            pool:           address(_pool),
            indexes:        depositIndex2,
            reward:         0.021313802017687201 * 1e18
        });
        assertEq(_ajnaToken.balanceOf(_updater2), .021313802017687201 * 1e18);


        /*******************************************/
        /*** Lender Withdraws And Claims Rewards ***/
        /*******************************************/

        // _minterOne withdraws and claims rewards, rewards should be set to the difference between total claimed and cap
        _unstakeToken({
            owner:                     _minterOne,
            pool:                      address(_pool),
            tokenId:                   tokenIdOne,
            claimedArray:              _epochsClaimedArray(1, 0),
            reward:                    0.227347221514659977 * 1e18,
            indexes:                   depositIndexes,
            updateExchangeRatesReward: 0
        });
    }

    function testMultiPeriodRewardsSingleClaim() external {
        skip(10);

        uint256 totalTokensBurned;

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](10);
        depositIndexes[0] = 5995;
        depositIndexes[1] = 5996;
        depositIndexes[2] = 5997;
        depositIndexes[3] = 5998;
        depositIndexes[4] = 5999;
        depositIndexes[5] = 6000;
        depositIndexes[6] = 6001;
        depositIndexes[7] = 6002;
        depositIndexes[8] = 6003;
        depositIndexes[9] = 6004;

        // mint memorialize and deposit NFT
        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        _stakeToken({
            pool:    address(_pool),
            owner:   _minterOne,
            tokenId: tokenIdOne
        });

        /*****************************/
        /*** First Reserve Auction ***/
        /*****************************/

        // borrower takes actions providing reserves enabling reserve auctions
        // bidder takes reserve auctions by providing ajna tokens to be burned
        totalTokensBurned += _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 408.996890813313521802 * 1e18,
            borrowAmount: 1_500 * 1e18,
            limitIndex:   6000,
            pool:         address(_pool)
        });

        // call update exchange rate to enable claiming rewards
        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_pool),
            indexes:        depositIndexes,
            reward:         20.449844540665688882 * 1e18
        });
        assertEq(_ajnaToken.balanceOf(_updater), 20.449844540665688882 * 1e18);

        uint256 rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _pool.currentBurnEpoch());
        assertEq(rewardsEarned, 204.498445406656758711 * 1e18);
        assertLt(rewardsEarned, Maths.wmul(totalTokensBurned, 0.800000000000000000 * 1e18));

        /******************************/
        /*** Second Reserve Auction ***/
        /******************************/
        // trigger second reserve auction
        totalTokensBurned += _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 749.938886647400234043 * 1e18,
            borrowAmount: 1_500 * 1e18,
            limitIndex:   6_000,
            pool:         address(_pool)
        });

        // call update exchange rate to enable claiming rewards
        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_pool),
            indexes:        depositIndexes,
            reward:         17.047099791704330880 * 1e18
        });
        assertEq(_ajnaToken.balanceOf(_updater), 37.496944332370019762 * 1e18);

        // check available rewards
        rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _pool.currentBurnEpoch());
        assertEq(rewardsEarned, 374.969443323700090181 * 1e18);
        assertLt(rewardsEarned, Maths.wmul(totalTokensBurned, 0.800000000000000000 * 1e18));

        /*****************************/
        /*** Third Reserve Auction ***/
        /*****************************/

        // trigger third reserve auction
        totalTokensBurned += _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 1_030.322190308494974315 * 1e18,
            borrowAmount: 1_500 * 1e18,
            limitIndex:   6_000,
            pool:         address(_pool)
        });

        // skip updating exchange rates and check available rewards
        uint256 rewardsEarnedNoUpdate = _rewardsManager.calculateRewards(tokenIdOne, _pool.currentBurnEpoch());
        assertEq(rewardsEarnedNoUpdate, 374.969443323700090181 * 1e18);
        assertLt(rewardsEarned, Maths.wmul(totalTokensBurned, 0.800000000000000000 * 1e18));

        // snapshot calling update exchange rate
        uint256 snapshot = vm.snapshot();

        // call update exchange rate
        _updateExchangeRates({
            updater:        _updater2,
            pool:           address(_pool),
            indexes:        depositIndexes,
            reward:         14.019165183054794390 * 1e18
        });

        assertEq(_ajnaToken.balanceOf(_updater2), 14.019165183054794390 * 1e18);

        // check available rewards
        rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _pool.currentBurnEpoch());
        assertGt(rewardsEarned, rewardsEarnedNoUpdate);
        assertLt(rewardsEarned, Maths.wmul(totalTokensBurned, 0.800000000000000000 * 1e18));

        // revert to no update state
        vm.revertTo(snapshot);

        /******************************/
        /*** Fourth Reserve Auction ***/
        /******************************/

        // triger fourth reserve auction
        totalTokensBurned += _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 1_285.690624286578714549 * 1e18,
            borrowAmount: 1_500 * 1e18,
            limitIndex:   6_000,
            pool:         address(_pool)
        });

        // check rewards earned
        rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _pool.currentBurnEpoch());
        assertEq(rewardsEarned, 374.969443323700090181 * 1e18);

        // call update exchange rate
        _updateExchangeRates({
            updater:        _updater2,
            pool:           address(_pool),
            indexes:        depositIndexes,
            reward:         0 
        });
        assertEq(_ajnaToken.balanceOf(_updater2), 0);

        // check rewards earned won't increase since previous update was missed
        rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _pool.currentBurnEpoch());
        assertEq(rewardsEarned, 374.969443323700090181 * 1e18);

        /*****************************/
        /*** Fifth Reserve Auction ***/
        /*****************************/

        // triger fifth reserve auction
        totalTokensBurned += _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 1_518.007628131033839702 * 1e18,
            borrowAmount: 1_500 * 1e18,
            limitIndex:   6_000,
            pool:         address(_pool)
        });

        // call update exchange rate
        _updateExchangeRates({
            updater:        _updater2,
            pool:           address(_pool),
            indexes:        depositIndexes,
            reward:         11.615850192222782234 * 1e18
        });
        assertEq(_ajnaToken.balanceOf(_updater2), 11.615850192222782234 * 1e18);

        rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _pool.currentBurnEpoch());
        assertEq(rewardsEarned, 491.127945245927630407 * 1e18);

        // claim all rewards accrued since deposit
        _claimRewards({
            pool:          address(_pool),
            from:          _minterOne,
            tokenId:       tokenIdOne,
            epochsClaimed: _epochsClaimedArray(5,0),
            reward:        491.127945245927630407 * 1e18
        });
        assertEq(_ajnaToken.balanceOf(_minterOne), rewardsEarned);
        assertLt(rewardsEarned, Maths.wmul(totalTokensBurned, 0.800000000000000000 * 1e18));
    }

    function testMoveStakedLiquidity() external {
        skip(10);

        /*****************/
        /*** Stake NFT ***/
        /*****************/

        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;

        // configure NFT position
        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: 1000 * 1e18,
            pool:       address(_pool)
        });

        // stake nft
        _stakeToken({
            pool:    address(_pool),
            owner:   _minterOne,
            tokenId: tokenIdOne
        });

        /***********************/
        /*** Move Staked NFT ***/
        /***********************/

        _updateExchangeRates({
            updater:        _minterOne,
            pool:           address(_pool),
            indexes:        depositIndexes,
            reward:         0
        });


        uint256[] memory secondIndexes = new uint256[](5);
        secondIndexes[0] = 2556;
        secondIndexes[1] = 2557;
        secondIndexes[2] = 2558;
        secondIndexes[3] = 2559;
        secondIndexes[4] = 2560;
        uint256[] memory secondLpsRedeemed = new uint256[](5);
        secondLpsRedeemed[0] = 1_000 * 1e18;
        secondLpsRedeemed[1] = 1_000 * 1e18;
        secondLpsRedeemed[2] = 1_000 * 1e18;
        secondLpsRedeemed[3] = 1_000 * 1e18;
        secondLpsRedeemed[4] = 1_000 * 1e18;
        uint256[] memory secondLpsAwarded = new uint256[](5);
        secondLpsAwarded[0] = 1_000 * 1e18;
        secondLpsAwarded[1] = 1_000 * 1e18;
        secondLpsAwarded[2] = 1_000 * 1e18;
        secondLpsAwarded[3] = 1_000 * 1e18;
        secondLpsAwarded[4] = 1_000 * 1e18;

        _moveStakedLiquidity({
            from:             _minterOne,
            tokenId:          tokenIdOne,
            fromIndexes:      depositIndexes,
            lpsRedeemed:      secondLpsRedeemed,
            fromIndStaked:    false,
            toIndexes:        secondIndexes,
            lpsAwarded:       secondLpsAwarded,
            expiry:           block.timestamp + 1000
        });

        /*****************************/
        /*** First Reserve Auction ***/
        /*****************************/

        // first reserve auction happens successfully -> epoch 1
        _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 81.799378162662704349 * 1e18,
            borrowAmount: 300 * 1e18,
            limitIndex:   2560,
            pool:         address(_pool)
        });

        /***********************/
        /*** Move Staked NFT ***/
        /***********************/

        // retrieve the position managers index set, recreating typical tx flow since positionIndexes are stored unordered in EnnumerableSets
        secondIndexes       = _positionManager.getPositionIndexes(tokenIdOne);
        secondLpsAwarded[0] = 1_000.000165321954673000 * 1e18;
        secondLpsAwarded[1] = 1_006.443804687426460000 * 1e18;
        secondLpsAwarded[2] = 1_000.000165321954673000 * 1e18;
        secondLpsAwarded[3] = 1_000.000165321954673000 * 1e18;
        secondLpsAwarded[4] = 1_000.000165321954673000 * 1e18;

        _moveStakedLiquidity({
            from:             _minterOne,
            tokenId:          tokenIdOne,
            fromIndexes:      secondIndexes,
            lpsRedeemed:      secondLpsRedeemed,
            fromIndStaked:    true,
            toIndexes:        depositIndexes,
            lpsAwarded:       secondLpsAwarded,
            expiry:           block.timestamp + 1000
        });

        /******************************/
        /*** Second Reserve Auction ***/
        /******************************/

        // second reserve auction happens successfully -> epoch 1
        _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 149.002721220086908460 * 1e18,
            borrowAmount: 300 * 1e18,
            limitIndex:   2555,
            pool:         address(_pool)
        });

        /******************************/
        /*** Exchange Rates Updated ***/
        /******************************/

        // retrieve the position managers index set, recreating typical tx flow since positionIndexes are stored unordered in EnnumerableSets
        depositIndexes = _positionManager.getPositionIndexes(tokenIdOne);

        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_pool),
            indexes:        depositIndexes,
            reward:         3.359647161647741986 * 1e18
        });

        /*********************/
        /*** Claim Rewards ***/
        /*********************/
        _claimRewards({
            pool:          address(_pool),
            from:          _minterOne,
            tokenId:       tokenIdOne,
            epochsClaimed: _epochsClaimedArray(1,1),
            reward:        33.596471616477451732 * 1e18
        });
    }

    function testEarlyAndLateStakerRewards() external {
        skip(10);

        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;

        // configure NFT position two
        uint256 tokenIdTwo = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterTwo,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        // bucket exchange rates are not changed at the time minter two stakes
        assertEq(_pool.bucketExchangeRate(2550), 1e18);
        assertEq(_pool.bucketExchangeRate(2551), 1e18);
        assertEq(_pool.bucketExchangeRate(2552), 1e18);
        assertEq(_pool.bucketExchangeRate(2553), 1e18);
        assertEq(_pool.bucketExchangeRate(2555), 1e18);

        // stake NFT
        _stakeToken({
            pool:    address(_pool),
            owner:   _minterTwo,
            tokenId: tokenIdTwo
        });

        (uint256 collateralToPledge) = _createTestBorrower(address(_pool), _borrower2, 10_000 * 1e18, 2770);

        // borrower borrows and change the exchange rates of buckets
        _drawDebt({
            from:               _borrower2,
            borrower:           _borrower2,
            amountToBorrow:     5 * 1e18,
            limitIndex:         2770,
            collateralToPledge: collateralToPledge,
            newLup:             3_010.892022197881557845 * 1e18
        });

        skip(1 days);

        // configure NFT position three one day after early minter
        uint256 tokenIdThree = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterThree,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        // bucket exchange rates are higher at the time minter three stakes
        assertEq(_pool.bucketExchangeRate(2550), 1.000000116558299385 * 1e18);
        assertEq(_pool.bucketExchangeRate(2551), 1.000000116558299385 * 1e18);
        assertEq(_pool.bucketExchangeRate(2552), 1.000000116558299385 * 1e18);
        assertEq(_pool.bucketExchangeRate(2553), 1.000000116558299385 * 1e18);
        assertEq(_pool.bucketExchangeRate(2555), 1.000000116558299385 * 1e18);

        // stake NFT
        _stakeToken({
            pool:    address(_pool),
            owner:   _minterThree,
            tokenId: tokenIdThree
        });

        skip(1 days);

        _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 133.011310982683297932 * 1e18,
            borrowAmount: 300 * 1e18,
            limitIndex:   2555,
            pool:         address(_pool)
        });

        // unstake and compare rewards and balances of minter two and minter three
        _unstakeToken({
            owner:                     _minterTwo,
            pool:                      address(_pool),
            tokenId:                   tokenIdTwo,
            claimedArray:              _epochsClaimedArray(1, 0),
            reward:                    39.906320577094451437 * 1e18,
            indexes:                   depositIndexes,
            updateExchangeRatesReward: 6.651053030580225818 * 1e18
        });

        uint256 minterTwoBalance = _ajnaToken.balanceOf(_minterTwo);
        assertEq(minterTwoBalance, 39.906320577094451437 * 1e18);
        _unstakeToken({
            owner:                     _minterThree,
            pool:                      address(_pool),
            tokenId:                   tokenIdThree,
            claimedArray:              _epochsClaimedArray(1, 0),
            reward:                    33.250387944827385443 * 1e18,
            indexes:                   depositIndexes,
            updateExchangeRatesReward: 0
        });
        uint256 minterThreeBalance = _ajnaToken.balanceOf(_minterThree);
        assertEq(minterThreeBalance, 33.250387944827385443 * 1e18);

        assertGt(minterTwoBalance, minterThreeBalance);
    }

    // Calling updateExchangeRates not needed since deposits will update the exchange rate themselves
    function testClaimRewardsMultipleDepositsSameBucketsMultipleAuctions() external {
        skip(10);

        /*****************************/
        /*** First Lender Deposits ***/
        /*****************************/

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 9;
        depositIndexes[1] = 1;
        depositIndexes[2] = 2;
        depositIndexes[3] = 3;
        depositIndexes[4] = 4;

        // mint memorialize and deposit NFT
        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        // stake NFT
        _stakeToken({
            pool:    address(_pool),
            owner:   _minterOne,
            tokenId: tokenIdOne
        });

        /*****************************/
        /*** First Reserve Auction ***/
        /*****************************/

        // borrower takes actions providing reserves enabling reserve auctions
        uint256 firstTokensToBurn = _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 81.799378162662704349 * 1e18,
            borrowAmount: 300 * 1e18,
            limitIndex:   3,
            pool:         address(_pool)
        });

        /******************************/
        /*** Second Lender Deposits ***/
        /******************************/

        // second depositor deposits an NFT representing the same positions into the rewards contract
        uint256 tokenIdTwo = _mintAndMemorializePositionNFT({
            indexes: depositIndexes,
            minter: _minterTwo,
            mintAmount: 1000 * 1e18,
            pool: address(_pool)
        });

        // second depositor stakes NFT, generating an update reward
        _stakeToken({
            pool:    address(_pool),
            owner:   _minterTwo,
            tokenId: tokenIdTwo
        });
        assertEq(_ajnaToken.balanceOf(_minterTwo), 8.154804173752250280 * 1e18);

        // calculate rewards earned since exchange rates have been updated
        uint256 idOneRewardsAtOne = _rewardsManager.calculateRewards(tokenIdOne, _pool.currentBurnEpoch());
        assertLt(idOneRewardsAtOne, firstTokensToBurn);
        assertGt(idOneRewardsAtOne, 1);

        // minter one claims rewards accrued since deposit
        _claimRewards({
            pool:          address(_pool),
            from:          _minterOne,
            tokenId:       tokenIdOne,
            epochsClaimed: _epochsClaimedArray(1,0),
            reward:        idOneRewardsAtOne
        });

        /******************************/
        /*** Second Reserve Auction ***/
        /******************************/
        // // borrower takes actions providing reserves enabling additional reserve auctions
        // conduct second reserve auction
        uint256 secondTokensToBurn = _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 175.886535409777500511 * 1e18,
            borrowAmount: 300 * 1e18,
            limitIndex:   3,
            pool:         address(_pool)
        });

        /*****************************/
        /*** Third Lender Deposits ***/
        /*****************************/

        // third depositor deposits an NFT representing the same positions into the rewards contract
        uint256 tokenIdThree = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterThree,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        _stakeToken({
            pool:    address(_pool),
            owner:   _minterThree,
            tokenId: tokenIdThree
        });

        /***********************/
        /*** Rewards Claimed ***/
        /***********************/

        // calculate rewards earned since exchange rates have been updated
        uint256 idOneRewardsAtTwo = _rewardsManager.calculateRewards(tokenIdOne, _pool.currentBurnEpoch());
        assertLt(idOneRewardsAtTwo, secondTokensToBurn);
        assertGt(idOneRewardsAtTwo, 0);
        assertEq(idOneRewardsAtTwo, 23.539744751129506689 * 1e18);

        uint256 idTwoRewardsAtTwo = _rewardsManager.calculateRewards(tokenIdTwo, _pool.currentBurnEpoch());
        assertLt(idOneRewardsAtTwo + idTwoRewardsAtTwo, secondTokensToBurn);
        assertEq(idTwoRewardsAtTwo, 23.507298745456577468 * 1e18);
        assertGt(idTwoRewardsAtTwo, 0);

        // minter one claims rewards accrued after second auction        
        _claimRewards({
            pool:          address(_pool),
            from:          _minterOne,
            tokenId:       tokenIdOne,
            epochsClaimed: _epochsClaimedArray(1,1),
            reward:        23.539744751129506689 * 1e18
        });

        assertEq(_ajnaToken.balanceOf(_minterOne), idOneRewardsAtOne + idOneRewardsAtTwo);

        // minter two claims rewards accrued since deposit
        _claimRewards({
            pool:          address(_pool),
            from:          _minterTwo,
            tokenId:       tokenIdTwo,
            epochsClaimed: _epochsClaimedArray(1,1),
            reward:        idTwoRewardsAtTwo
        });
        assertEq(_ajnaToken.balanceOf(_minterTwo), 31.662102919208827748 * 1e18);

        // check there are no remaining rewards available after claiming
        uint256 remainingRewards = _rewardsManager.calculateRewards(tokenIdOne, _pool.currentBurnEpoch());
        assertEq(remainingRewards, 0);

        remainingRewards = _rewardsManager.calculateRewards(tokenIdTwo, _pool.currentBurnEpoch());
        assertEq(remainingRewards, 0);

        remainingRewards = _rewardsManager.calculateRewards(tokenIdThree, _pool.currentBurnEpoch());
        assertEq(remainingRewards, 0);
    }

    function testClaimRewardsMultipleDepositsDifferentBucketsMultipleAuctions() external {
        // configure _minterOne's NFT position
        uint256[] memory firstIndexes = new uint256[](5);
        firstIndexes[0] = 2550;
        firstIndexes[1] = 2551;
        firstIndexes[2] = 2552;
        firstIndexes[3] = 2553;
        firstIndexes[4] = 2555;

        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    firstIndexes,
            minter:     _minterOne,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        // configure _minterTwo's NFT position
        uint256[] memory secondIndexes = new uint256[](5);
        secondIndexes[0] = 2550;
        secondIndexes[1] = 2551;
        secondIndexes[2] = 2200;
        secondIndexes[3] = 2221;
        secondIndexes[4] = 2222;

        uint256 tokenIdTwo = _mintAndMemorializePositionNFT({
            indexes:    secondIndexes,
            minter:     _minterTwo,
            mintAmount: 5_000 * 1e18,
            pool:       address(_pool)
        });

        // lenders stake their NFTs
        _stakeToken(address(_pool), _minterOne, tokenIdOne);
        _stakeToken(address(_pool), _minterTwo, tokenIdTwo);

        uint256[] memory depositIndexes = new uint256[](8);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;
        depositIndexes[5] = 2200;
        depositIndexes[6] = 2221;
        depositIndexes[7] = 2222;

        // borrower takes actions providing reserves enabling three reserve auctions
        // proof of burn events (burn epoch 0)
        _assertBurn({
            pool:      address(_pool),
            epoch:        0,
            timestamp:    0,
            burned:       0,
            interest:     0,
            tokensToBurn: 0
        });

        // auction one
        uint256 tokensToBurnE1 = _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 81.799378162663471460 * 1e18,
            borrowAmount: 300 * 1e18,
            limitIndex:   2555,
            pool:         address(_pool)
        });

        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_pool),
            indexes:        depositIndexes,
            reward:         4.089968908133195708 * 1e18
        });

        _assertBurn({
            pool:             address(_pool),
            epoch:            1,
            timestamp:        block.timestamp - 24 hours,
            burned:           81.799378162663471460 * 1e18,
            tokensToBurn:     tokensToBurnE1,
            interest:         6.443638300196908069 * 1e18
        });

        // auction two
        uint256 tokensToBurnE2 = _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 308.524022190658113598 * 1e18,
            borrowAmount: 1_000 * 1e18,
            limitIndex:   2555,
            pool:         address(_pool)
        });

        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_pool),
            indexes:        depositIndexes,
            reward:         11.336232201399613917 * 1e18
        });

        _assertBurn({
            pool:             address(_pool),
            epoch:            2,
            timestamp:        block.timestamp - 24 hours,
            burned:           308.524022190658113598 * 1e18,
            tokensToBurn:     tokensToBurnE2,
            interest:         23.938554041534910348 * 1e18
        });

        // auction three
        uint256 tokensToBurnE3 = _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 676.510732923020389616 * 1e18,
            borrowAmount: 2_000 * 1e18,
            limitIndex:   2555,
            pool:         address(_pool)
        });
 
        _updateExchangeRates({
            updater: _updater,
            pool:    address(_pool),
            indexes: depositIndexes,
            reward:  18.399335536618388154 * 1e18
        });

        _assertBurn({
            pool:             address(_pool),
            epoch:            3,
            timestamp:        block.timestamp - 24 hours,
            burned:           676.510732923020389616 * 1e18,
            tokensToBurn:     tokensToBurnE3,
            interest:         52.423541260157607958 * 1e18
        });

        // both stakers claim rewards
        _unstakeToken({
            owner:                     _minterOne,
            pool:                      address(_pool),
            tokenId:                   tokenIdOne,
            claimedArray:              _epochsClaimedArray(3, 0),
            reward:                    51.499282055430577895 * 1e18,
            indexes:                   firstIndexes,   
            updateExchangeRatesReward: 0
        });

        _unstakeToken({
            owner:                     _minterTwo,
            pool:                      address(_pool),
            tokenId:                   tokenIdTwo,
            claimedArray:              _epochsClaimedArray(3, 0),
            reward:                    286.756084406079436885 * 1e18,
            indexes:                   secondIndexes,
            updateExchangeRatesReward: 0
        });
    }


    function testWithdrawAndClaimRewards() external {
        skip(10);

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;

        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        // stake nft
        _stakeToken({
            pool:    address(_pool),
            owner:   _minterOne,
            tokenId: tokenIdOne
        });

        uint256 tokensToBurn = _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 81.799378162662704349 * 1e18,
            borrowAmount: 300 * 1e18,
            limitIndex:   2555,
            pool:         address(_pool)
        });

        // call update exchange rate to enable claiming rewards
        _updateExchangeRates({
            updater: _updater,
            pool:    address(_pool),
            indexes: depositIndexes,
            reward:  4.089968908133134138 * 1e18
        });

        // check owner can withdraw the NFT and rewards will be automatically claimed

        uint256 snapshot = vm.snapshot();

        // claimed rewards amount is greater than available tokens in rewards manager contract

        // burn rewards manager tokens and leave only 5 tokens available
        changePrank(address(_rewardsManager));
        IERC20Token(address(_ajnaToken)).burn(99_999_990.978586345404952410 * 1e18);

        uint256 managerBalance = _ajnaToken.balanceOf(address(_rewardsManager));
        assertEq(managerBalance, 4.931444746461913452 * 1e18);

        // _minterOne unstakes staked position
        _unstakeToken({
            owner:                     _minterOne,
            pool:                      address(_pool),
            tokenId:                   tokenIdOne,
            claimedArray:              _epochsClaimedArray(1, 0),
            reward:                    40.899689081331351737 * 1e18,
            indexes:                   depositIndexes,
            updateExchangeRatesReward: 0
        });

        // minter one receives only the amount of 5 ajna tokens available in manager balance instead calculated rewards of 40.214136545950568150
        assertEq(_ajnaToken.balanceOf(_minterOne), managerBalance);
        // all 5 tokens available in manager balance were used to reward minter one
        assertEq(_ajnaToken.balanceOf(address(_rewardsManager)), 0);

        vm.revertTo(snapshot);

        // test when enough tokens in rewards manager contracts
        // _minterOne unstakes staked position
        _unstakeToken({
            owner:                      _minterOne,
            pool:                       address(_pool),
            tokenId:                    tokenIdOne,
            claimedArray:               _epochsClaimedArray(1, 0),
            reward:                     40.899689081331351737 * 1e18,
            indexes:                    depositIndexes,
            updateExchangeRatesReward:  0
        });

        assertEq(PositionManager(address(_positionManager)).ownerOf(tokenIdOne), _minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 40.899689081331351737 * 1e18);
        assertLt(_ajnaToken.balanceOf(_minterOne), tokensToBurn);

        // check can't claim rewards twice
        _assertNotOwnerOfDepositRevert({
            from: _minterOne,
            tokenId: tokenIdOne
        });
    }

    function testMultiplePools() external {
        skip(10);

        // configure NFT position one
        uint256[] memory firstIndexes = new uint256[](5);
        firstIndexes[0] = 9;
        firstIndexes[1] = 1;
        firstIndexes[2] = 2;
        firstIndexes[3] = 3;
        firstIndexes[4] = 4;

        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    firstIndexes,
            minter:     _minterOne,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        // configure NFT position two
        uint256[] memory secondIndexes = new uint256[](4);
        secondIndexes[0] = 5;
        secondIndexes[1] = 1;
        secondIndexes[2] = 3;
        secondIndexes[3] = 12;

        uint256 tokenIdTwo = _mintAndMemorializePositionNFT({
            indexes:    secondIndexes,
            minter:     _minterTwo,
            mintAmount: 1_000 * 1e18,
            pool:       address(_poolTwo)
        });

        // minterOne deposits their NFT into the rewards contract
        _stakeToken(address(_pool), _minterOne, tokenIdOne);

        // minterTwo deposits their NFT into the rewards contract
        _stakeToken(address(_poolTwo), _minterTwo, tokenIdTwo);

        // borrower takes actions providing reserves enabling reserve auctions
        // bidder takes reserve auctions by providing ajna tokens to be burned
        uint256 tokensToBurn = _triggerReserveAuctions({
            borrower:     _borrower,
            tokensToBurn: 81.799378162662704349 * 1e18,
            borrowAmount: 300 * 1e18,
            limitIndex:   3,
            pool:         address(_pool)
        });

        // check only deposit owner can claim rewards
        _assertNotOwnerOfDepositRevert({
            from: _minterTwo,
            tokenId: tokenIdOne
        });

        // check rewards earned in one pool shouldn't be claimable by depositors from another pool
        assertEq(_ajnaToken.balanceOf(_minterTwo), 0);
        _claimRewards({
            pool:          address(_poolTwo),
            from:          _minterTwo,
            tokenId:       tokenIdTwo,
            reward:        0,
            epochsClaimed: _epochsClaimedArray(0, 0)
        });
        assertEq(_ajnaToken.balanceOf(_minterTwo), 0);

        // call update exchange rate to enable claiming rewards
        _updateExchangeRates({
            updater: _minterOne,
            pool:    address(_pool),
            indexes: firstIndexes,
            reward:  4.089968908133134138 * 1e18
        });
        assertEq(_ajnaToken.balanceOf(_minterOne), 4.089968908133134138 * 1e18);

        // check owner in pool with accrued interest can properly claim rewards
        _claimRewards({
            pool:          address(_pool),
            from:          _minterOne,
            tokenId:       tokenIdOne,
            reward:        40.899689081331351737 * 1e18,
            epochsClaimed: _epochsClaimedArray(1, 0)
        });
        assertLt(_ajnaToken.balanceOf(_minterOne), tokensToBurn);

    }

    /********************/
    /*** FUZZ TESTING ***/
    /********************/

    function testClaimRewardsFuzzy(uint256 indexes, uint256 mintAmount) external {
        indexes    = bound(indexes, 3, 10); // number of indexes to add liquidity to
        mintAmount = bound(mintAmount, 1 * 1e18, 100_000 * 1e18); // bound mint amount and dynamically determine borrow amount and collateral based upon provided index and mintAmount

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](indexes);
        for (uint256 i = 0; i < indexes; ++i) {
            depositIndexes[i] = _randomIndex();
        }

        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: mintAmount,
            pool:       address(_pool)
        });

        // stake NFT
        _stakeToken(address(_pool), _minterOne, tokenIdOne);

        // calculates a limit index leaving one index above the htp to accrue interest
        uint256 limitIndex = _findSecondLowestIndexPrice(depositIndexes);

        // start and end new reserve auction 
        uint256 tokensToBurn= _triggerReserveAuctionsBurnUnknown({
            borrower: _borrower,
            borrowAmount: Maths.wdiv(mintAmount, Maths.wad(3)),
            limitIndex:   limitIndex,
            pool:         address(_pool)
        });

        // call update exchange rate to enable claiming rewards
        changePrank(_updater);
        assertEq(_ajnaToken.balanceOf(_updater), 0);
        _rewardsManager.updateBucketExchangeRatesAndClaim(address(_pool), depositIndexes);
        assertGt(_ajnaToken.balanceOf(_updater), 0);

        // calculate rewards earned and compare to percentages for updating and claiming
        uint256 rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _pool.currentBurnEpoch());
        assertGt(rewardsEarned, 0);

        // claim rewards accrued since deposit
        _claimRewards({
            pool:          address(_pool),
            from:          _minterOne,
            tokenId:       tokenIdOne,
            reward:        rewardsEarned,
            epochsClaimed: _epochsClaimedArray(1, 0)
        });

        // assert rewards claimed is less than ajna tokens burned cap
        assertLt(_ajnaToken.balanceOf(_minterOne), Maths.wmul(tokensToBurn, 0.800000000000000000 * 1e18));
    }

    function testStakingRewardsFuzzy(uint256 deposits, uint256 reserveAuctions) external {
        deposits        = bound(deposits, 1, 25); // number of deposits to make
        reserveAuctions = bound(reserveAuctions, 1, 25); // number of reserve Auctions to complete

        uint256[] memory tokenIds = new uint256[](deposits);

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](3);
        for (uint256 j = 0; j < 3; ++j) {
            depositIndexes[j] = _randomIndex();
            vm.roll(block.number + 1); // advance block to ensure that the index price is different
        }

        address[] memory minters = _getAddresses(deposits);

        // stake variable no of deposits
        for (uint256 i = 0; i < deposits; ++i) {

            tokenIds[i] = _mintAndMemorializePositionNFT({
                indexes: depositIndexes,
                minter: minters[i],
                mintAmount: 1_000_000_000 * 1e18,
                pool: address(_pool)
            });
            tokenIdToMinter[tokenIds[i]] = minters[i];
            _stakeToken(address(_pool), minters[i], tokenIds[i]);
        }

        uint256 updaterBalance = _ajnaToken.balanceOf(_updater);

        for (uint i = 0; i < deposits; i++) {
            minterToBalance[minters[i]] = _ajnaToken.balanceOf(minters[i]);
        }

        // start variable no of reserve Auctions and claim rewards for random tokenIds in each epoch
        for (uint i = 0; i < reserveAuctions; ++i) {
            uint256 limitIndex = _findSecondLowestIndexPrice(depositIndexes);

            // start and end new reserve auction 
            uint256 tokensBurned = _triggerReserveAuctionsBurnUnknown({
                borrower: _borrower,
                borrowAmount: 10_000 * 1e18,
                limitIndex:   limitIndex,
                pool:         address(_pool)
            });

            // call update exchange rate to enable claiming rewards
            assertEq(_ajnaToken.balanceOf(_updater), updaterBalance);

            changePrank(_updater);
            assertEq(_ajnaToken.balanceOf(_updater), updaterBalance);
            _rewardsManager.updateBucketExchangeRatesAndClaim(address(_pool), depositIndexes);

            // ensure updater gets reward for updating exchange rate
            assertGt(_ajnaToken.balanceOf(_updater), updaterBalance);

            // ensure update rewards in each epoch is less than or equals to 10% of tokensBurned
            assertLe(_ajnaToken.balanceOf(_updater) - updaterBalance, tokensBurned / 10);

            updaterBalance = _ajnaToken.balanceOf(_updater);

            // pick random NFTs from all NFTs to claim rewards
            uint256[] memory randomNfts = _getRandomSubsetFromArray(tokenIds);

            for (uint j = 0; j < randomNfts.length; j++) {
                address minterAddress = tokenIdToMinter[randomNfts[j]];
                changePrank(minterAddress);

                (, , uint256 lastInteractionEpoch) = _rewardsManager.getStakeInfo(randomNfts[j]);

                // select random epoch to claim reward
                uint256 epochToClaim = lastInteractionEpoch < _pool.currentBurnEpoch() ? randomInRange(lastInteractionEpoch + 1, _pool.currentBurnEpoch()) : lastInteractionEpoch; 
                
                uint256 rewardsEarned = _rewardsManager.calculateRewards(randomNfts[j], epochToClaim);
                assertGt(rewardsEarned, 0);

                _rewardsManager.claimRewards(randomNfts[j], _pool.currentBurnEpoch());

                // ensure user gets reward
                assertGt(_ajnaToken.balanceOf(minterAddress), minterToBalance[minterAddress]);
                minterToBalance[minterAddress] = _ajnaToken.balanceOf(minterAddress);
            }
        }
    }

    function testClaimRewardsFreezeUnclaimedYield() external {
        skip(10);

        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 9;
        depositIndexes[1] = 1;
        depositIndexes[2] = 2;
        depositIndexes[3] = 3;
        depositIndexes[4] = 4;

        uint256 tokenIdOne = _mintAndMemorializePositionNFT({
            indexes:    depositIndexes,
            minter:     _minterOne,
            mintAmount: 1_000 * 1e18,
            pool:       address(_pool)
        });

        _stakeToken(address(_pool), _minterOne, tokenIdOne);

        uint256 currentBurnEpoch = _pool.currentBurnEpoch();

        changePrank(_minterOne);
        // should revert if the epoch to claim is not available yet
        vm.expectRevert(IRewardsManagerErrors.EpochNotAvailable.selector);
        _rewardsManager.claimRewards(tokenIdOne, currentBurnEpoch + 10);

        // user should be able to claim rewards for current epoch
        _rewardsManager.claimRewards(tokenIdOne, currentBurnEpoch);
    }

}
