# Testnet Deployment Setup

This repository includes automated testnet deployment via GitHub Actions. The workflow automatically deploys all smart contracts to testnet when code is pushed to the `dev` or `staging` branches.

## Required GitHub Secrets

Before the deployment workflow can run successfully, you must configure the following secrets in your GitHub repository settings:

### 1. TESTNET_RPC_URL
- **Description**: The RPC endpoint URL for your target testnet
- **Example**: `https://rpc.gnosischain.com` (for Gnosis Chain testnet)
- **Format**: Full HTTPS URL including protocol

### 2. TESTNET_PRIVATE_KEY
- **Description**: Private key for the wallet that will deploy the contracts
- **Format**: 64-character hexadecimal string (with or without `0x` prefix)
- **Security**: This wallet should be used ONLY for testnet deployments and contain only testnet tokens

## Setting Up GitHub Secrets

1. Navigate to your GitHub repository
2. Go to **Settings** > **Secrets and variables** > **Actions**
3. Click **New repository secret**
4. Add each secret with the exact names listed above

## Deployed Contracts

The workflow deploys the following contracts in sequence:

1. **ButteredBread** - `script/deploy/DeployButteredBread.s.sol`
2. **YieldDistributor** - `script/deploy/DeployYieldDistributor.s.sol`
3. **NFTMultiplier** - `script/deploy/DeployNFTMultiplier.s.sol`
4. **VotingStreakMultiplier** - `script/deploy/DeployVotingStreakMultiplier.s.sol`

## Workflow Triggers

The deployment workflow runs automatically on:
- Push to `dev` branch (production testnet deployment)
- Push to `staging` branch (testing/validation deployment)

## Workflow Steps

1. **Build**: Compiles all contracts using `forge build`
2. **Test**: Runs tests with fork testing using the testnet RPC
3. **Deploy**: Executes each deployment script in sequence
4. **Logging**: Contract addresses and transaction hashes are logged in the workflow output

## Monitoring Deployments

- View deployment logs in the **Actions** tab of your GitHub repository
- Each deployment step will show the deployed contract addresses
- Failed deployments will stop the workflow and show error details

## Security Considerations

- Never use mainnet private keys for testnet deployments
- Testnet private keys should be separate from any production keys
- Monitor the testnet wallet balance to ensure sufficient gas funds
- Regularly rotate testnet private keys for security

## Troubleshooting

### Common Issues

1. **Insufficient Gas**: Ensure the deployment wallet has enough testnet tokens
2. **RPC Errors**: Verify the TESTNET_RPC_URL is correct and accessible
3. **Private Key Format**: Ensure the private key is properly formatted (64 hex characters)
4. **Contract Dependencies**: Some contracts may depend on others being deployed first

### Getting Help

- Check the GitHub Actions logs for detailed error messages
- Verify all secrets are properly set in repository settings
- Ensure the target testnet is operational and accessible