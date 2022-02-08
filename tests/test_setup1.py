import brownie
from brownie import Contract
import pytest


def test_5borrowers(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
):

    bucket_price = mkr_dai_pool.indexToPrice(7)

    # lender1 deposit 10000 DAI in bucket 7
    _assert_lender_quote_deposit(lenders[0], 10000 * 1e18, bucket_price, dai, mkr_dai_pool)
    # lender2 deposit 5000 DAI in bucket 7
    _assert_lender_quote_deposit(lenders[1], 5000 * 1e18, bucket_price, dai, mkr_dai_pool)
    # lender3 deposit 7000 DAI in bucket 7
    _assert_lender_quote_deposit(lenders[2], 7000 * 1e18, bucket_price, dai, mkr_dai_pool)
    # lender4 deposit 4000 DAI in bucket 7
    _assert_lender_quote_deposit(lenders[3], 4000 * 1e18, bucket_price, dai, mkr_dai_pool)

    # check bucket 7 balances on deposit 26000 DAI 
    on_deposit, _, _, _, _ = mkr_dai_pool.bucketInfoForAddress(7, lenders[0])
    assert on_deposit == 26000 * 1e18

    # borrower1 deposit 10 MKR
    _assert_borrower_collateral_deposit(borrowers[0], 10 * 1e18, mkr, mkr_dai_pool)
    # borrower2 deposit 3 MKR
    _assert_borrower_collateral_deposit(borrowers[1], 3 * 1e18, mkr, mkr_dai_pool)
    # borrower3 deposit 5 MKR
    _assert_borrower_collateral_deposit(borrowers[2], 5 * 1e18, mkr, mkr_dai_pool)
    # borrower4 deposit 2 MKR
    _assert_borrower_collateral_deposit(borrowers[3], 2 * 1e18, mkr, mkr_dai_pool)
    # borrower5 deposit 4 MKR
    _assert_borrower_collateral_deposit(borrowers[4], 4 * 1e18, mkr, mkr_dai_pool)

    # borrower1 borrows 10000 DAI
    _assert_borrow(borrowers[0], 10000 * 1e18, dai, mkr_dai_pool)
    # borrower2 borrows 1000 DAI
    _assert_borrow(borrowers[1], 1000 * 1e18, dai, mkr_dai_pool)
    # borrower3 borrows 2000 DAI
    _assert_borrow(borrowers[2], 2000 * 1e18, dai, mkr_dai_pool)
    # borrower4 borrows 1000 DAI
    _assert_borrow(borrowers[3], 1000 * 1e18, dai, mkr_dai_pool)
    # borrower5 borrows 7000 DAI
    _assert_borrow(borrowers[4], 7000 * 1e18, dai, mkr_dai_pool)

    # check bucket 7 balances
    on_deposit, total_debitors, borrower_debt, debt_accumulator, _ = mkr_dai_pool.bucketInfoForAddress(7, borrowers[0])
    assert on_deposit == 5000 * 1e18
    assert total_debitors == 5
    assert debt_accumulator == 21000 * 1e18

    # borrower1 debt should be 10000 DAI
    assert borrower_debt == 10000 * 1e18
    # borrower2 debt should be 1000 DAI
    assert _get_borrower_debt(borrowers[1], 7, mkr_dai_pool) == 1000 * 1e18
    # borrower3 debt should be 2000 DAI
    assert _get_borrower_debt(borrowers[2], 7, mkr_dai_pool) == 2000 * 1e18
    # borrower4 debt should be 1000 DAI
    assert _get_borrower_debt(borrowers[3], 7, mkr_dai_pool) == 1000 * 1e18
    # borrower5 debt should be 7000 DAI
    assert _get_borrower_debt(borrowers[4], 7, mkr_dai_pool) == 7000 * 1e18

    # lender1 deposit 26000 DAI in bucket 9, covering entire 21000 DAI debt
    bucket_price = mkr_dai_pool.indexToPrice(9)
    assert dai.balanceOf(lenders[1]) > 26000 * 1e18
    mkr_dai_pool.depositQuoteToken(26000 * 1e18, bucket_price, {"from": lenders[1]})
    # check debt reallocated from bucket 7
    bucket7_on_deposit, bucket7_total_debitors, borrower_debt, bucket7_debt_accumulator, _ = mkr_dai_pool.bucketInfoForAddress(7, borrowers[0])
    assert bucket7_on_deposit == (21000 + 5000) * 1e18 # on deposit = 21000 DAI repaid debt + existing 5000 DAI on deposit
    assert bucket7_total_debitors == 0
    assert bucket7_debt_accumulator == 0

    # check debt allocated to bucket 9
    bucket9_on_deposit, bucket9_total_debitors, borrower_debt, bucket9_debt_accumulator, _ = mkr_dai_pool.bucketInfoForAddress(9, borrowers[0])
    assert bucket9_on_deposit == (26000 - 21000) * 1e18 # on deposit = 26000 DAI added by lender - 21000 DAI debt
    assert bucket9_total_debitors == 5 # all 5 borrowers moved
    assert bucket9_debt_accumulator == 21000 * 1e18 # 21000 DAI debt moved from bucket 7

    # debts for borrowers should remain same in bucket 9 and 0 in bucket 7
    # borrower1 debt should be 10000 DAI
    assert _get_borrower_debt(borrowers[0], 7, mkr_dai_pool) == 0
    assert borrower_debt == 10000 * 1e18
    # borrower2 debt should be 1000 DAI
    assert _get_borrower_debt(borrowers[1], 7, mkr_dai_pool) == 0
    assert _get_borrower_debt(borrowers[1], 9, mkr_dai_pool) == 1000 * 1e18
    # borrower3 debt should be 2000 DAI
    assert _get_borrower_debt(borrowers[2], 7, mkr_dai_pool) == 0
    assert _get_borrower_debt(borrowers[2], 9, mkr_dai_pool) == 2000 * 1e18
    # borrower4 debt should be 1000 DAI
    assert _get_borrower_debt(borrowers[3], 7, mkr_dai_pool) == 0
    assert _get_borrower_debt(borrowers[3], 9, mkr_dai_pool) == 1000 * 1e18
    # borrower5 debt should be 7000 DAI
    assert _get_borrower_debt(borrowers[4], 7, mkr_dai_pool) == 0
    assert _get_borrower_debt(borrowers[4], 9, mkr_dai_pool) == 7000 * 1e18

    # check DAI balance of pool inline with bucket deposits
    assert dai.balanceOf(mkr_dai_pool) == bucket7_on_deposit + bucket9_on_deposit


def _assert_lender_quote_deposit(lender, amount, price, dai, mkr_dai_pool):
    balance = dai.balanceOf(lender)
    assert balance > amount
    mkr_dai_pool.depositQuoteToken(amount, price, {"from": lender})
    assert balance - dai.balanceOf(lender) ==  amount
    assert mkr_dai_pool.quoteBalances(lender) == amount


def _assert_borrower_collateral_deposit(borrower, amount, mkr, mkr_dai_pool):
    balance = mkr.balanceOf(borrower)
    assert balance > amount
    mkr_dai_pool.depositCollateral(amount, {"from": borrower})
    assert balance - mkr.balanceOf(borrower) ==  amount
    assert mkr_dai_pool.collateralBalances(borrower) == amount


def _assert_borrow(borrower, amount, dai, mkr_dai_pool):
    mkr_dai_pool.borrow(amount, {"from": borrower})
    assert dai.balanceOf(borrower) == amount


def _get_borrower_debt(borrower, bucket, mkr_dai_pool):
    _, _, borrower_debt, _, _ =mkr_dai_pool.bucketInfoForAddress(bucket, borrower)
    return borrower_debt