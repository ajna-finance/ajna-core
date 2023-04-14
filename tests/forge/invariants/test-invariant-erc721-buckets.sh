for bucket_index in 6500
do
    make test-invariant-erc721 QUOTE_PRECISION=18 BUCKET_INDEX=${bucket_index}
done