# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

all: clean install update build

# Clean the repo
clean  :; forge clean

# Install the Modules
install :; git submodule update --init --recursive

# Update Dependencies
update:; forge update

# Builds
build  :; forge clean && forge build --optimize --optimize-runs 1000000

# Tests
test   :; forge clean && forge build && forge test --optimize --optimize-runs 1000000 -v # --ffi # enable if you need the `ffi` cheat code on HEVM
test-with-gas-report   :; forge clean && forge test --optimize --optimize-runs 1000000 -v --gas-report # --ffi # enable if you need the `ffi` cheat code on HEVM

# Lints
lint :; prettier --write src/**/*.sol && prettier --write src/*.sol

# Generate Gas Snapshots
snapshot :; forge clean && forge snapshot --optimize --optimize-runs 1000000 