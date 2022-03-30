import brownie
from brownie import Contract
import pytest
from decimal import *


def test_purchase_bid_partial_amount(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    capsys,
    test_utils,
):

    with test_utils.GasWatcher(["purchaseBid"]):
        lender = lenders[0]
        borrower = borrowers[0]
        bidder = borrowers[1]

        assert dai.balanceOf(lender) == 200_000 * 1e18
        mkr_dai_pool.addQuoteToken(3_000 * 1e18, 4000 * 1e18, {"from": lender})
        mkr_dai_pool.addQuoteToken(3_000 * 1e18, 3000 * 1e18, {"from": lender})
        mkr_dai_pool.addQuoteToken(3_000 * 1e18, 1000 * 1e18, {"from": lender})

        # borrower takes a loan of 4000 DAI making bucket 4000 to be fully utilized
        mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
        mkr_dai_pool.borrow(4_000 * 1e18, 3000 * 1e18, {"from": borrower})
        assert mkr_dai_pool.lup() == 3_000 * 1e18

        # should fail if invalid price
        with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
            mkr_dai_pool.purchaseBid(1 * 1e18, 1000, {"from": bidder})
        assert exc.value.revert_msg == "ajna/invalid-bucket-price"

        # should fail if bidder doesn't have enough collateral
        with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
            mkr_dai_pool.purchaseBid(2_000_000 * 1e18, 4000 * 1e18, {"from": bidder})
        assert exc.value.revert_msg == "ajna/not-enough-collateral-balance"

        # should fail if trying to purchase more than on bucket
        with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
            mkr_dai_pool.purchaseBid(4_000 * 1e18, 4000 * 1e18, {"from": bidder})
        assert exc.value.revert_msg == "ajna/insufficient-bucket-size"

        assert mkr.balanceOf(bidder) == 100 * 1e18
        assert dai.balanceOf(bidder) == 0

        assert mkr.balanceOf(mkr_dai_pool) == 100 * 1e18
        assert dai.balanceOf(mkr_dai_pool) == 5_000 * 1e18

        assert mkr_dai_pool.totalCollateral() == 100 * 1e18

        # check 4000 bucket balance before purchase bid
        (
            _,
            _,
            _,
            bucket_deposit,
            bucket_debt,
            _,
            _,
            _,
        ) = mkr_dai_pool.bucketAt(4_000 * 1e18)
        assert bucket_debt == 3_000 * 1e18
        assert bucket_deposit == 0

        # check 3000 bucket balance before purchase bid
        (
            _,
            _,
            _,
            bucket_deposit,
            bucket_debt,
            _,
            _,
            _,
        ) = mkr_dai_pool.bucketAt(3_000 * 1e18)
        assert bucket_debt == 1_000 * 1e18
        assert bucket_deposit == 2_000 * 1e18

        # purchase 2000 bid from 4000 bucket
        tx = mkr_dai_pool.purchaseBid(2_000 * 1e18, 4_000 * 1e18, {"from": bidder})

        assert mkr_dai_pool.lup() == 1_000 * 1e18
        # check 4000 bucket balance after purchase bid
        (
            _,
            _,
            _,
            bucket_deposit,
            bucket_debt,
            _,
            _,
            _,
        ) = mkr_dai_pool.bucketAt(4_000 * 1e18)
        # checked without time delay in forge
        assert 1_000 * 1e18 <= bucket_debt <= 1_001 * 1e18
        assert bucket_deposit == 0

        # check 3000 bucket balance after purchase bid
        (
            _,
            _,
            _,
            bucket_deposit,
            bucket_debt,
            _,
            _,
            _,
        ) = mkr_dai_pool.bucketAt(3_000 * 1e18)
        # checked without time delay in forge
        assert 3_000 * 1e18 <= bucket_debt <= 3_001 * 1e18
        assert bucket_deposit == 0

        # check 1000 bucket balance after purchase bid
        (
            _,
            _,
            _,
            bucket_deposit,
            bucket_debt,
            _,
            _,
            _,
        ) = mkr_dai_pool.bucketAt(1_000 * 1e18)
        assert bucket_debt == 0
        assert bucket_deposit == 3_000 * 1e18

        assert mkr.balanceOf(bidder) == 99.5 * 1e18
        assert dai.balanceOf(bidder) == 2_000 * 1e18

        assert mkr.balanceOf(mkr_dai_pool) == 100.5 * 1e18
        assert dai.balanceOf(mkr_dai_pool) == 3_000 * 1e18

        assert mkr_dai_pool.totalCollateral() == 100 * 1e18

        # check tx events
        # event for transfer 0.5 collateral from bidder to pool
        transfer_collateral = tx.events["Transfer"][0][0]
        assert transfer_collateral["from"] == bidder
        assert transfer_collateral["to"] == mkr_dai_pool
        assert transfer_collateral["value"] == 0.5 * 1e18
        # event for transfer 600 quote token from pool to bidder
        transfer_quote = tx.events["Transfer"][1][0]
        assert transfer_quote["src"] == mkr_dai_pool
        assert transfer_quote["dst"] == bidder
        assert transfer_quote["wad"] == 2_000 * 1e18
        # custom purchase event
        pool_event = tx.events["Purchase"][0][0]
        assert pool_event["bidder"] == bidder
        assert pool_event["amount"] == 2_000 * 1e18
        assert pool_event["price"] == 4_000 * 1e18
        assert pool_event["collateral"] == 0.5 * 1e18

        with capsys.disabled():
            print("\n==================================")
            print("Gas estimations:")
            print("==================================")
            print(
                f"Purchase bid (reallocate to one bucket)           - {test_utils.get_usage(tx.gas_used)}"
            )


def test_purchase_bid_entire_amount(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    capsys,
    test_utils,
):
    lender = lenders[0]
    borrower = borrowers[0]
    bidder = borrowers[1]

    assert dai.balanceOf(lender) == 200_000 * 1e18
    mkr_dai_pool.addQuoteToken(1_000 * 1e18, 4000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(1_000 * 1e18, 3000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(5_000 * 1e18, 2000 * 1e18, {"from": lender})

    # borrower takes a loan of 1000 DAI from bucket 4000
    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
    mkr_dai_pool.borrow(1_000 * 1e18, 3000 * 1e18, {"from": borrower})
    # borrower takes a loan of 1000 DAI from bucket 3000
    mkr_dai_pool.borrow(1_000 * 1e18, 3000 * 1e18, {"from": borrower})
    assert mkr_dai_pool.lup() == 3_000 * 1e18

    # check bidder and pool balances
    assert mkr.balanceOf(bidder) == 100 * 1e18
    assert dai.balanceOf(bidder) == 0
    assert mkr.balanceOf(mkr_dai_pool) == 100 * 1e18
    assert dai.balanceOf(mkr_dai_pool) == 5_000 * 1e18
    assert mkr_dai_pool.totalCollateral() == 100 * 1e18

    # check 4000 bucket balance before purchase bid
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(4_000 * 1e18)
    # checked without time delay in forge
    assert 1_000 * 1e18 <= bucket_debt <= 1_001 * 1e18
    assert bucket_deposit == 0

    # check 3000 bucket balance before purchase bid
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(3_000 * 1e18)
    assert bucket_debt == 1_000 * 1e18
    assert bucket_deposit == 0

    # purchase 1000 bid - entire amount in 4000 bucket
    tx = mkr_dai_pool.purchaseBid(1_000 * 1e18, 4_000 * 1e18, {"from": bidder})

    assert mkr_dai_pool.lup() == 2_000 * 1e18

    # check 4000 bucket balance after purchase bid
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(4_000 * 1e18)
    assert 0 <= bucket_debt <= 0.1 * 1e18
    assert bucket_deposit == 0

    # check 3000 bucket balance
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(3_000 * 1e18)
    # TODO: properly check in forge tests
    assert 1_000 * 1e18 <= bucket_debt <= 1_001 * 1e18
    assert bucket_deposit == 0

    # check 2000 bucket balance
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(2_000 * 1e18)
    assert bucket_debt == 1_000 * 1e18
    assert bucket_deposit == 4_000 * 1e18

    # check bidder and pool balances
    assert mkr.balanceOf(bidder) == 99.75 * 1e18
    assert dai.balanceOf(bidder) == 1_000 * 1e18
    assert mkr.balanceOf(mkr_dai_pool) == 100.25 * 1e18
    assert dai.balanceOf(mkr_dai_pool) == 4_000 * 1e18
    # total collateral should not be incremented
    assert mkr_dai_pool.totalCollateral() == 100 * 1e18


def test_purchase_bid_not_enough_liquidity(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
):
    lender = lenders[0]
    borrower = borrowers[0]
    bidder = borrowers[1]

    assert dai.balanceOf(lender) == 200_000 * 1e18
    mkr_dai_pool.addQuoteToken(1_000 * 1e18, 4000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(1_000 * 1e18, 3000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(500 * 1e18, 2000 * 1e18, {"from": lender})

    # borrower takes a loan of 1000 DAI from bucket 4000
    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
    mkr_dai_pool.borrow(1_000 * 1e18, 3000 * 1e18, {"from": borrower})
    # borrower takes a loan of 1000 DAI from bucket 3000
    mkr_dai_pool.borrow(1_000 * 1e18, 3000 * 1e18, {"from": borrower})
    assert mkr_dai_pool.lup() == 3_000 * 1e18

    # should fail if trying to bid more than available liquidity (1000 vs 500)
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.purchaseBid(1_000 * 1e18, 4000 * 1e18, {"from": bidder})
    assert exc.value.revert_msg == "ajna/failed-to-reallocate"


def test_purchase_bid_undercollateralized(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
):
    lender = lenders[0]
    borrower = borrowers[0]
    bidder = borrowers[1]

    assert dai.balanceOf(lender) == 200_000 * 1e18
    mkr_dai_pool.addQuoteToken(1_000 * 1e18, 4000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(1_000 * 1e18, 3000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(2_000 * 1e18, 1 * 1e18, {"from": lender})

    # borrower takes a loan of 1000 DAI from bucket 4000
    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
    mkr_dai_pool.borrow(1_000 * 1e18, 3000 * 1e18, {"from": borrower})
    # borrower takes a loan of 1000 DAI from bucket 3000
    mkr_dai_pool.borrow(1_000 * 1e18, 3000 * 1e18, {"from": borrower})
    assert mkr_dai_pool.lup() == 3_000 * 1e18

    # should leave pool undercollateralized and fail
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.purchaseBid(1_000 * 1e18, 4000 * 1e18, {"from": bidder})
    assert exc.value.revert_msg == "ajna/pool-undercollateralized"
