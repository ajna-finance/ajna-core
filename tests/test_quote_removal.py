import brownie
from brownie import Contract
import pytest
from decimal import *
import inspect


def test_quote_removal_no_loan(
    lenders,
    mkr_dai_pool,
    dai,
    chain,
):

    lender = lenders[0]

    # deposit 10000 DAI at price of 1 MKR = 4000 DAI
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert dai.balanceOf(mkr_dai_pool) == 10_000 * 1e18
    assert dai.balanceOf(lender) == 190_000 * 1e18
    assert mkr_dai_pool.totalQuoteToken() == 10_000 * 1e18

    # should fail if trying to remove more than lended
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.removeQuoteToken(20_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert exc.value.revert_msg == "ajna/amount-greater-than-claimable"

    # forward time so lp tokens to accumulate
    chain.sleep(82000)
    chain.mine()

    # remove 10000 DAI at price of 1 MKR = 4000 DAI
    tx = mkr_dai_pool.removeQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert dai.balanceOf(mkr_dai_pool) == 0
    assert dai.balanceOf(lender) == 200_000 * 1e18
    assert mkr_dai_pool.totalQuoteToken() == 0
    # check bucket balance
    (
        _,
        _,
        _,
        bucket_deposit,
        _,
        snapshot,
        lpOutstanding,
        _,
    ) = mkr_dai_pool.bucketAt(4000 * 1e18)
    assert bucket_deposit == 0
    assert snapshot == 1 * 1e18
    assert lpOutstanding == 0

    # lender removed their entire quote, so shouldn't have LP tokens
    assert mkr_dai_pool.lpBalance(lender, 4000 * 1e18) == 0
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == mkr_dai_pool
    assert transfer_event["dst"] == lender
    assert transfer_event["wad"] == 10_000 * 1e18
    pool_event = tx.events["RemoveQuoteToken"][0][0]
    assert pool_event["amount"] == 10_000 * 1e18
    assert pool_event["lender"] == lender
    assert pool_event["price"] == 4000 * 1e18
    assert pool_event["lup"] == 0


def test_quote_removal_loan_not_paid_back(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    chain,
):

    lender = lenders[0]
    borrower = borrowers[0]

    # deposit 10000 DAI at price of 1 MKR = 4000 DAI
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert dai.balanceOf(mkr_dai_pool) == 10_000 * 1e18
    assert dai.balanceOf(lender) == 190_000 * 1e18
    assert mkr_dai_pool.totalQuoteToken() == 10_000 * 1e18
    assert mkr_dai_pool.lpBalance(lender, 4000 * 1e18) == 10_000 * 1e18

    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
    mkr_dai_pool.borrow(5_000 * 1e18, 4000 * 1e18, {"from": borrower})
    assert mkr_dai_pool.totalQuoteToken() == 5_000 * 1e18

    # should fail if trying to remove entire amount lended
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.removeQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert exc.value.revert_msg == "ajna/failed-to-reallocate"

    # remove 4000 DAI at price of 1 MKR = 4000 DAI
    tx = mkr_dai_pool.removeQuoteToken(4_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert dai.balanceOf(mkr_dai_pool) == 1_000 * 1e18
    assert dai.balanceOf(lender) == 194_000 * 1e18
    assert mkr_dai_pool.totalQuoteToken() == 1_000 * 1e18
    # check bucket balance
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        lpOutstanding,
        _,
    ) = mkr_dai_pool.bucketAt(4000 * 1e18)
    assert bucket_deposit == 1_000 * 1e18
    # tested without delay in forge
    assert 5_000 * 1e18 <= bucket_debt <= 5_001 * 1e18
    # due to delay in brownie, the removeQuoteToken call required slightly less 
    # LP to withdraw quote; tested without delay in forge
    assert 6_000 * 1e18 <= lpOutstanding <= 6_001 * 1e18
    assert 6_000 * 1e18 <= mkr_dai_pool.lpBalance(lender, 4000 * 1e18) <= 6_001 * 1e18
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == mkr_dai_pool
    assert transfer_event["dst"] == lender
    assert transfer_event["wad"] == 4_000 * 1e18
    pool_event = tx.events["RemoveQuoteToken"][0][0]
    assert pool_event["amount"] == 4_000 * 1e18
    assert pool_event["lender"] == lender
    assert pool_event["price"] == 4000 * 1e18
    assert pool_event["lup"] == 4000 * 1e18


def test_quote_removal_loan_paid_back(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    chain,
):

    lender = lenders[0]
    borrower = borrowers[0]

    # deposit 10000 DAI at price of 1 MKR = 4000 DAI
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})

    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
    mkr_dai_pool.borrow(10_000 * 1e18, 4000 * 1e18, {"from": borrower})
    assert mkr_dai_pool.totalQuoteToken() == 0

    dai.transfer(borrower, 1 * 1e18, {"from": lenders[1]})
    mkr_dai_pool.repay(10_001 * 1e18, {"from": borrower})

    # forward time
    chain.sleep(82000)
    chain.mine()

    # remove all lended amount
    tx = mkr_dai_pool.removeQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert format(dai.balanceOf(mkr_dai_pool) / 1e18, ".3f") == format(0, ".3f")
    assert dai.balanceOf(lender) == 200_000 * 1e18
    assert 0 <= mkr_dai_pool.totalQuoteToken() <= 1 * 1e18
    # check bucket balance
    (
        _,
        _,
        _,
        bucket_deposit,
        bucket_debt,
        _,
        lpOutstanding,
        _,
    ) = mkr_dai_pool.bucketAt(4000 * 1e18)
    # in forge test, no time passes between borrow and repayment
    assert bucket_deposit < 0.0001 * 1e18
    assert bucket_debt == 0
    assert lpOutstanding == 0
    assert mkr_dai_pool.lpBalance(lender, 4000 * 1e18) == 0
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == mkr_dai_pool
    assert transfer_event["dst"] == lender
    assert transfer_event["wad"] == 10_000 * 1e18
    pool_event = tx.events["RemoveQuoteToken"][0][0]
    assert pool_event["amount"] == 10_000 * 1e18
    assert pool_event["lender"] == lender
    assert pool_event["price"] == 4000 * 1e18
    assert pool_event["lup"] == 4000 * 1e18


def test_quote_removal_from_lup_with_reallocation(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    capsys,
    test_utils,
):

    with test_utils.GasWatcher(["removeQuoteToken", "addCollateral", "addQuoteToken"]):
        lender = lenders[0]
        borrower = borrowers[0]

        assert dai.balanceOf(lender) == 200_000 * 1e18
        # deposit 3400 DAI at price of 1 MKR = 4000 DAI and 1 MKR = 3000
        mkr_dai_pool.addQuoteToken(3_400 * 1e18, 4000 * 1e18, {"from": lender})
        mkr_dai_pool.addQuoteToken(3_400 * 1e18, 3000 * 1e18, {"from": lender})

        # borrower takes a loan of 3000 DAI
        mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
        mkr_dai_pool.borrow(3_000 * 1e18, 4000 * 1e18, {"from": borrower})
        assert mkr_dai_pool.lup() == 4_000 * 1e18

        # lender removes 1000 DAI
        tx = mkr_dai_pool.removeQuoteToken(1_000 * 1e18, 4000 * 1e18, {"from": lender})
        assert dai.balanceOf(mkr_dai_pool) == 2_800 * 1e18
        assert dai.balanceOf(lender) == 194_200 * 1e18
        assert mkr_dai_pool.totalQuoteToken() == 2_800 * 1e18

        # check lup moved down to 3000
        assert mkr_dai_pool.lup() == 3_000 * 1e18
        # check 4000 bucket balance
        (
            _,
            _,
            _,
            bucket_deposit,
            bucket_debt,
            _,
            lpOutstanding,
            _,
        ) = mkr_dai_pool.bucketAt(4000 * 1e18)
        # tested without delay in forge
        assert 2_400 * 1e18 <= bucket_debt <= 2_401 * 1e18
        assert bucket_deposit == 0
        assert 2_400 * 1e18 <= lpOutstanding <= 2_401 * 1e18
        assert 2_400 * 1e18 <= mkr_dai_pool.lpBalance(lender, 4000 * 1e18) <= 2_401 * 1e18

        # check 3000 bucket balance
        (
            _,
            _,
            _,
            bucket_deposit,
            bucket_debt,
            _,
            lpOutstanding,
            _,
        ) = mkr_dai_pool.bucketAt(3000 * 1e18)
        # debt should be 600 DAI + accumulated interest
        # TODO: properly check in forge tests
        assert Decimal(600) <= bucket_debt * 1e-18 <= Decimal(601)
        assert bucket_deposit == 2_800 * 1e18
        assert lpOutstanding == 3_400 * 1e18
        assert mkr_dai_pool.lpBalance(lender, 3000 * 1e18) == 3_400 * 1e18

        # check tx events
        transfer_event = tx.events["Transfer"][0][0]
        assert transfer_event["src"] == mkr_dai_pool
        assert transfer_event["dst"] == lender
        assert transfer_event["wad"] == 1_000 * 1e18
        pool_event = tx.events["RemoveQuoteToken"][0][0]
        assert pool_event["amount"] == 1_000 * 1e18
        assert pool_event["lender"] == lender
        assert pool_event["price"] == 4_000 * 1e18
        assert pool_event["lup"] == 3_000 * 1e18

        with capsys.disabled():
            print("\n==================================")
            print("Gas estimations:")
            print("==================================")
            print(
                f"Remove quote token from lup (reallocate to one bucket)           - {test_utils.get_usage(tx.gas_used)}"
            )


def test_quote_removal_below_lup(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    capsys,
    test_utils,
):

    with test_utils.GasWatcher(
        ["removeQuoteToken", "addCollateral", "addQuoteToken", "borrow"]
    ):
        lender = lenders[0]
        borrower = borrowers[0]

        assert dai.balanceOf(lender) == 200_000 * 1e18
        # deposit 3400 DAI at price of 1 MKR = 4000 DAI and 1 MKR = 3000
        mkr_dai_pool.addQuoteToken(5_000 * 1e18, 4000 * 1e18, {"from": lender})
        mkr_dai_pool.addQuoteToken(5_000 * 1e18, 3000 * 1e18, {"from": lender})
        mkr_dai_pool.addQuoteToken(5_000 * 1e18, 2000 * 1e18, {"from": lender})

        # borrower takes a loan of 3000 DAI
        mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
        mkr_dai_pool.borrow(3_000 * 1e18, 4000 * 1e18, {"from": borrower})
        assert mkr_dai_pool.lup() == 4_000 * 1e18

        # lender removes 1000 DAI
        tx = mkr_dai_pool.removeQuoteToken(1_000 * 1e18, 3000 * 1e18, {"from": lender})
        assert dai.balanceOf(mkr_dai_pool) == 11_000 * 1e18
        assert mkr_dai_pool.totalQuoteToken() == 11_000 * 1e18

        # check lup same 4000
        assert mkr_dai_pool.lup() == 4_000 * 1e18

        # check tx events
        transfer_event = tx.events["Transfer"][0][0]
        assert transfer_event["src"] == mkr_dai_pool
        assert transfer_event["dst"] == lender
        assert transfer_event["wad"] == 1_000 * 1e18
        pool_event = tx.events["RemoveQuoteToken"][0][0]
        assert pool_event["amount"] == 1_000 * 1e18
        assert pool_event["lender"] == lender
        assert pool_event["price"] == 3_000 * 1e18
        assert pool_event["lup"] == 4_000 * 1e18
        # check 4000 bucket balance
        (
            _,
            _,
            _,
            bucket_deposit,
            bucket_debt,
            _,
            lpOutstanding,
            _,
        ) = mkr_dai_pool.bucketAt(4000 * 1e18)
        assert bucket_debt == 3_000 * 1e18
        assert bucket_deposit == 2_000 * 1e18
        assert mkr_dai_pool.lpBalance(lender, 4000 * 1e18) == 5_000 * 1e18

        # check 3000 bucket balance
        (
            _,
            _,
            _,
            bucket_deposit,
            bucket_debt,
            _,
            lpOutstanding,
            _,
        ) = mkr_dai_pool.bucketAt(3000 * 1e18)
        assert bucket_debt == 0
        assert bucket_deposit == 4_000 * 1e18
        assert lpOutstanding == 4_000 * 1e18
        assert mkr_dai_pool.lpBalance(lender, 3000 * 1e18) == 4_000 * 1e18

        with capsys.disabled():
            print("\n==================================")
            print("Gas estimations:")
            print("==================================")
            print(
                f"Remove quote token below lup            - {test_utils.get_usage(tx.gas_used)}"
            )


def test_quote_removal_undercollateralized_pool(
    lenders,
    borrowers,
    mkr_dai_pool,
):

    lender = lenders[0]
    borrower = borrowers[0]

    # deposit 5000 DAI at price of 1 MKR = 4000 DAI and 1 MKR = 3000
    mkr_dai_pool.addQuoteToken(5_000 * 1e18, 1000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(5_000 * 1e18, 100 * 1e18, {"from": lender})

    # borrower takes a loan of 3000 DAI
    mkr_dai_pool.addCollateral(5.1 * 1e18, {"from": borrower})
    mkr_dai_pool.borrow(4_000 * 1e18, 1000 * 1e18, {"from": borrower})
    assert mkr_dai_pool.lup() == 1_000 * 1e18

    # lender tries to remove 2000 DAI - this will bring lup to 100 and leave pool undercollateralized
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.removeQuoteToken(2_000 * 1e18, 1000 * 1e18, {"from": lender})
    assert exc.value.revert_msg == "ajna/pool-undercollateralized"
