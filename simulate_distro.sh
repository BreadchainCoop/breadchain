#!/bin/bash
#
# Simulate a yield distribution on a local Anvil fork.
#
# Usage:
#   ./simulate_distro.sh [--contract ADDRESS] [--votes JSON] [--upgrade]
#   --contract  YieldDistributor contract address (default: mainnet deployment)
#   --votes     Vote distribution as JSON array (default: [1,1,1,1,1,1,1])
#   --upgrade   Upgrade the contract before running distribution
#
# Prerequisites: Anvil must be running with a fork of the target chain.
#


# Default values
DEFAULT_CONTRACT="0xeE95A62b749d8a2520E0128D9b3aCa241269024b"
DEFAULT_VOTES="[1,1,1,1,1,1,1]"
CONTRACT="$DEFAULT_CONTRACT"
VOTES="$DEFAULT_VOTES"
UPGRADE=false

# Parse flags
while [[ $# -gt 0 ]]; do
    case $1 in
        --contract)
            CONTRACT="$2"
            shift 2
            ;;
        --votes)
            VOTES="$2"
            shift 2
            ;;
        --upgrade)
            UPGRADE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

[[ "$CONTRACT" == "$DEFAULT_CONTRACT" ]] && echo "Using default value of CONTRACT=$CONTRACT"
[[ "$VOTES" == "$DEFAULT_VOTES" ]] && echo "Using default value of VOTES=$VOTES"

# Get the owner of the contract
OWNER="0x$(cast call $CONTRACT "owner()" | tr -d '\n' | tail -c 40)"

if [[ "$UPGRADE" == "true" ]]; then
    # Upgrade the contract to the current version
    echo "Deploying new YieldDistributor implementation..."
    forge build --quiet
    BYTECODE=$(forge inspect src/YieldDistributor.sol:YieldDistributor bytecode)
    cast rpc anvil_impersonateAccount $OWNER
    NEW_IMPL=$(cast send --from $OWNER --unlocked --create "$BYTECODE" --json | jq -r '.contractAddress')
    echo "New implementation deployed at: $NEW_IMPL"

    # Read the ProxyAdmin address from the ERC-1967 admin slot
    ADMIN_SLOT="0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
    PROXY_ADMIN=$(cast storage $CONTRACT $ADMIN_SLOT)
    PROXY_ADMIN=$(cast to-check-sum-address "0x${PROXY_ADMIN:26}")
    echo "ProxyAdmin address: $PROXY_ADMIN"

    # Upgrade the proxy to the new implementation
    cast send $PROXY_ADMIN "upgradeAndCall(address,address,bytes)" $CONTRACT $NEW_IMPL "0x" --from $OWNER --unlocked
    echo "Contract upgraded successfully"
else
    echo "Skipping upgrade (use --upgrade to upgrade)"
    cast rpc anvil_impersonateAccount $OWNER
fi

# Initialize voting cycle
cast send $CONTRACT "initializeVotingCycle(uint256)" 1 --from $OWNER --unlocked
echo "Voting cycle initialized"

ADDRESSES=(
    "0x918dEf5d593F46735f74F9E2B280Fe51AF3A99ad"
    "0x458cD345B4C05e8DF39d0A07220feb4Ec19F5e6f"
    "0xc2fB4B3EA53E10c88D193E709A81C4dc7aEC902e"
    "0xc053d2877C03e7FB96D6D29cE2d557c886f700A6"
    "0x4E443cDaff5c09a467eC5eE7e8b230bA463cBBBb"
    "0x3C41f941098681bfDb14ed423709CC7C29c1e5e6"
    "0xd083764c39Eddb70A749e0c1F808C14706b0CF44"
    "0xC304Eef1023e0b6e644f8ED8f8c629fD0973c52d"
    "0x8b5e3dD9A19bFF07C50C0019B21F69F7C3De555e"
    "0x9134fc7112b478e97eE6F0E6A7bf81EcAfef19ED"
    "0x2C5b3B2156EF139972FD39c4C5491140Ba0Ea3eE"
    "0x255f2b02cDed81FEe754CbaDFcAb8F9500EB436e"
    "0xbdf5Ce782871cbd4708eDBDe2dC18893d3C29E46"
    "0x22300aaDF0CCe33a4b993e5d2A1bb24409BAb8e1"
    "0xDfB0b22940Cc45283D639D22ba26aa55ab8Bfee8"
    "0xc57c5aE582708e619Ec1BA7513480b2e7540935f"
    "0xFa1093e2bacCa0b148284be2F650B5E00F83B72f"
    "0xD1edDfcc4596CC8bD0bd7495beaB9B979fc50336"
    "0x6C12E114E00C6f5AEb50dAAA384FBED9b48ACcbA"
    "0xB0De8cB8Dcc8c5382c4b7F3E978b491140B2bC55"
    "0x58f19e55058057B04feAe2EEA88F90B84b7714Eb"
    "0x94c9E2EF77f437955062FBc9911bebD20761eBBb"
    "0x6E2737d7B7247A35Ed6851a685a154FBA19E41Da"
    "0x7A1490Ff0241767171Fe023bAaf8D74525f2e866"
    "0xcca9a24c13B3C84E84643cb2cFA6b2402ff870E8"
    "0xdf0F44EFb2A2bF48A2B85FC3D9Bf663aDe8E1D1d"
    "0x5EAf9025b1e3459Eba17Ce8A4959158Ac1CDCbdb"
    "0x918F6d1446a7860eA147F413f59DF1C69839f9C1"
    "0x44D2b6Ef923b45064E73b4A1569547D84C6cb38a"
    "0x181404aD760f0167A24F939923dE52F0efCc0600"
    "0x1C9F765C579F94f6502aCd9fc356171d85a1F8D0"
    "0x2F4BcD8AdBE961290f2c4df752852466e7D655c9"
    "0x303f0310e394D9a297c3768f18D4ee3C0a5d4b6F"
    "0x3765fC1Dd77DE1Edfaf03b4941D95983dF2A5336"
    "0x37F1fE0C626Ab737db7B816bBA4Be91C838f88c2"
    "0x5cb6E6C521E1262E24A4004F012Ae6529E61E30F"
    "0x1AD43538F303a03d4CF0Be10bd408a23E8bdF73F"
    "0x453ADC452C975Ea77dc7289b3a124f2e261f359b"
    "0xB8e8d50752d3314a70e622795DA91d7e4287bA66"
    "0x8cc405143fb6C4ea908DFBA720702cE099874146"
    "0x1ECF3f51A771983C150b3cB4A2162E89c0A046Fc"
    "0x094CE8Ea2bD06C5BCf955592fc86842929935926"
)

# Cast votes from all addresses
echo "Casting votes for ${#ADDRESSES[@]} addresses"
for addr in "${ADDRESSES[@]}"; do
    cast rpc anvil_impersonateAccount "$addr"
    cast send "$CONTRACT" "castVote(uint256[])" "$VOTES" --from "$addr" --unlocked
done

# Get the starting block from the previous cycle
CYCLE_START_BLOCK=$(cast call $CONTRACT "lastClaimedBlockNumber()")

# Get current block
CURRENT_BLOCK=$(cast block-number)

# Switch to owner account
cast rpc anvil_impersonateAccount $OWNER

# Calculate the difference between CURRENT_BLOCK and CYCLE_START_BLOCK
# CYCLE_START_BLOCK is returned as hex, convert to decimal
CYCLE_START_DECIMAL=$(cast to-dec $CYCLE_START_BLOCK)
ENOUGH_BLOCKS=$((CURRENT_BLOCK - CYCLE_START_DECIMAL))
cast send $CONTRACT "setCycleLength(uint256)" $ENOUGH_BLOCKS --from $OWNER --unlocked

# Run Gas Killer Distribution
cast send $CONTRACT "distributeYieldGK()" --from $OWNER --unlocked