# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

all: clean install build

# Clean the repo
clean  :; forge clean

# Install the Modules
install :; git submodule update --init --recursive

# Builds
build  :; forge clean && forge build --optimize --optimizer-runs 1000000

# Tests
test   :; forge clean && forge test --optimize --optimizer-runs 1000000 -v # --ffi # enable if you need the `ffi` cheat code on HEVM
test-with-gas-report   :; forge clean && forge build && forge test --optimize --optimizer-runs 1000000 -v --gas-report # --ffi # enable if you need the `ffi` cheat code on HEVM
coverage   :; forge coverage

# Generate Gas Snapshots
snapshot :; forge clean && forge snapshot --optimize --optimize-runs 1000000 

analyze:
		slither src/base/. ; slither src/libraries/. ; slither src/erc20/. ; slither src/erc721/.
