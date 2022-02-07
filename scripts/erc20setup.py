from brownie import *
import itertools

def main():
    deployer = accounts[0];
    alice = accounts[1];
    bob = accounts[2];
    uniswapDai = Contract("0x2a1530C4C41db0B0b2bB646CB5Eb1A67b7158667");
    uniswapDai.ethToTokenSwapInput(1, 9999999999, {"from": alice, "value": "50 ether"});
    uniswapMkr = Contract("0x2C4Bd064b998838076fa341A83d007FC2FA50957");
    uniswapMkr.ethToTokenSwapInput(1, 9999999999, {"from": bob, "value": "50 ether"});
    dai = Contract('0x6b175474e89094c44da98b954eedeac495271d0f');
    mkr = Contract('0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2')
    daiPool = ERC20PerpPool.deploy(mkr, dai, {"from" : deployer});
    dai.approve(daiPool, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, {"from" : alice});
    dai.approve(daiPool, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, {"from" : bob});
    mkr.approve(daiPool, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, {"from" : alice});
    mkr.approve(daiPool, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, {"from" : bob});

    # Alice deposits 10000 DAI at price of 2866.666666666666666662 DAI / MKR - bucket 7
    daiPool.depositQuoteToken(10000000000000000000000, 2866666666666666666662, {"from": alice})
    # Bob deposits 10 MKR as collateral
    daiPool.depositCollateral(10000000000000000000, {"from": bob})
    # Bob borrows 5000 DAI
    daiPool.borrow(5000000000000000000000, {"from": bob})

    return deployer, alice, bob, dai, mkr, daiPool;