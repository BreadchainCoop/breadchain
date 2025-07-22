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

### 3. ETHERSCAN_API_KEY
- **Description**: API key for contract verification on block explorer (e.g., Etherscan, Gnosisscan)
- **Format**: Alphanumeric string provided by the block explorer service
- **Purpose**: Enables automatic contract source code verification after deployment
- **Optional**: Verification will be skipped if this secret is not provided

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
3. **Deploy**: Executes each deployment script in sequence, capturing contract addresses
4. **Verify**: Attempts to verify each deployed contract on the block explorer
5. **Artifact Generation**: Creates `deployment.json` with all contract addresses and verification status
6. **Logging**: Contract addresses and transaction hashes are logged in the workflow output

## Deployment Artifacts

After each deployment, the workflow generates several artifacts:

### deployment.json
Contains the complete deployment information:
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "network": "testnet", 
  "contracts": {
    "ButteredBread": "0x1234...",
    "YieldDistributor": "0x5678...",
    "NFTMultiplier": "0x9abc...",
    "VotingStreakMultiplier": "0xdef0..."
  },
  "verification_status": "success"
}
```

### Individual deployment files
- `butteredbread_deploy.json`
- `yielddistributor_deploy.json` 
- `nftmultiplier_deploy.json`
- `votingstreakMultiplier_deploy.json`

These artifacts are automatically uploaded and retained for 30 days.

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
5. **Verification Failures**: 
   - Check that ETHERSCAN_API_KEY is valid and has sufficient rate limits
   - Ensure the block explorer supports the target network
   - Verification may fail if contracts are not yet indexed (try again later)
6. **Missing Contract Addresses**: If deployment.json shows null addresses, check individual deployment logs for errors

### Getting Help

- Check the GitHub Actions logs for detailed error messages
- Verify all secrets are properly set in repository settings
- Ensure the target testnet is operational and accessible