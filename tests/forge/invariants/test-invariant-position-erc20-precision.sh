#!/bin/bash
set -e
for quote_precision in 6 8 18
do
    for collateral_precision in 6 8 18
    do
        export QUOTE_PRECISION=${quote_precision}
        export COLLATERAL_PRECISION=${collateral_precision}
        echo "Running test with ${QUOTE_PRECISION} quote precision and ${COLLATERAL_PRECISION} collateral precision"
        forge t --mt invariant --nmc RegressionTest --mc ERC20PoolPosition
    done
done