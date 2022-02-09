import brownie
from brownie import Contract
import pytest


def test_1borrower_from_multiple_buckets(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
):
    bucket3_price = mkr_dai_pool.indexToPrice(3)
    bucket8_price = mkr_dai_pool.indexToPrice(8)
    # lender1 deposit 10000 DAI in bucket 3
    _assert_lender_quote_deposit(
        lenders[0], 10000 * 1e18, bucket3_price, dai, mkr_dai_pool
    )
    # lender2 deposit 5000 DAI in bucket 8
    _assert_lender_quote_deposit(
        lenders[1], 5000 * 1e18, bucket8_price, dai, mkr_dai_pool
    )

    # borrower1 deposit 10 MKR
    _assert_borrower_collateral_deposit(borrowers[0], 10 * 1e18, mkr, mkr_dai_pool)

    # borrower1 tries to borrow 17000 DAI, tx should fail
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.borrow(17000 * 1e18, {"from": borrowers[0]})
    assert exc.value.revert_msg == "amount-remaining"

    # borrower1 borrows 11000 DAI (5000 DAI from bucket 8, 6000 DAI from bucket 3)
    _assert_borrow(borrowers[0], 11000 * 1e18, dai, mkr_dai_pool)

    # check borrower1 debt in bucket 8 is 5000 DAI
    assert _get_borrower_debt(borrowers[0], 8, mkr_dai_pool) == 5000 * 1e18
    # check borrower1 debt in bucket 3 is 6000 DAI
    assert _get_borrower_debt(borrowers[0], 3, mkr_dai_pool) == 6000 * 1e18


def _assert_lender_quote_deposit(lender, amount, price, dai, mkr_dai_pool):
    balance = dai.balanceOf(lender)
    assert balance > amount
    mkr_dai_pool.depositQuoteToken(amount, price, {"from": lender})
    assert balance - dai.balanceOf(lender) == amount
    assert mkr_dai_pool.quoteBalances(lender) == amount


def _assert_borrower_collateral_deposit(borrower, amount, mkr, mkr_dai_pool):
    balance = mkr.balanceOf(borrower)
    assert balance > amount
    mkr_dai_pool.depositCollateral(amount, {"from": borrower})
    assert balance - mkr.balanceOf(borrower) == amount
    assert mkr_dai_pool.collateralBalances(borrower) == amount


def _assert_borrow(borrower, amount, dai, mkr_dai_pool):
    mkr_dai_pool.borrow(amount, {"from": borrower})
    assert dai.balanceOf(borrower) == amount


def _get_borrower_debt(borrower, bucket, mkr_dai_pool):
    return mkr_dai_pool.userDebt(borrower, bucket)
