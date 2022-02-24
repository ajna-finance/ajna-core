import brownie
from brownie import Contract
import pytest
import math


def indexToPricePy(index: int) -> int:
    # x^y = 2^(y*log_2(x))
    return 2 ** (index * math.log2(1.005))

def priceToIndexPy(price: int) -> int:
    return math.log2(price) / math.log2(1.005)

def test_index_to_price(bucket_math):

    index_to_price_test_cases = [
        1,
        10,
        50,
        350
        3000,
        6926
    ]

    for i in index_to_price_test_cases:
        price = bucket_math.indexToPrice(i)

        print(price, indexToPricePy(i))
        assert price == indexToPricePy(i)


def test_price_to_index(bucket_math):
    price = 100

    index = bucket_math.priceToIndex(price)