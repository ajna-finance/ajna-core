// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "ds-test/test.sol";
import "forge-std/console.sol";
import 'src/PoolInfoUtils.sol';

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { Token }            from '../../utils/Tokens.sol';

uint constant MIN_BUCKET_INDEX = 2570;
uint constant MAX_BUCKET_INDEX = 2590;

function constrictToRange(
    uint256 x,
    uint256 min,
    uint256 max
) pure returns (uint256 result) {
    require(max >= min, "MAX_LESS_THAN_MIN");

    uint256 size = max - min;

    if (size == 0) return min;            // Using max would be equivalent as well.
    if (max != type(uint256).max) size++; // Make the max inclusive.

    // Ensure max is inclusive in cases where x != 0 and max is at uint max.
    if (max == type(uint256).max && x != 0) x--; // Accounted for later.

    if (x < min) x += size * (((min - x) / size) + 1);

    result = min + ((x - min) % size);

    // Account for decrementing x to make max inclusive.
    if (max == type(uint256).max && x != 0) result++;
}

// this contract acts as a single lender
contract InvariantLender {
    address internal _quote;
    address internal _pool;
    
    constructor(address pool, address quote) {
        _pool  = pool;
        _quote = quote;
    }

    function addQuoteToken(uint256 amount_, uint256 bucketIndex_) external {
        Token(_quote).mint(address(this), amount_);
        Token(_quote).approve(_pool, amount_);
        ERC20Pool(_pool).addQuoteToken(amount_, bucketIndex_);
    }

    function removeQuoteToken(uint256 amount_, uint256 bucketIndex_) external {
        ERC20Pool(_pool).removeQuoteToken(amount_, bucketIndex_);
    }

    function lenderLpBalance(uint256 bucketIndex_) external view returns(uint256 _lps) {
        (_lps, ) = ERC20Pool(_pool).lenderInfo(bucketIndex_, address(this));
    }
}


/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
contract InvariantLenderManager {
    address internal _pool;
    address internal _quote;

    InvariantLender[] public lenders;

    constructor(address pool, address quote) {
        _pool  = pool;
        _quote = quote;
    }

    function createLender() external {
        InvariantLender newLender = new InvariantLender(_pool, _quote);
        lenders.push(newLender);
    }

    function addQuoteToken(uint256 lenderIndex, uint256 amount, uint256 bucketIndex) external {
        amount = constrictToRange(amount, 1, 1000000 * 1e18);
        bucketIndex  = constrictToRange(bucketIndex , MIN_BUCKET_INDEX, MAX_BUCKET_INDEX);
        lenders[constrictToRange(lenderIndex, 0, lenders.length - 1)].addQuoteToken(amount, bucketIndex);
    }

    function removeQuoteToken(uint256 lenderIndex, uint256 amount, uint256 bucketIndex) external {
        lenderIndex = constrictToRange(lenderIndex, 0, lenders.length - 1);
        bucketIndex  = constrictToRange(bucketIndex , MIN_BUCKET_INDEX, MAX_BUCKET_INDEX);
        uint256 lpBalance = lenders[lenderIndex].lenderLpBalance(bucketIndex);

        if ( lpBalance > 0 ) {
            amount = constrictToRange(amount, 1, 1000000 * 1e18);
            lenders[lenderIndex].removeQuoteToken(amount, bucketIndex);
        }
    }

    function getLendersCount() external view returns(uint256) {
        return lenders.length;
    }
}

// contains invariants for the test
contract PoolInvariants is DSTest {
    InvariantLenderManager internal _invariantLenderManager;

    // Mainnet ajna address
    address internal _ajna = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;
    ERC20Pool internal _pool;
    Token internal _collateral;
    Token internal _quote;
    ERC20PoolFactory internal _poolFactory;

    function setUp() public virtual {
        _collateral  = new Token("Collateral", "C");
        _quote       = new Token("Quote", "Q");
        _poolFactory = new ERC20PoolFactory(_ajna);
        _pool        = ERC20Pool(_poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _invariantLenderManager = new InvariantLenderManager(address(_pool), address(_quote));

        // create first lender
        _invariantLenderManager.createLender();
    }

    function testPoolEncumberance() public {
        assertEq(_encumberance(1 * 1e18, 1 * 1e18), 1 * 1e18);
    }


    // include only invariantLenderManager contract for invariant testing
    function targetContracts() public view returns (address[] memory) {
        address[] memory addrs = new address[](1);
        addrs[0] = address(_invariantLenderManager);
        return addrs;
    }

    // checks pool lps are equal to sum of all lender lps in a bucket 
    function invariant_Lps() public {
        uint256 lenderCount = _invariantLenderManager.getLendersCount();
        for(uint256 bucketIndex = MIN_BUCKET_INDEX; bucketIndex <= MAX_BUCKET_INDEX; bucketIndex++ ) {
            uint256 totalLps;
            for(uint256 i = 0; i < lenderCount; i++) {
                address lender = address(_invariantLenderManager.lenders(i));
                (uint256 lps, ) = _pool.lenderInfo(bucketIndex, lender);
                totalLps += lps;
            }
            (uint256 poolLps, , , , ) = _pool.bucketInfo(bucketIndex);
            require(poolLps == totalLps, "Incorrect Lps");
        }
    }

    // checks pool quote token balance is greater than equals total deposits in pool
    function invariant_quoteTokenBalance() public {
        uint256 poolBalance = _quote.balanceOf(address(_pool));
        uint256 poolDeposit = _pool.depositSize();
        // poolBalance == poolDeposit will fail due to rounding issue while converting LPs to Quote
        require(poolBalance >= poolDeposit, "Incorrect pool Balance");
    }
}