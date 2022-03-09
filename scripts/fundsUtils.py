from brownie import *


def provide_borrower_tokens(borrower):

    mkr_reserve = accounts.at("0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB", force=True)
    mkr = Contract("0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2")
    # fund 500 MKR
    mkr.transfer(borrower, 500 * 1e18, {"from": mkr_reserve})
    # fund 100 ETH
    accounts[0].transfer(borrower, 100 * 1e18)


def provide_lender_tokens(lender):

    dai_reserve = accounts.at("0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643", force=True)
    dai = Contract("0x6b175474e89094c44da98b954eedeac495271d0f")
    # fund 100000 DAI
    dai.transfer(lender, 100_000 * 1e18, {"from": dai_reserve})
    # fund 100 ETH
    accounts[0].transfer(lender, 100 * 1e18)
