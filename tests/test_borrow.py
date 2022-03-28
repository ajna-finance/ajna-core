import brownie
from brownie import Contract
import pytest
from decimal import *
import inspect


def test_borrow(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    chain,
):
    lender = lenders[0]
    borrower1 = borrowers[0]

    # lender deposits 10000 DAI in 5 buckets each
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 3500 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 3000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 2500 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 2000 * 1e18, {"from": lender})

    # check pool balance
    assert mkr_dai_pool.totalQuoteToken() == 50_000 * 1e18
    assert mkr_dai_pool.hdp() == 4000 * 1e18

    # should fail if borrower wants to borrow a greater amount than in pool
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.borrow(60_000 * 1e18, 2000 * 1e18, {"from": borrower1})
    assert exc.value.revert_msg == "ajna/not-enough-liquidity"

    # should fail if not enough collateral deposited by borrower
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.borrow(10_000 * 1e18, 4000 * 1e18, {"from": borrower1})
    assert exc.value.revert_msg == "ajna/not-enough-collateral"

    # borrower deposit 100 MKR collateral
    mkr_dai_pool.addCollateral(10 * 1e18, {"from": borrower1})

    # should fail if stop price exceeded
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.borrow(15_000 * 1e18, 4000 * 1e18, {"from": borrower1})
    assert exc.value.revert_msg == "ajna/stop-price-exceeded"

    # should fail if not enough collateral to get the loan
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.borrow(40_000 * 1e18, 2000 * 1e18, {"from": borrower1})
    assert exc.value.revert_msg == "ajna/not-enough-collateral"

    # borrower deposit more 90 MKR collateral
    mkr_dai_pool.addCollateral(90 * 1e18, {"from": borrower1})
    # get 21000 DAI loan from 3 buckets
    # loan price should be 3000 DAI
    assert 3000 * 1e18 == mkr_dai_pool.estimatePriceForLoan(21_000 * 1e18)
    tx = mkr_dai_pool.borrow(21_000 * 1e18, 2500 * 1e18, {"from": borrower1})

    assert dai.balanceOf(borrower1) == 21_000 * 1e18
    assert dai.balanceOf(mkr_dai_pool) == 29_000 * 1e18
    assert mkr_dai_pool.hdp() == 4000 * 1e18
    assert mkr_dai_pool.lup() == 3000 * 1e18
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(3000 * 1e18)
    assert bucket_deposit == 9_000 * 1e18
    assert mkr_dai_pool.totalDebt() == 21_000 * 1e18
    # check borrower
    (debt, col_deposited, _) = mkr_dai_pool.borrowers(borrower1)
    assert debt == 21_000 * 1e18
    assert col_deposited == 100 * 1e18
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == mkr_dai_pool
    assert transfer_event["dst"] == borrower1
    assert transfer_event["wad"] == 21_000 * 1e18
    pool_event = tx.events["Borrow"][0][0]
    assert pool_event["borrower"] == borrower1
    assert pool_event["lup"] == 3000 * 1e18
    assert pool_event["amount"] == 21_000 * 1e18

    chain.sleep(8200)
    chain.mine()

    # borrow remaining 9000 DAI from LUP
    tx = mkr_dai_pool.borrow(9_000 * 1e18, 2500 * 1e18, {"from": borrower1})

    assert dai.balanceOf(borrower1) == 30_000 * 1e18
    assert dai.balanceOf(mkr_dai_pool) == 20_000 * 1e18
    assert mkr_dai_pool.hdp() == 4000 * 1e18

    # check debt paid in 2500 DAI bucket
    assert mkr_dai_pool.lup() == 2500 * 1e18
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(2500 * 1e18)
    assert format(bucket_debt / 1e18, ".3f") == format(0.013, ".3f")
    # check debt paid in 3000 DAI bucket
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(3000 * 1e18)
    assert bucket_debt == 10_000 * 1e18
    # check debt paid in 3500 DAI bucket
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(3500 * 1e18)
    assert bucket_debt == 10_000 * 1e18
    # check debt paid in 4000 DAI bucket
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(4000 * 1e18)
    assert bucket_debt == 10_000 * 1e18
    assert round(mkr_dai_pool.totalDebt() * 1e-18, 3) == 30000.273
    # check borrower
    (debt, col_deposited, _) = mkr_dai_pool.borrowers(borrower1)
    # TODO: properly checked in forge tests
    assert 30_000 * 1e18 <= debt <= 30_001 * 1e18
    assert col_deposited == 100 * 1e18
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == mkr_dai_pool
    assert transfer_event["dst"] == borrower1
    assert transfer_event["wad"] == 9_000 * 1e18
    pool_event = tx.events["Borrow"][0][0]
    assert pool_event["borrower"] == borrower1
    assert pool_event["lup"] == 2500 * 1e18
    assert pool_event["amount"] == 9_000 * 1e18

    # deposit at 5000 and pay back entire debt
    mkr_dai_pool.addQuoteToken(40_000 * 1e18, 5000 * 1e18, {"from": lender})
    # check debt paid for 2500 DAI bucket
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(2500 * 1e18)
    assert bucket_deposit == 10_000 * 1e18
    assert bucket_debt == 0
    # check debt paid for 3000 DAI bucket
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(3000 * 1e18)
    assert bucket_deposit == 10_000 * 1e18
    assert bucket_debt == 0
    # check debt paid for 3500 DAI bucket
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(3500 * 1e18)
    assert bucket_deposit == 10_000 * 1e18
    assert bucket_debt == 0
    # check debt paid for 4000 DAI bucket
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(4000 * 1e18)
    assert bucket_deposit == 10_000 * 1e18
    assert bucket_debt == 0
    # check 5000 DAI bucket, accumulated all 30000 DAI debt, deposited 40000 DAI
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        _,
        _,
    ) = mkr_dai_pool.bucketAt(5000 * 1e18)
    assert bucket_deposit == 40_000 * 1e18
    assert format(bucket_debt / 1e18, ".3f") == format(30000.273, ".3f")


def test_pool_undercollateralization(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    chain,
):

    lender = lenders[0]
    borrower1 = borrowers[0]
    borrower2 = borrowers[1]

    # lender deposits 100000 DAI in 2 buckets each
    mkr_dai_pool.addQuoteToken(100_000 * 1e18, 2000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(50_000 * 1e18, 1000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(50_000 * 1e18, 500 * 1e18, {"from": lender})

    mkr_dai_pool.addCollateral(51 * 1e18, {"from": borrower1})
    mkr_dai_pool.borrow(100_000 * 1e18, 1000 * 1e18, {"from": borrower1})
    mkr_dai_pool.addCollateral(51 * 1e18, {"from": borrower2})
    # should fail when taking a loan of 50000 DAI that will drive pool undercollateralized

    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.borrow(50_000 * 1e18, 1000 * 1e18, {"from": borrower2})
    assert exc.value.revert_msg == "ajna/pool-undercollateralized"


def test_collateral_validation(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    chain,
):
    lender = lenders[0]
    borrower1 = borrowers[0]

    # lender deposits 10000 DAI in 5 buckets each
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 13.537 * 1e18, {"from": lender})
    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower1})

    tx = mkr_dai_pool.borrow(1_000 * 1e18, 13.537 * 1e18, {"from": borrower1})
    # should not fail
    assert tx.status.value == 1


def test_borrow_gas(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    capsys,
    test_utils,
):
    with test_utils.GasWatcher(['borrow', 'addCollateral', 'addQuoteToken']):
        txes = []
        for i in range(12):
            mkr_dai_pool.addQuoteToken(
                10_000 * 1e18, (4000 - 10 * i) * 1e18, {"from": lenders[0]}
            )

        mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrowers[0]})

        # borrow 10_000 DAI from single bucket (LUP)
        tx_one_bucket = mkr_dai_pool.borrow(
            10_000 * 1e18, 4000 * 1e18, {"from": borrowers[0]}
        )
        tx_reallocate_debt_one_bucket = mkr_dai_pool.addQuoteToken(
            10_000 * 1e18, 5000 * 1e18, {"from": lenders[0]}
        )
        txes.append(tx_one_bucket)
        txes.append(tx_reallocate_debt_one_bucket)

        # borrow 101_000 DAI from 11 buckets
        tx_11_buckets = mkr_dai_pool.borrow(
            101_000 * 1e18, 1000 * 1e18, {"from": borrowers[0]}
        )
        tx_reallocate_debt_11_buckets = mkr_dai_pool.addQuoteToken(
            150_000 * 1e18, 6000 * 1e18, {"from": lenders[1]}
        )
        txes.append(tx_11_buckets)

        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]}):")
            print("==================================")
            print(
                f"Borrow single bucket           - {test_utils.get_usage(tx_one_bucket.gas_used)}\n"
                f"Reallocate debt single bucket  - {test_utils.get_usage(tx_reallocate_debt_one_bucket.gas_used)}"
            )
            print(
                f"Borrow from multiple buckets (11)      - {test_utils.get_usage(tx_11_buckets.gas_used)}\n"
                f"Reallocate debt multiple buckets (11)  - {test_utils.get_usage(tx_reallocate_debt_11_buckets.gas_used)}"
            )
    assert True
