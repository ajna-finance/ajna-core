from brownie import *


def main():
    deployer = accounts[0]
    # quote is DAI
    quote_token = Contract("0x6b175474e89094c44da98b954eedeac495271d0f")
    # collateral is COMP
    collateral = Contract("0xc00e94Cb662C3520282E6f5717214004A7f26888")
    Maths.deploy({"from": deployer})
    Buckets.deploy({"from": deployer})
    pool = ERC20Pool.deploy(
        collateral,
        quote_token,
        {"from": deployer},
    )

    lenders = get_lenders(quote_token, pool, accounts)
    borrowers = get_borrowers(collateral, pool, accounts)

    pool.addQuoteToken(20_000 * 1e18, 11.694 * 1e18, {"from": lenders[0]})
    pool.addQuoteToken(50_000 * 1e18, 12.278 * 1e18, {"from": lenders[0]})
    pool.addQuoteToken(100_000 * 1e18, 12.892 * 1e18, {"from": lenders[0]})
    pool.addQuoteToken(50_000 * 1e18, 13.537 * 1e18, {"from": lenders[0]})
    pool.addQuoteToken(60_000 * 1e18, 14.214 * 1e18, {"from": lenders[0]})

    pool.addQuoteToken(10_000 * 1e18, 11.137 * 1e18, {"from": lenders[1]})
    pool.addQuoteToken(10_000 * 1e18, 11.694 * 1e18, {"from": lenders[1]})
    pool.addQuoteToken(70_000 * 1e18, 12.278 * 1e18, {"from": lenders[1]})
    pool.addQuoteToken(60_000 * 1e18, 12.892 * 1e18, {"from": lenders[1]})
    pool.addQuoteToken(60_000 * 1e18, 13.537 * 1e18, {"from": lenders[1]})
    pool.addQuoteToken(50_000 * 1e18, 14.214 * 1e18, {"from": lenders[1]})
    pool.addQuoteToken(10_000 * 1e18, 14.924 * 1e18, {"from": lenders[1]})

    pool.addQuoteToken(40_000 * 1e18, 11.694 * 1e18, {"from": lenders[2]})
    pool.addQuoteToken(60_000 * 1e18, 12.278 * 1e18, {"from": lenders[2]})
    pool.addQuoteToken(90_000 * 1e18, 12.892 * 1e18, {"from": lenders[2]})
    pool.addQuoteToken(30_000 * 1e18, 13.537 * 1e18, {"from": lenders[2]})
    pool.addQuoteToken(10_000 * 1e18, 14.214 * 1e18, {"from": lenders[2]})
    pool.addQuoteToken(10_000 * 1e18, 14.924 * 1e18, {"from": lenders[2]})

    pool.addQuoteToken(10_000 * 1e18, 11.137 * 1e18, {"from": lenders[3]})
    pool.addQuoteToken(30_000 * 1e18, 11.694 * 1e18, {"from": lenders[3]})
    pool.addQuoteToken(70_000 * 1e18, 12.278 * 1e18, {"from": lenders[3]})
    pool.addQuoteToken(50_000 * 1e18, 12.892 * 1e18, {"from": lenders[3]})
    pool.addQuoteToken(40_000 * 1e18, 13.537 * 1e18, {"from": lenders[3]})
    pool.addQuoteToken(10_000 * 1e18, 14.214 * 1e18, {"from": lenders[3]})

    # pool.addQuoteToken(100000 * 1e18, 2000 * 1e18, {"from": lender})
    # pool.addQuoteToken(100000 * 1e18, 1500 * 1e18, {"from": lender})
    # pool.addQuoteToken(100000 * 1e18, 1000 * 1e18, {"from": lender})
    # pool.addCollateral(100 * 1e18, {"from": borrower1})
    # pool.addCollateral(200 * 1e18, {"from": borrower2})
    # pool.addCollateral(300 * 1e18, {"from": borrower3})
    # pool.addCollateral(400 * 1e18, {"from": borrower4})
    # pool.addCollateral(500 * 1e18, {"from": borrower5})
    # pool.borrow(10_000 * 1e18, 4000 * 1e18, {"from": borrower1})
    # pool.borrow(10_000 * 1e18, 4000 * 1e18, {"from": borrower2})
    return (
        lenders,
        borrowers,
        quote_token,
        collateral,
        pool,
    )


def get_lenders(quote_token, pool, accounts):
    amount = 500_000 * 10**18  # 500000 quote tokens for each lender
    quote_reserve = accounts.at(
        "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643", force=True
    )
    lenders = []
    for index in range(5):
        lender = accounts.add()
        quote_token.transfer(lender, amount, {"from": quote_reserve})
        quote_token.approve(
            pool,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            {"from": lender},
        )
        lenders.append(lender)
    return lenders


def get_borrowers(collateral, pool, accounts):
    amount = 20_000 * 10**18  # 20000 collateral for each borrower
    # reserve is COMP Reservoir
    reserve = accounts.at("0x2775b1c75658be0f640272ccb8c72ac986009e38", force=True)
    borrowers = []
    for index in range(10):
        borrower = accounts.add()
        collateral.transfer(borrower, amount, {"from": reserve})
        collateral.approve(
            pool,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            {"from": borrower},
        )
        borrowers.append(borrower)
    return borrowers
