import brownie
from brownie import Contract
import pytest
from decimal import *


def test_claim_collateral(
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

    # should fail if invalid price
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.claimCollateral(1_000 * 1e18, 1000, {"from": lender})
    assert exc.value.revert_msg == "ajna/invalid-bucket-price"

    # should fail if no lp tokens in bucket
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.claimCollateral(1 * 1e18, 4000 * 1e18, {"from": lender})
    assert exc.value.revert_msg == "ajna/no-claim-to-bucket"

    # deposit DAI in 3 buckets
    mkr_dai_pool.addQuoteToken(3_000 * 1e18, 4000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(4_000 * 1e18, 3000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(5_000 * 1e18, 1000 * 1e18, {"from": lender})

    assert mkr_dai_pool.lpBalance(lender, 4_000 * 1e18) == 3_000 * 1e18
    assert mkr_dai_pool.lpBalance(lender, 3_000 * 1e18) == 4_000 * 1e18
    assert mkr_dai_pool.lpBalance(lender, 1_000 * 1e18) == 5_000 * 1e18

    # should fail if claiming collateral if no purchase bid was done on bucket
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.claimCollateral(1 * 1e18, 4000 * 1e18, {"from": lender})
    assert exc.value.revert_msg == "ajna/insufficient-amount-to-claim"

    # borrower takes a loan of 4000 DAI
    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
    mkr_dai_pool.borrow(4_000 * 1e18, 3000 * 1e18, {"from": borrower})
    assert mkr_dai_pool.lup() == 3_000 * 1e18

    # check 3000 bucket balance before purchase Bid
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        lpOutstanding,
    ) = mkr_dai_pool.bucketAt(3000 * 1e18)
    # TODO: properly check in forge tests
    assert 1_000 * 1e18 <= bucket_debt <= 1_001 * 1e18
    assert bucket_deposit == 4_000 * 1e18
    assert lpOutstanding == 4_000 * 1e18

    mkr_dai_pool.purchaseBid(1_500 * 1e18, 3000 * 1e18, {"from": bidder})

    assert mkr_dai_pool.lpBalance(lender, 3_000 * 1e18) == 4_000 * 1e18
    assert mkr.balanceOf(lender) == 0
    assert dai.balanceOf(lender) == 188_000 * 1e18
    assert mkr.balanceOf(mkr_dai_pool) == 100.5 * 1e18
    assert dai.balanceOf(mkr_dai_pool) == 6_500 * 1e18
    assert mkr_dai_pool.totalCollateral() == 100 * 1e18

    # should fail if claiming a larger amount than available in bucket
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.claimCollateral(2 * 1e18, 3000 * 1e18, {"from": lender})
    assert exc.value.revert_msg == "ajna/insufficient-amount-to-claim"

    tx = mkr_dai_pool.claimCollateral(0.5 * 1e18, 3_000 * 1e18, {"from": lender})

    # check 3000 bucket balance after claim collateral
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        lpOutstanding,
    ) = mkr_dai_pool.bucketAt(3000 * 1e18)
    # TODO: properly check in forge tests
    assert 1_000 * 1e18 <= bucket_debt <= 1_001 * 1e18
    assert bucket_deposit == 2_500 * 1e18
    assert lpOutstanding == 2_500 * 1e18

    # claimer lp tokens for pool should be diminished
    assert mkr_dai_pool.lpBalance(lender, 3_000 * 1e18) == 2_500 * 1e18
    # claimer collateral balance should increase with claimed amount
    assert mkr.balanceOf(lender) == 0.5 * 1e18
    # claimer quote token balance should stay the same
    assert dai.balanceOf(lender) == 188_000 * 1e18
    assert mkr.balanceOf(mkr_dai_pool) == 100 * 1e18
    assert dai.balanceOf(mkr_dai_pool) == 6_500 * 1e18
    assert mkr_dai_pool.totalCollateral() == 100 * 1e18

    # check tx events
    # event for transfer 0.5 collateral from pool
    transfer_collateral = tx.events["Transfer"][0][0]
    assert transfer_collateral["from"] == mkr_dai_pool
    assert transfer_collateral["to"] == lender
    assert transfer_collateral["value"] == 0.5 * 1e18
    # custom claim event
    pool_event = tx.events["ClaimCollateral"][0][0]
    assert pool_event["claimer"] == lender
    assert pool_event["price"] == 3_000 * 1e18
    assert pool_event["amount"] == 0.5 * 1e18
    assert pool_event["lps"] == 1_500 * 1e18

    with capsys.disabled():
        print("\n==================================")
        print("Gas estimations:")
        print("==================================")
        print(f"Claim collateral           - {test_utils.get_gas_usage(tx.gas_used)}")
        print("==================================")
