#!/bin/bash
set -e

echo "=== Setting up DeFi Protocol Engineering workspace ==="

# Install Foundry
echo "Installing Foundry..."
curl -L https://foundry.paradigm.xyz | bash
export PATH="$HOME/.foundry/bin:$PATH"
foundryup

# Verify installation
echo ""
echo "=== Foundry installed ==="
forge --version
cast --version
anvil --version

# Install workspace dependencies
echo ""
echo "Installing Forge dependencies..."
cd workspace
forge install

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Quick start:"
echo "  cd workspace"
echo "  forge build              # compile all contracts"
echo "  forge test               # run all tests"
echo "  forge test --match-path 'test/part1/**/*.sol'  # run Part 1 tests only"
echo ""
echo "Happy building!"
