#!/bin/bash
set -e
for quote_precision in 6 8 18
do
    export QUOTE_PRECISION=${quote_precision}
    echo "Running test with ${QUOTE_PRECISION} quote precision"
    forge t --mt invariant --nmc RegressionTest --mc ERC721PoolPosition
done