# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

all: clean install build

# Clean the repo
clean   :; forge clean

# Install the Modules
install :; git submodule update --init --recursive

# Builds
build   :; forge clean && forge build

# Tests
test                 :; forge clean && forge test -v --no-match-test testLoad # --ffi # enable if you need the `ffi` cheat code on HEVM
test-with-gas-report :; forge clean && forge build && forge test -v --no-match-test testLoad --gas-report # --ffi # enable if you need the `ffi` cheat code on HEVM
test-load            :; forge clean && forge build && forge test -vv --match-test testLoad --gas-report
# TODO: should be able to fork from block 15478978, a block after Ajna token contract was created
test-with-cache      :; forge clean && forge test -vv --no-match-test testLoad --fork-url $(ETH_RPC_URL) --fork-block-number 15576176
coverage             :; forge coverage --no-match-test testLoad

# Generate Gas Snapshots
snapshot :; forge clean && forge snapshot

analyze:
		slither src/base/. ; slither src/libraries/. ; slither src/erc20/. ; slither src/erc721/.
