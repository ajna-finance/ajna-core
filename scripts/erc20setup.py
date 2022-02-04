from brownie import *
import itertools

def main():
    deployer = accounts[0];
    alice = accounts[1];
    bob = accounts[2];
    uniswap =Contract("0x2a1530C4C41db0B0b2bB646CB5Eb1A67b7158667");
    uniswap.ethToTokenSwapInput(1, 9999999999, {"from": alice, "value": "100 ether"});
    uniswap.ethToTokenSwapInput(1, 9999999999, {"from": bob, "value": "55 ether"});
    dai = Contract('0x6b175474e89094c44da98b954eedeac495271d0f');
    mkr = Contract('0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2')
    daiPool = ERC20PerpPool.deploy(dai, mkr, {"from" : deployer});
    dai.approve(daiPool, 111111111111, {"from" : alice});
    dai.approve(daiPool, 111111111111, {"from" : bob});
    return deployer, alice, bob, dai, mkr, daiPool;