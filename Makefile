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
test                 :; forge test --no-match-test testLoad # --ffi # enable if you need the `ffi` cheat code on HEVM
test-with-gas-report :; FOUNDRY_PROFILE=optimized forge test --no-match-test testLoad --gas-report # --ffi # enable if you need the `ffi` cheat code on HEVM
test-load            :; FOUNDRY_PROFILE=optimized forge test --match-test testLoad --gas-report
coverage             :; forge coverage --no-match-test testLoad

# Generate Gas Snapshots
snapshot :; forge clean && forge snapshot

analyze:
		slither src/. ; slither src/libraries/external/.
