for bucket_index in 500 1500 2500 3500 4500 5500 6500
do
    make test-invariant-erc20 QUOTE_PRECISION=18 COLLATERAL_PRECISION=18 BUCKET_INDEX_ERC20=${bucket_index}
done