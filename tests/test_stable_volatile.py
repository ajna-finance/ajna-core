import brownie
import pytest
from decimal import *


def test_stable_volatile_one(weth_dai_pool, dai, weth):
    assert weth_dai_pool.collateral() == weth
    assert weth_dai_pool.quoteToken() == dai
