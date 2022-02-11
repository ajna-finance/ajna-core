import pytest
from brownie import Contract, ERC20PerpPool


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
    daiPool = ERC20PerpPool.deploy(mkr, dai, {"from": deployer})
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


class TestUtils:
    @staticmethod
    def assert_lender_quote_deposit(lender, amount, price, dai, mkr_dai_pool):
        balance = dai.balanceOf(lender)
        assert balance > amount
        mkr_dai_pool.depositQuoteToken(amount, price, {"from": lender})
        assert balance - dai.balanceOf(lender) == amount
        assert mkr_dai_pool.quoteBalances(lender) == amount

    @staticmethod
    def assert_borrower_collateral_deposit(borrower, amount, mkr, mkr_dai_pool):
        balance = mkr.balanceOf(borrower)
        assert balance > amount
        mkr_dai_pool.depositCollateral(amount, {"from": borrower})
        assert balance - mkr.balanceOf(borrower) == amount
        assert mkr_dai_pool.collateralBalances(borrower) == amount

    @staticmethod
    def assert_borrow(borrower, amount, dai, mkr_dai_pool):
        mkr_dai_pool.borrow(amount, {"from": borrower})
        assert dai.balanceOf(borrower) == amount

    @staticmethod
    def assert_bucket(bucket, deposit, debt, debitors, mkr_dai_pool):
        onDeposit, totalDebitors, bucketDebt, _ = mkr_dai_pool.bucketInfo(bucket)
        assert onDeposit == deposit
        assert totalDebitors == debitors
        assert bucketDebt == debt

    @staticmethod
    def assert_borrower_debt(borrower, bucket, expected, mkr_dai_pool):
        assert mkr_dai_pool.userDebt(borrower, bucket) == expected


@pytest.fixture
def test_utils():
    return TestUtils
