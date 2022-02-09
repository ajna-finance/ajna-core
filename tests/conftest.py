import pytest
from brownie import Contract, ERC20PerpPool


@pytest.fixture
def deployer(accounts):
    yield accounts[0]


@pytest.fixture
def lender1(accounts):
    yield accounts[1]


@pytest.fixture
def lender2(accounts):
    yield accounts[2]


@pytest.fixture
def lender3(accounts):
    yield accounts[3]


@pytest.fixture
def lender4(accounts):
    yield accounts[4]


@pytest.fixture
def borrower1(accounts):
    yield accounts[5]


@pytest.fixture
def borrower2(accounts):
    yield accounts[6]


@pytest.fixture
def borrower3(accounts):
    yield accounts[7]


@pytest.fixture
def borrower4(accounts):
    yield accounts[8]


@pytest.fixture
def borrower5(accounts):
    yield accounts[9]


@pytest.fixture
def dai():
    token_address = "0x6b175474e89094c44da98b954eedeac495271d0f"
    yield Contract(token_address)


@pytest.fixture
def mkr():
    token_address = "0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2"
    yield Contract(token_address)


@pytest.fixture
def uniswap_dai():
    token_address = "0x2a1530C4C41db0B0b2bB646CB5Eb1A67b7158667"
    yield Contract(token_address)


@pytest.fixture
def uniswap_mkr():
    token_address = "0x2C4Bd064b998838076fa341A83d007FC2FA50957"
    yield Contract(token_address)


@pytest.fixture
def mkr_dai_pool(mkr, dai, deployer):
    daiPool = ERC20PerpPool.deploy(mkr, dai, {"from": deployer})
    yield daiPool


@pytest.fixture
def lenders(uniswap_dai, dai, mkr_dai_pool, lender1, lender2, lender3, lender4):
    lenders = [lender1, lender2, lender3, lender4]
    for lender in lenders:
        uniswap_dai.ethToTokenSwapInput(
            1, 9999999999, {"from": lender, "value": "90 ether"}
        )
        dai.approve(
            mkr_dai_pool,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            {"from": lender},
        )
    yield lenders


@pytest.fixture
def borrowers(
    uniswap_mkr,
    mkr,
    mkr_dai_pool,
    borrower1,
    borrower2,
    borrower3,
    borrower4,
    borrower5,
):
    borrowers = [borrower1, borrower2, borrower3, borrower4, borrower5]
    for borrower in borrowers:
        uniswap_mkr.ethToTokenSwapInput(
            1, 9999999999, {"from": borrower, "value": "50 ether"}
        )
        mkr.approve(
            mkr_dai_pool,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            {"from": borrower},
        )
    yield borrowers
