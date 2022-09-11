# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

all: clean install build

# Clean the repo
clean  :; forge clean

# Install the Modules
install :; git submodule update --init --recursive

# Builds
build  :; forge clean && forge build

# Tests
test   :; forge clean && forge test -v --no-match-test testGasLoad # --ffi # enable if you need the `ffi` cheat code on HEVM
test-with-gas-report   :; forge clean && forge build && forge test -v --no-match-path testGasLoad --gas-report # --ffi # enable if you need the `ffi` cheat code on HEVM
test-gas-load   :; forge clean && forge build && forge test -vv --match-test testGasLoad --gas-report
coverage   :; forge coverage

# Generate Gas Snapshots
snapshot :; forge clean && forge snapshot

analyze:
		slither src/base/. ; slither src/libraries/. ; slither src/erc20/. ; slither src/erc721/.
