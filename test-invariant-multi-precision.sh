for quote_precision in 6 8 18
do
    for collateral_precision in 6 8 18
    do
        make test-invariant QUOTE_PRECISION=${quote_precision} COLLATERAL_PRECISION=${collateral_precision}
    done
done