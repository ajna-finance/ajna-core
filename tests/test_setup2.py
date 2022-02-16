import brownie
from brownie import Contract
import pytest


def test_5borrowers_2buckets(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    test_utils,
):

    bucket1_price = mkr_dai_pool.indexToPrice(1)
    bucket2_price = mkr_dai_pool.indexToPrice(2)

    # lenders lend 41000 DAI in total, 26000 DAI in bucket 1 and 15000 DAI in bucket
    # lender1 deposit 10000 DAI in bucket 1 and 5000 DAI in bucket 2
    mkr_dai_pool.depositQuoteToken(10000 * 1e18, bucket1_price, {"from": lenders[0]})
    mkr_dai_pool.depositQuoteToken(5000 * 1e18, bucket2_price, {"from": lenders[0]})
    # lender2 deposit 5000 DAI in bucket 1 and 3000 DAI in bucket 2
    mkr_dai_pool.depositQuoteToken(5000 * 1e18, bucket1_price, {"from": lenders[1]})
    mkr_dai_pool.depositQuoteToken(3000 * 1e18, bucket2_price, {"from": lenders[1]})
    # lender3 deposit 7000 DAI in bucket 1 and 2000 DAI in bucket 2
    mkr_dai_pool.depositQuoteToken(7000 * 1e18, bucket1_price, {"from": lenders[2]})
    mkr_dai_pool.depositQuoteToken(2000 * 1e18, bucket2_price, {"from": lenders[2]})
    # lender4 deposit 4000 DAI in bucket 1 and 5000 DAI in bucket 2
    mkr_dai_pool.depositQuoteToken(4000 * 1e18, bucket1_price, {"from": lenders[3]})
    mkr_dai_pool.depositQuoteToken(5000 * 1e18, bucket2_price, {"from": lenders[3]})

    # check bucket 1 balances on deposit 26000 DAI
    on_deposit, _, _, _ = mkr_dai_pool.bucketInfo(1)
    assert on_deposit == 26000 * 1e18
    # check bucket 2 balances on deposit 15000 DAI
    on_deposit, _, _, _ = mkr_dai_pool.bucketInfo(2)
    assert on_deposit == 15000 * 1e18

    # 5 borrowers deposit 50 MKR each as collateral
    for borrower in range(5):
        test_utils.assert_borrower_collateral_deposit(
            borrowers[borrower], 50 * 1e18, mkr, mkr_dai_pool
        )

    # borrowers borrow 40000 DAI in total, 8000 DAI each
    for borrower in range(5):
        test_utils.assert_borrow(borrowers[borrower], 8000 * 1e18, dai, mkr_dai_pool)

    # check bucket 1 balances
    (
        on_deposit,
        total_debitors,
        debt_accumulator,
        _,
    ) = mkr_dai_pool.bucketInfo(1)
    assert on_deposit == 1000 * 1e18
    assert total_debitors == 4
    assert debt_accumulator == 25000 * 1e18

    # check bucket 2 balances
    (
        on_deposit,
        total_debitors,
        debt_accumulator,
        _,
    ) = mkr_dai_pool.bucketInfo(2)
    assert on_deposit == 0
    assert total_debitors == 2
    assert debt_accumulator == 15000 * 1e18

    # borrower1 debt in bucket 1 should be 8000 DAI
    test_utils.assert_borrower_debt(borrowers[0], 2, 8000 * 1e18, mkr_dai_pool)
    # borrower2 debt in bucket 1 should be 7000 DAI
    test_utils.assert_borrower_debt(borrowers[1], 2, 7000 * 1e18, mkr_dai_pool)
    # borrower2 debt in bucket 2 should be 1000 DAI
    test_utils.assert_borrower_debt(borrowers[1], 1, 1000 * 1e18, mkr_dai_pool)
    # borrower3 debt in bucket 1 should be 8000 DAI
    test_utils.assert_borrower_debt(borrowers[2], 1, 8000 * 1e18, mkr_dai_pool)
    # borrower4 debt in bucket 1 should be 8000 DAI
    test_utils.assert_borrower_debt(borrowers[3], 1, 8000 * 1e18, mkr_dai_pool)
    # borrower5 debt in bucket 1 should be 8000 DAI
    test_utils.assert_borrower_debt(borrowers[4], 1, 8000 * 1e18, mkr_dai_pool)

    # lender5 deposit 50000 DAI in bucket 3, covering entire 41000 DAI debt from b1 and b2
    bucket3_price = mkr_dai_pool.indexToPrice(3)
    mkr_dai_pool.depositQuoteToken(50000 * 1e18, bucket3_price, {"from": lenders[4]})
    # check bucket 1 balances
    (
        on_deposit,
        total_debitors,
        debt_accumulator,
        _,
    ) = mkr_dai_pool.bucketInfo(1)
    assert on_deposit == 26000 * 1e18
    assert total_debitors == 0
    assert debt_accumulator == 0

    # check bucket 2 balances
    (
        on_deposit,
        total_debitors,
        debt_accumulator,
        _,
    ) = mkr_dai_pool.bucketInfo(2)
    assert on_deposit == 15000 * 1e18
    assert total_debitors == 0
    assert debt_accumulator == 0

    # check bucket 3 balances
    (
        on_deposit,
        total_debitors,
        debt_accumulator,
        _,
    ) = mkr_dai_pool.bucketInfo(3)
    assert on_deposit == 10000 * 1e18
    assert total_debitors == 5
    assert debt_accumulator == 40000 * 1e18

    # all 5 borrowers debt in bucket 3 should be 8000 DAI
    for borrower in range(5):
        test_utils.assert_borrower_debt(
            borrowers[borrower], 3, 8000 * 1e18, mkr_dai_pool
        )
