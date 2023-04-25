#!/bin/bash
set -e
for quote_precision in 6 8 18
do
    make test-invariant-erc721 QUOTE_PRECISION=${quote_precision}
done