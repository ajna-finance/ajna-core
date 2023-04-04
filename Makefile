# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# Default token precisions for invariant testing
QUOTE_PRECISION = 18
COLLATERAL_PRECISION = 18

all: clean install build

# Clean the repo
clean   :; forge clean

# Install the Modules
install :; git submodule update --init --recursive

# Builds
build   :; forge clean && forge build

# Tests
test                           :; forge test --no-match-test "testLoad|invariant|test_regression"  # --ffi # enable if you need the `ffi` cheat code on HEVM
test-with-gas-report           :; FOUNDRY_PROFILE=optimized forge test --no-match-test "testLoad|invariant|test_regression" --gas-report # --ffi # enable if you need the `ffi` cheat code on HEVM
test-load                      :; FOUNDRY_PROFILE=optimized forge test --match-test testLoad --gas-report
test-invariant				   :; eval QUOTE_PRECISION=${QUOTE_PRECISION} COLLATERAL_PRECISION=${COLLATERAL_PRECISION} forge t --mt invariant --nmc RegressionTest
test-invariant-erc20           :; eval QUOTE_PRECISION=${QUOTE_PRECISION} COLLATERAL_PRECISION=${COLLATERAL_PRECISION} forge t --mt invariant --nmc RegressionTest --mc ERC20
test-invariant-erc721          :; eval QUOTE_PRECISION=${QUOTE_PRECISION} forge t --mt invariant --nmc RegressionTest --mc ERC721
test-regression                :; eval QUOTE_PRECISION=${QUOTE_PRECISION} COLLATERAL_PRECISION=${COLLATERAL_PRECISION} forge t --mt test_regression
test-regression-erc20          :; eval QUOTE_PRECISION=${QUOTE_PRECISION} COLLATERAL_PRECISION=${COLLATERAL_PRECISION} forge t --mt test_regression --mc ERC20
test-regression-erc721         :; eval QUOTE_PRECISION=${QUOTE_PRECISION} forge t --mt test_regression --mc ERC721
coverage                       :; forge coverage --no-match-test "testLoad|invariant"
test-invariant-erc20-precision :; ./test-invariant-erc20-precision.sh

# Generate Gas Snapshots
snapshot :; forge clean && forge snapshot

analyze:
		slither src/. ; slither src/libraries/external/.


# Deployment
deploy-contracts:
	forge script ./deploy.sol \
		--rpc-url ${ETH_RPC_URL} --sender ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY} --broadcast -vvv
