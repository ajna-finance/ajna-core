import brownie
from brownie import Contract
import pytest


def test_5borrowers(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    test_utils,
):

    bucket_price = mkr_dai_pool.indexToPrice(7)

    # lender1 deposit 10000 DAI in bucket 7
    test_utils.assert_lender_quote_deposit(
        lenders[0], 10000 * 1e18, bucket_price, dai, mkr_dai_pool
    )
    # lender2 deposit 5000 DAI in bucket 7
    test_utils.assert_lender_quote_deposit(
        lenders[1], 5000 * 1e18, bucket_price, dai, mkr_dai_pool
    )
    # lender3 deposit 7000 DAI in bucket 7
    test_utils.assert_lender_quote_deposit(
        lenders[2], 7000 * 1e18, bucket_price, dai, mkr_dai_pool
    )
    # lender4 deposit 4000 DAI in bucket 7
    test_utils.assert_lender_quote_deposit(
        lenders[3], 4000 * 1e18, bucket_price, dai, mkr_dai_pool
    )

    # check bucket 7 balances on deposit 26000 DAI
    on_deposit, _, _, _ = mkr_dai_pool.bucketInfo(7)
    assert on_deposit == 26000 * 1e18

    # borrower1 deposit 10 MKR
    test_utils.assert_borrower_collateral_deposit(
        borrowers[0], 10 * 1e18, mkr, mkr_dai_pool
    )
    # borrower2 deposit 3 MKR
    test_utils.assert_borrower_collateral_deposit(
        borrowers[1], 3 * 1e18, mkr, mkr_dai_pool
    )
    # borrower3 deposit 5 MKR
    test_utils.assert_borrower_collateral_deposit(
        borrowers[2], 5 * 1e18, mkr, mkr_dai_pool
    )
    # borrower4 deposit 2 MKR
    test_utils.assert_borrower_collateral_deposit(
        borrowers[3], 2 * 1e18, mkr, mkr_dai_pool
    )
    # borrower5 deposit 4 MKR
    test_utils.assert_borrower_collateral_deposit(
        borrowers[4], 4 * 1e18, mkr, mkr_dai_pool
    )

    # borrower1 borrows 10000 DAI
    test_utils.assert_borrow(borrowers[0], 10000 * 1e18, dai, mkr_dai_pool)
    # borrower2 borrows 1000 DAI
    test_utils.assert_borrow(borrowers[1], 1000 * 1e18, dai, mkr_dai_pool)
    # borrower3 borrows 2000 DAI
    test_utils.assert_borrow(borrowers[2], 2000 * 1e18, dai, mkr_dai_pool)
    # borrower4 borrows 1000 DAI
    test_utils.assert_borrow(borrowers[3], 1000 * 1e18, dai, mkr_dai_pool)
    # borrower5 borrows 7000 DAI
    test_utils.assert_borrow(borrowers[4], 7000 * 1e18, dai, mkr_dai_pool)

    # check bucket 7 balances
    (
        on_deposit,
        total_debitors,
        debt_accumulator,
        _,
    ) = mkr_dai_pool.bucketInfo(7)
    assert on_deposit == 5000 * 1e18
    assert total_debitors == 5
    assert debt_accumulator == 21000 * 1e18

    # borrower1 debt should be 10000 DAI
    test_utils.assert_borrower_debt(borrowers[0], 7, 10000 * 1e18, mkr_dai_pool)
    # borrower2 debt should be 1000 DAI
    test_utils.assert_borrower_debt(borrowers[1], 7, 1000 * 1e18, mkr_dai_pool)
    # borrower3 debt should be 2000 DAI
    test_utils.assert_borrower_debt(borrowers[2], 7, 2000 * 1e18, mkr_dai_pool)
    # borrower4 debt should be 1000 DAI
    test_utils.assert_borrower_debt(borrowers[3], 7, 1000 * 1e18, mkr_dai_pool)
    # borrower5 debt should be 7000 DAI
    test_utils.assert_borrower_debt(borrowers[4], 7, 7000 * 1e18, mkr_dai_pool)

    # lender1 deposit 26000 DAI in bucket 9, covering entire 21000 DAI debt
    bucket_price = mkr_dai_pool.indexToPrice(9)
    assert dai.balanceOf(lenders[1]) > 26000 * 1e18
    mkr_dai_pool.depositQuoteToken(26000 * 1e18, bucket_price, {"from": lenders[1]})
    # check debt reallocated from bucket 7
    (
        bucket7_on_deposit,
        bucket7_total_debitors,
        bucket7_debt_accumulator,
        _,
    ) = mkr_dai_pool.bucketInfo(7)
    assert (
        bucket7_on_deposit == (21000 + 5000) * 1e18
    )  # on deposit = 21000 DAI repaid debt + existing 5000 DAI on deposit
    assert bucket7_total_debitors == 0
    assert bucket7_debt_accumulator == 0

    # check debt allocated to bucket 9
    (
        bucket9_on_deposit,
        bucket9_total_debitors,
        bucket9_debt_accumulator,
        _,
    ) = mkr_dai_pool.bucketInfo(9)
    assert (
        bucket9_on_deposit == (26000 - 21000) * 1e18
    )  # on deposit = 26000 DAI added by lender - 21000 DAI debt
    assert bucket9_total_debitors == 5  # all 5 borrowers moved
    assert (
        bucket9_debt_accumulator == 21000 * 1e18
    )  # 21000 DAI debt moved from bucket 7

    # debts for borrowers should remain same in bucket 9 and 0 in bucket 7
    # borrower1 debt should be 10000 DAI
    test_utils.assert_borrower_debt(borrowers[0], 7, 0, mkr_dai_pool)
    test_utils.assert_borrower_debt(borrowers[0], 9, 10000 * 1e18, mkr_dai_pool)
    # borrower2 debt should be 1000 DAI
    test_utils.assert_borrower_debt(borrowers[1], 7, 0, mkr_dai_pool)
    test_utils.assert_borrower_debt(borrowers[1], 9, 1000 * 1e18, mkr_dai_pool)
    # borrower3 debt should be 2000 DAI
    test_utils.assert_borrower_debt(borrowers[2], 7, 0, mkr_dai_pool)
    test_utils.assert_borrower_debt(borrowers[2], 9, 2000 * 1e18, mkr_dai_pool)
    # borrower4 debt should be 1000 DAI
    test_utils.assert_borrower_debt(borrowers[3], 7, 0, mkr_dai_pool)
    test_utils.assert_borrower_debt(borrowers[3], 9, 1000 * 1e18, mkr_dai_pool)
    # borrower5 debt should be 7000 DAI
    test_utils.assert_borrower_debt(borrowers[4], 7, 0, mkr_dai_pool)
    test_utils.assert_borrower_debt(borrowers[4], 9, 7000 * 1e18, mkr_dai_pool)

    # check DAI balance of pool inline with bucket deposits
    assert dai.balanceOf(mkr_dai_pool) == bucket7_on_deposit + bucket9_on_deposit


def _test_50borrowers(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    test_utils,
):
    assert mkr.balanceOf(borrowers[0]) == 100 * 10**18
    bucket_price = mkr_dai_pool.indexToPrice(7)

    # 4 lenders deposit 10000 DAI each in bucket 7
    for i in range(4):
        test_utils.assert_lender_quote_deposit(
            lenders[i], 10000 * 1e18, bucket_price, dai, mkr_dai_pool
        )

    # 50 lenders deposit 100 MKR each from bucket 7
    for i in range(50):
        test_utils.assert_borrower_collateral_deposit(
            borrowers[i], 100 * 1e18, mkr, mkr_dai_pool
        )

    # 50 lenders borrow 800 DAI each from bucket 7
    for i in range(50):
        test_utils.assert_borrow(borrowers[i], 800 * 1e18, dai, mkr_dai_pool)
