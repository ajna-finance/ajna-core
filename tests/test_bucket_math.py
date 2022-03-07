import brownie
from brownie import Contract
import pytest
import math


PRB_SCALE = 10 ** 18

def indexToPricePy(index: int) -> int:
    # x^y = 2^(y*log_2(x))
    return 2 ** (index * math.log2(1.005))

def priceToIndexPy(price: int) -> int:
    index = math.log2(price) / math.log2(1.005)
    return math.floor(index)

def get_first_12_digits(number: int) -> int:
    return int(str(number)[:12])

def find_precision(number_1: int, number_2: int) -> int:
    # find the matching precision of two numbers
    assert isinstance(number_1, int)
    assert isinstance(number_2, int)

    i = 1
    matches = True

    while matches:
        if int(str(number_1)[:i]) == int(str(number_2)[:i]):
            i += 1
        else:
            matches = False
    return i - 1

def test_index_to_price(bucket_math):

    index_to_price_test_cases = [
        -3232,
        -322,
        1,
        2,
        3,
        4,
        10,
        50,
        350,
        3000,
        6926
    ]

    for i in index_to_price_test_cases:
        price = bucket_math.indexToPrice(i)

        print(f"testing index: {i}", price, indexToPricePy(i))
        # python and solidity approaches match up to a precision of 12 digits
        assert get_first_12_digits(price) == get_first_12_digits(int(indexToPricePy(i) * PRB_SCALE))

def test_price_to_index(bucket_math):

    price_to_index_test_cases = [
        .0000001,
        .2,
        .5,
        1.5,
        2.89995955,
        5,
        5000,
        10000,
        450000
    ]

    for p in price_to_index_test_cases:

        index = bucket_math.priceToIndex(int(p * PRB_SCALE))
        index_py = priceToIndexPy(p)

        print(f"testing price: {p}", index, index_py)
        assert index == index_py

def test_round_trip(bucket_math):

    index = bucket_math.priceToIndex(5 * PRB_SCALE)

    assert index == 322

    price = bucket_math.indexToPrice(index)
    assert (int(math.ceil(price / PRB_SCALE)) == 5)
