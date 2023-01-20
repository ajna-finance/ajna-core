// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "forge-std/console.sol";

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { Token }            from '../../utils/Tokens.sol';
import { PoolInfoUtils }    from 'src/PoolInfoUtils.sol';
import { InvariantActorManager, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX} from './utils/InvariantManager.sol';

struct FuzzSelector {
    address addr;
    bytes4[] selectors;
}

contract InvariantTest {

    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    address[] private _excludedContracts;
    address[] private _excludedSenders;
    address[] private _targetedContracts;
    address[] private _targetedSenders;

    FuzzSelector[] internal _targetedSelectors;

    function excludeContract(address newExcludedContract_) internal {
        _excludedContracts.push(newExcludedContract_);
    }

    function excludeContracts() public view returns (address[] memory excludedContracts_) {
        require(_excludedContracts.length != uint256(0), "NO_EXCLUDED_CONTRACTS");
        excludedContracts_ = _excludedContracts;
    }

    function excludeSender(address newExcludedSender_) internal {
        _excludedSenders.push(newExcludedSender_);
    }

    function excludeSenders() public view returns (address[] memory excludedSenders_) {
        require(_excludedSenders.length != uint256(0), "NO_EXCLUDED_SENDERS");
        excludedSenders_ = _excludedSenders;
    }

    function targetContract(address newTargetedContract_) internal {
        _targetedContracts.push(newTargetedContract_);
    }

    function targetContracts() public view returns (address[] memory targetedContracts_) {
        require(_targetedContracts.length != uint256(0), "NO_TARGETED_CONTRACTS");
        targetedContracts_ = _targetedContracts;
    }

    function targetSelector(FuzzSelector memory newTargetedSelector_) internal {
        _targetedSelectors.push(newTargetedSelector_);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targetedSelectors_) {
        require(targetedSelectors_.length != uint256(0), "NO_TARGETED_SELECTORS");
        targetedSelectors_ = _targetedSelectors;
    }

    function targetSender(address newTargetedSender_) internal {
        _targetedSenders.push(newTargetedSender_);
    }

    function targetSenders() public view returns (address[] memory targetedSenders_) {
        require(_targetedSenders.length != uint256(0), "NO_TARGETED_SENDERS");
        targetedSenders_ = _targetedSenders;
    }

}

// contains invariants for the test
contract PoolInvariants is InvariantTest, Test{
    InvariantActorManager internal _invariantActorManager;

    // Mainnet ajna address
    address internal _ajna = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;
    ERC20Pool internal _pool;
    Token internal _collateral;
    Token internal _quote;
    PoolInfoUtils internal _poolInfo;
    ERC20PoolFactory internal _poolFactory;

    function setUp() public virtual {
        _collateral  = new Token("Collateral", "C");
        _quote       = new Token("Quote", "Q");
        _poolFactory = new ERC20PoolFactory(_ajna);
        _pool        = ERC20Pool(_poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _poolInfo    = new PoolInfoUtils();
        _invariantActorManager = new InvariantActorManager(address(_pool), address(_quote), address(_collateral), address(_poolInfo));

        // create first Actor
        _invariantActorManager.createActor();

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = InvariantActorManager.addQuoteToken.selector;
        selectors[1] = InvariantActorManager.removeQuoteToken.selector;
        selectors[2] = InvariantActorManager.drawDebt.selector;
        selectors[3] = InvariantActorManager.repayDebt.selector;
        selectors[4] = InvariantActorManager.createActor.selector;
        FuzzSelector memory target = FuzzSelector(address(_invariantActorManager), selectors);

        // targetContract(address(_invariantActorManager));
        targetSelector(target);
    }

    // include only required functions from invariantLenderManager contract for invariant testing
    // function targetSelectors() public view returns (FuzzSelector[] memory) {
    //     FuzzSelector[] memory targets = new FuzzSelector[](1);
    //     bytes4[] memory selectors = new bytes4[](5);
    //     selectors[0] = InvariantActorManager.addQuoteToken.selector;
    //     selectors[1] = InvariantActorManager.removeQuoteToken.selector;
    //     selectors[2] = InvariantActorManager.drawDebt.selector;
    //     selectors[3] = InvariantActorManager.repayDebt.selector;
    //     selectors[4] = InvariantActorManager.createActor.selector;
    //     targets[0] = FuzzSelector(address(_invariantActorManager), selectors);
    //     return targets;
    // }

    // checks pool lps are equal to sum of all lender lps in a bucket 
    function invariant_Lps() public {
        uint256 actorCount = _invariantActorManager.getActorsCount();
        for(uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            uint256 totalLps;
            for(uint256 i = 0; i < actorCount; i++) {
                address lender = address(_invariantActorManager.actors(i));
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
        (uint256 pooldebt, , ) = _pool.debtInfo();
        // poolBalance == poolDeposit will fail due to rounding issue while converting LPs to Quote
        require(poolBalance == _pool.depositSize() - pooldebt, "Incorrect pool Balance");
    }

    // checks pools collateral Balance to be equal to collateral pledged
    function invariant_collateralBalance() public {
        uint256 actorCount = _invariantActorManager.getActorsCount();
        uint256 totalCollateralPledged;
        for(uint256 i = 0; i < actorCount; i++) {
            address borrower = address(_invariantActorManager.actors(i));
            ( , uint256 borrowerCollateral, ) = _pool.borrowerInfo(borrower);
            totalCollateralPledged += borrowerCollateral;
        }

        require(_pool.pledgedCollateral() == totalCollateralPledged, "Incorrect Collateral Pledged");
    }

    // checks pool debt is equal to sum of all borrowers debt
    function invariant_pooldebt() public {
        uint256 actorCount = _invariantActorManager.getActorsCount();
        uint256 totalDebt;
        for(uint256 i = 0; i < actorCount; i++) {
            address borrower = address(_invariantActorManager.actors(i));
            (uint256 debt, , ) = _pool.borrowerInfo(borrower);
            totalDebt += debt;
        }

        uint256 poolDebt = _pool.totalDebt();

        require(poolDebt == totalDebt, "Incorrect pool debt");
    }
}