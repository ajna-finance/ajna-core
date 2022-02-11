import brownie
from brownie import Contract
import pytest


def test_5borrowers_10buckets(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    test_utils,
):

    bucket1_price = mkr_dai_pool.indexToPrice(1)
    bucket2_price = mkr_dai_pool.indexToPrice(2)

    # lenders deposit DAI in 10 buckets
    for bucket in range(1, 11):
        bucket_price = mkr_dai_pool.indexToPrice(bucket)
        # lender 1 deposit 5000 DAI in each of 10 buckets
        mkr_dai_pool.depositQuoteToken(5000 * 1e18, bucket_price, {"from": lenders[0]})
        # lender 2 deposit 3000 DAI in each of 10 buckets
        mkr_dai_pool.depositQuoteToken(3000 * 1e18, bucket_price, {"from": lenders[1]})
        # lender 3 deposit 4000 DAI in each of 10 buckets
        mkr_dai_pool.depositQuoteToken(4000 * 1e18, bucket_price, {"from": lenders[2]})
        # lender 4 deposit 7000 DAI in each of 10 buckets
        mkr_dai_pool.depositQuoteToken(7000 * 1e18, bucket_price, {"from": lenders[3]})

    assert dai.balanceOf(mkr_dai_pool) == 190000 * 1e18

    # check buckets balance
    for bucket in range(1, 11):
        # check each bucket on deposit 19000 DAI
        on_deposit, _, _, _ = mkr_dai_pool.bucketInfo(bucket)
        assert on_deposit == 19000 * 1e18

    # 5 borrowers deposit 50 MKR each as collateral
    for borrower in range(5):
        test_utils.assert_borrower_collateral_deposit(
            borrowers[borrower], 50 * 1e18, mkr, mkr_dai_pool
        )

    # each borrower borrows 38000 DAI
    for borrower in range(5):
        test_utils.assert_borrow(borrowers[borrower], 38000 * 1e18, dai, mkr_dai_pool)

    # each borrower borrowed from 2 consecutive buckets (one debitor per bucket)
    for bucket in range(1, 11):
        (
            on_deposit,
            total_debitors,
            debt_accumulator,
            _,
        ) = mkr_dai_pool.bucketInfo(bucket)
        assert on_deposit == 0
        assert total_debitors == 1
        assert debt_accumulator == 19000 * 1e18

    # borrower1 debt in bucket 10 should be 19000 DAI
    test_utils.assert_borrower_debt(borrowers[0], 10, 19000 * 1e18, mkr_dai_pool)
    # borrower1 debt in bucket 9 should be 19000 DAI
    test_utils.assert_borrower_debt(borrowers[0], 9, 19000 * 1e18, mkr_dai_pool)
    # borrower5 debt in bucket 2 should be 19000 DAI
    test_utils.assert_borrower_debt(borrowers[4], 2, 19000 * 1e18, mkr_dai_pool)
    # borrower5 debt in bucket 1 should be 19000 DAI
    test_utils.assert_borrower_debt(borrowers[4], 1, 19000 * 1e18, mkr_dai_pool)

    # lender5 deposit 200000 DAI in bucket 11, covering entire 190000 DAI debt
    bucket11_price = mkr_dai_pool.indexToPrice(11)
    mkr_dai_pool.depositQuoteToken(200000 * 1e18, bucket11_price, {"from": lenders[4]})

    for bucket in range(1, 11):
        (
            on_deposit,
            total_debitors,
            debt_accumulator,
            _,
        ) = mkr_dai_pool.bucketInfo(bucket)
        assert on_deposit == 19000 * 1e18
        assert total_debitors == 0
        assert debt_accumulator == 0

    # check bucket 11 balances
    (
        on_deposit,
        total_debitors,
        debt_accumulator,
        _,
    ) = mkr_dai_pool.bucketInfo(11)
    assert on_deposit == 10000 * 1e18
    assert total_debitors == 5
    assert debt_accumulator == 190000 * 1e18

    # all 5 borrowers debt in bucket 11 should be 38000 DAI
    for borrower in range(5):
        test_utils.assert_borrower_debt(
            borrowers[borrower], 11, 38000 * 1e18, mkr_dai_pool
        )
