# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# Default token precisions for invariant testing
QUOTE_PRECISION = 18
COLLATERAL_PRECISION = 18

# Default buckets for invariant testing
BUCKET_INDEX_ERC20  = 2570
BUCKET_INDEX_ERC721 = 850
NO_OF_BUCKETS       = 3

all: clean install build

# Clean the repo
clean   :; forge clean

# Install the Modules
install :; git submodule update --init --recursive

# Builds
build   :; forge clean && forge build

# Tests
test                           :; forge test --no-match-test "testLoad|invariant|test_regression"  # --ffi # enable if you need the `ffi` cheat code on HEVM
test-with-gas-report           :; forge test --no-match-test "testLoad|invariant|test_regression" --gas-report # --ffi # enable if you need the `ffi` cheat code on HEVM
test-load                      :; forge test --match-test testLoad --gas-report
test-invariant                 :; eval QUOTE_PRECISION=${QUOTE_PRECISION} COLLATERAL_PRECISION=${COLLATERAL_PRECISION} BUCKET_INDEX_ERC20=${BUCKET_INDEX_ERC20} BUCKET_INDEX_ERC721=${BUCKET_INDEX_ERC721} NO_OF_BUCKETS=${NO_OF_BUCKETS} forge t --mt invariant --nmc RegressionTest
test-invariant-erc20           :; eval QUOTE_PRECISION=${QUOTE_PRECISION} COLLATERAL_PRECISION=${COLLATERAL_PRECISION} BUCKET_INDEX_ERC20=${BUCKET_INDEX_ERC20} NO_OF_BUCKETS=${NO_OF_BUCKETS} forge t --mt invariant --nmc RegressionTest --mc ERC20
test-invariant-erc721          :; eval QUOTE_PRECISION=${QUOTE_PRECISION} BUCKET_INDEX_ERC721=${BUCKET_INDEX_ERC721} NO_OF_BUCKETS=${NO_OF_BUCKETS} forge t --mt invariant --nmc RegressionTest --mc ERC721
test-regression                :; eval QUOTE_PRECISION=${QUOTE_PRECISION} COLLATERAL_PRECISION=${COLLATERAL_PRECISION} BUCKET_INDEX_ERC20=${BUCKET_INDEX_ERC20} BUCKET_INDEX_ERC721=${BUCKET_INDEX_ERC721} NO_OF_BUCKETS=${NO_OF_BUCKETS} forge t --mt test_regression
test-regression-erc20          :; eval QUOTE_PRECISION=${QUOTE_PRECISION} COLLATERAL_PRECISION=${COLLATERAL_PRECISION} BUCKET_INDEX_ERC20=${BUCKET_INDEX_ERC20} NO_OF_BUCKETS=${NO_OF_BUCKETS} forge t --mt test_regression --mc ERC20
test-regression-erc721         :; eval QUOTE_PRECISION=${QUOTE_PRECISION} BUCKET_INDEX_ERC721=${BUCKET_INDEX_ERC721} NO_OF_BUCKETS=${NO_OF_BUCKETS} forge t --mt test_regression --mc ERC721
coverage                       :; forge coverage --no-match-test "testLoad|invariant"
test-invariant-erc20-precision :; ./tests/forge/invariants/test-invariant-erc20-precision.sh
test-invariant-erc20-buckets   :; ./tests/forge/invariants/test-invariant-erc20-buckets.sh
test-invariant-erc721-buckets  :; ./tests/forge/invariants/test-invariant-erc721-buckets.sh

# Certora
certora-erc721-permit          :; $(if $(CERTORAKEY),, @echo "set certora key"; exit 1;) PATH=~/.solc-select/artifacts/solc-0.8.14:~/.solc-select/artifacts:${PATH} certoraRun --solc_map PermitERC721Harness=solc-0.8.14,Auxiliar=solc-0.8.14,SignerMock=solc-0.8.14 --optimize_map PermitERC721Harness=500,Auxiliar=0,SignerMock=0 --rule_sanity basic certora/harness/PermitERC721Harness.sol certora/Auxiliar.sol certora/SignerMock.sol --verify PermitERC721Harness:certora/PermitERC721.spec --multi_assert_check $(if $(short), --short_output,)

# Generate Gas Snapshots
snapshot :; forge clean && forge snapshot

analyze:
		slither src/. ; slither src/libraries/external/.


# Deployment
deploy-contracts:
	forge script script/deploy.s.sol \
		--rpc-url ${ETH_RPC_URL} --sender ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY} --broadcast -vvv --verify
