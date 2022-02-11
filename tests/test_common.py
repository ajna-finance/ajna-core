import brownie
from brownie import Contract
import pytest


def test_borrow_multiple_buckets(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    test_utils,
):
    bucket3_price = mkr_dai_pool.indexToPrice(3)
    bucket8_price = mkr_dai_pool.indexToPrice(8)
    # lender1 deposit 10000 DAI in bucket 3
    test_utils.assert_lender_quote_deposit(
        lenders[0], 10000 * 1e18, bucket3_price, dai, mkr_dai_pool
    )
    # lender2 deposit 5000 DAI in bucket 8
    test_utils.assert_lender_quote_deposit(
        lenders[1], 5000 * 1e18, bucket8_price, dai, mkr_dai_pool
    )

    # borrower1 deposit 10 MKR
    test_utils.assert_borrower_collateral_deposit(
        borrowers[0], 10 * 1e18, mkr, mkr_dai_pool
    )

    # borrower1 tries to borrow 17000 DAI, tx should fail
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.borrow(17000 * 1e18, {"from": borrowers[0]})
    assert exc.value.revert_msg == "amount-remaining"

    # borrower1 borrows 11000 DAI (5000 DAI from bucket 8, 6000 DAI from bucket 3)
    test_utils.assert_borrow(borrowers[0], 11000 * 1e18, dai, mkr_dai_pool)

    # check borrower1 debt in bucket 8 is 5000 DAI
    test_utils.assert_borrower_debt(borrowers[0], 8, 5000 * 1e18, mkr_dai_pool)
    # check borrower1 debt in bucket 3 is 6000 DAI
    test_utils.assert_borrower_debt(borrowers[0], 3, 6000 * 1e18, mkr_dai_pool)


def test_lend_multiple_buckets(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    test_utils,
):
    lender = lenders[0]
    borrower = borrowers[0]
    bucket1_price = mkr_dai_pool.indexToPrice(1)
    bucket2_price = mkr_dai_pool.indexToPrice(2)
    bucket3_price = mkr_dai_pool.indexToPrice(3)
    bucket4_price = mkr_dai_pool.indexToPrice(4)

    # lender deposit 1000 DAI in bucket 1
    mkr_dai_pool.depositQuoteToken(1000 * 1e18, bucket1_price, {"from": lender})
    # lender deposit 2000 DAI in bucket 2
    mkr_dai_pool.depositQuoteToken(2000 * 1e18, bucket2_price, {"from": lender})
    # lender deposit 4000 DAI in bucket 3
    mkr_dai_pool.depositQuoteToken(4000 * 1e18, bucket3_price, {"from": lender})
    assert mkr_dai_pool.quoteBalances(lender) == 7000 * 1e18

    # borrower deposit 10 MKR
    test_utils.assert_borrower_collateral_deposit(
        borrower, 20 * 1e18, mkr, mkr_dai_pool
    )
    # borrower borrows all 7000 DAI from all buckets
    test_utils.assert_borrow(borrower, 7000 * 1e18, dai, mkr_dai_pool)

    # check borrower debt in bucket 1 is 1000 DAI
    test_utils.assert_borrower_debt(borrower, 1, 1000 * 1e18, mkr_dai_pool)
    # check borrower debt in bucket 2 is 2000 DAI
    test_utils.assert_borrower_debt(borrower, 2, 2000 * 1e18, mkr_dai_pool)
    # check borrower debt in bucket 3 is 4000 DAI
    test_utils.assert_borrower_debt(borrower, 3, 4000 * 1e18, mkr_dai_pool)

    # lender deposit 3000 DAI in bucket 4 (should cover debt in bucket1 and bucket2)
    mkr_dai_pool.depositQuoteToken(3000 * 1e18, bucket4_price, {"from": lender})
    assert mkr_dai_pool.quoteBalances(lender) == 10000 * 1e18
    # bucket 1 on deposit 1000 DAI and no debt / no debitors
    test_utils.assert_bucket(1, 1000 * 1e18, 0, 0, mkr_dai_pool)
    # bucket 2 on deposit 2000 DAI and no debt / no debitors
    test_utils.assert_bucket(2, 2000 * 1e18, 0, 0, mkr_dai_pool)
    # bucket 3 no deposit and 4000 DAI debt / 1 debitor
    test_utils.assert_bucket(3, 0, 4000 * 1e18, 1, mkr_dai_pool)
    # bucket 4 no deposit and 3000 DAI debt / 1 debitor
    test_utils.assert_bucket(4, 0, 3000 * 1e18, 1, mkr_dai_pool)

    # lender deposit 4000 DAI in bucket 4 (should cover debt in bucket 3)
    mkr_dai_pool.depositQuoteToken(4000 * 1e18, bucket4_price, {"from": lender})
    assert mkr_dai_pool.quoteBalances(lender) == 14000 * 1e18
    # bucket 1 on deposit 1000 DAI and no debt / no debitors
    test_utils.assert_bucket(1, 1000 * 1e18, 0, 0, mkr_dai_pool)
    # bucket 2 on deposit 2000 DAI and no debt / no debitors
    test_utils.assert_bucket(2, 2000 * 1e18, 0, 0, mkr_dai_pool)
    # bucket 3 on deposit 4000 DAI and no debt / no debitors
    test_utils.assert_bucket(3, 4000 * 1e18, 0, 0, mkr_dai_pool)
    # bucket 4 no deposit and 7000 DAI debt / 1 debitor
    test_utils.assert_bucket(4, 0, 7000 * 1e18, 1, mkr_dai_pool)
