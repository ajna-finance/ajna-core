#!/bin/bash
set -e
for bucket_index in 1 500 1500 2500 3500 4500 5500 6500 7369
do
    export BUCKET_INDEX_ERC721=${bucket_index}
    echo "Running test with Starting bucketIndex ${bucket_index}"
    forge t --mt invariant --nmc RegressionTest --mc ERC721
done