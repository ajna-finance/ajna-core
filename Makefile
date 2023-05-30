# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env && source ./tests/forge/invariants/scenarios/scenario-${SCENARIO}.sh

all: clean install build

# Clean the repo
clean   :; forge clean

# Install the Modules
install :; git submodule update --init --recursive

# Builds
build   :; forge clean && forge build

# Unit Tests
test                            :; forge test --no-match-test "testLoad|invariant|test_regression" --nmc "RegressionTest|Panic"  # --ffi # enable if you need the `ffi` cheat code on HEVM
test-with-gas-report            :; forge test --no-match-test "testLoad|invariant|test_regression" --nmc "RegressionTest|Panic" --gas-report # --ffi # enable if you need the `ffi` cheat code on HEVM

# Gas Load Tests
test-load                       :; forge test --match-test testLoad --gas-report

# Invariant Tests
test-invariant-all              :; forge t --mt invariant --nmc "RegressionTest|Panic"
test-invariant-erc20            :; forge t --mt invariant --nmc "RegressionTest|Panic" --mc ERC20
test-invariant-erc721           :; forge t --mt invariant --nmc "RegressionTest|Panic" --mc ERC721
test-invariant                  :; forge t --mt ${MT} --nmc RegressionTest
test-invariant-erc20-precision  :; ./tests/forge/invariants/test-invariant-erc20-precision.sh
test-invariant-erc721-precision :; ./tests/forge/invariants/test-invariant-erc721-precision.sh
test-invariant-erc20-buckets    :; ./tests/forge/invariants/test-invariant-erc20-buckets.sh
test-invariant-erc721-buckets   :; ./tests/forge/invariants/test-invariant-erc721-buckets.sh

# Real-world simulation scenarios
test-rw-simulation-erc20        :; FOUNDRY_INVARIANT_SHRINK_SEQUENCE=false RUST_LOG=forge=info,foundry_evm=info,ethers=info forge t --mt invariant_all_erc20 --mc RealWorldScenario
test-rw-simulation-erc721       :; FOUNDRY_INVARIANT_SHRINK_SEQUENCE=false RUST_LOG=forge=info,foundry_evm=info,ethers=info forge t --mt invariant_all_erc721 --mc RealWorldScenario

# Liquidations load test scenarios
test-liquidations-load-erc20     :; FOUNDRY_INVARIANT_SHRINK_SEQUENCE=false RUST_LOG=forge=info,foundry_evm=info,ethers=info forge t --mt invariant_all_erc20 --mc PanicExitERC20
test-liquidations-load-erc721    :; FOUNDRY_INVARIANT_SHRINK_SEQUENCE=false RUST_LOG=forge=info,foundry_evm=info,ethers=info forge t --mt invariant_all_erc721 --mc PanicExitERC721

# Swap tokens load test scenarios
test-swap-load-erc20             :; FOUNDRY_INVARIANT_SHRINK_SEQUENCE=false RUST_LOG=forge=info,foundry_evm=info,ethers=info forge t --mt invariant_all_erc20 --mc TradingERC20

# Regression Tests
test-regression-all             : test-regression-erc20 test-regression-erc721 test-regression-prototech
test-regression-erc20           :; forge t --mt test_regression --mc ERC20 --nmc "RealWorldRegression|Prototech"
test-regression-erc721          :; forge t --mt test_regression --mc ERC721 --nmc "RealWorldRegression|Prototech"
test-regression-prototech       :; forge t --mt test_regression --mc Prototech
test-regression-rw              :; forge t --mt test_regression --mc RealWorldRegression
test-regression                 :; forge t --mt ${MT}

# Coverage
coverage                        :; forge coverage --no-match-test "testLoad|invariant"

# Generate Gas Snapshots
snapshot :; forge clean && forge snapshot

analyze:
		slither src/. ; slither src/libraries/external/.


# Deployment
deploy-contracts:
	forge script script/deploy.s.sol \
		--rpc-url ${ETH_RPC_URL} --sender ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY} --broadcast -vvv --verify
