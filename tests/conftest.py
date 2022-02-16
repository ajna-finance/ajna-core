import pytest
from brownie import Contract, ERC20Pool


@pytest.fixture
def deployer(accounts):
    yield accounts[0]


@pytest.fixture
def dai():
    token_address = "0x6b175474e89094c44da98b954eedeac495271d0f"
    yield Contract(token_address)


@pytest.fixture
def mkr():
    token_address = "0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2"
    yield Contract(token_address)


@pytest.fixture
def mkr_dai_pool(mkr, dai, deployer):
    daiPool = ERC20Pool.deploy(mkr, dai, {"from": deployer})
    yield daiPool


@pytest.fixture
def lenders(dai, mkr_dai_pool, accounts):
    amount = 200_000 * 10**18  # 100000 DAI for each lender
    reserve = accounts.at("0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643", force=True)
    lenders = []
    for index in range(10):
        lender = accounts.add()
        dai.transfer(lender, amount, {"from": reserve})
        dai.approve(
            mkr_dai_pool,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            {"from": lender},
        )
        lenders.append(lender)
    yield lenders


@pytest.fixture
def borrowers(mkr, mkr_dai_pool, accounts):
    amount = 100 * 10**18  # 100 MKR for each borrower
    reserve = accounts.at("0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB", force=True)
    borrowers = []
    for index in range(10):
        borrower = accounts.add()
        mkr.transfer(borrower, amount, {"from": reserve})
        mkr.approve(
            mkr_dai_pool,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            {"from": borrower},
        )
        borrowers.append(borrower)
    yield borrowers
