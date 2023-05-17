#!/bin/bash
# configuration for inactive pool
export QUOTE_PRECISION=18
export COLLATERAL_PRECISION=18
export BUCKET_INDEX_ERC20=2570
export BUCKET_INDEX_ERC721=1000
export NO_OF_BUCKETS=3
export MIN_QUOTE_AMOUNT_ERC20=1000
# 1e30
export MAX_QUOTE_AMOUNT_ERC20=1000000000000000000000000000000
export MIN_COLLATERAL_AMOUNT_ERC20=1000
# 1e30
export MAX_COLLATERAL_AMOUNT_ERC20=1000000000000000000000000000000
export MIN_QUOTE_AMOUNT_ERC721=1000
# 1e30
export MAX_QUOTE_AMOUNT_ERC721=1000000000000000000000000000000
export MIN_COLLATERAL_AMOUNT_ERC721=1
export MAX_COLLATERAL_AMOUNT_ERC721=100
export FOUNDRY_INVARIANT_RUNS=10
export FOUNDRY_INVARIANT_DEPTH=200
# 24 hours
export SKIP_TIME=86400
# 200 days
export SKIP_TIME_TO_KICK=17280000
# 24 hours
export SKIP_TIME_TO_KICK_RESERVE=86400