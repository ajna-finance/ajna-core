for bucket_index in 1 500 1500 2500 3500 4500 5500 6500 7369
do
    make test-invariant-erc721 QUOTE_PRECISION=18 BUCKET_INDEX_ERC721=${bucket_index}
done