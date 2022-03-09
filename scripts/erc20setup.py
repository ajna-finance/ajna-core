from brownie import *


def main():
    deployer = accounts[0]
    lender = accounts[1]
    borrower1 = accounts[2]
    borrower2 = accounts[3]
    borrower3 = accounts[4]
    borrower4 = accounts[5]
    borrower5 = accounts[6]
    BucketMath.deploy({"from": deployer})
    dai = Contract("0x6b175474e89094c44da98b954eedeac495271d0f")
    mkr = Contract("0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2")
    Maths.deploy({"from": deployer})
    PriceBuckets.deploy({"from": deployer})
    contract = ERC20Pool.deploy(
        mkr,
        dai,
        {"from": deployer},
    )

    dai_reserve = accounts.at("0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643", force=True)
    dai.transfer(lender, 1_000_000 * 1e18, {"from": dai_reserve})
    dai.approve(
        contract,
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
        {"from": lender},
    )

    mkr_reserve = accounts.at("0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB", force=True)
    for i in range(2, 7):
        mkr.transfer(accounts[i], 500 * 1e18, {"from": mkr_reserve})
        mkr.approve(
            contract,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            {"from": accounts[i]},
        )
        dai.approve(
            contract,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            {"from": accounts[i]},
        )

    contract.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    contract.addQuoteToken(10_000 * 1e18, 2000 * 1e18, {"from": lender})
    contract.addQuoteToken(10_000 * 1e18, 1500 * 1e18, {"from": lender})
    contract.addQuoteToken(10_000 * 1e18, 1000 * 1e18, {"from": lender})
    contract.addCollateral(500 * 1e18, {"from": borrower1})
    contract.addCollateral(500 * 1e18, {"from": borrower2})
    contract.addCollateral(300 * 1e18, {"from": borrower3})
    contract.addCollateral(400 * 1e18, {"from": borrower4})
    contract.addCollateral(500 * 1e18, {"from": borrower5})
    contract.borrow(10_000 * 1e18, 4000 * 1e18, {"from": borrower1})
    contract.borrow(5_000 * 1e18, 2000 * 1e18, {"from": borrower2})
    return (
        lender,
        borrower1,
        borrower2,
        dai,
        mkr,
        contract,
    )
