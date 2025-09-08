# 🚨 DataDAO - Data Breach Notification DAO

## 📋 Overview

DataDAO is a decentralized autonomous organization built on Stacks that enables transparent reporting and verification of corporate data breaches through community-driven governance. Whistleblowers can submit breach reports, and DAO members vote on their validity while maintaining transparency and accountability.

## ✨ Key Features

- 🔐 **Whistleblower Protection**: Anonymous breach reporting with cryptographic evidence
- 🗳️ **Democratic Voting**: Stake-weighted voting system for proposal validation  
- 💰 **Incentive System**: Reward whistleblowers for verified breach reports
- 📊 **Company Tracking**: Maintain historical breach records and severity scores
- 🏛️ **DAO Governance**: Community-driven decision making with reputation system

## 🚀 Getting Started

### Prerequisites
- Clarinet CLI installed
- Stacks wallet with STX tokens

### Installation

```bash
git clone <repository-url>
cd datadao
clarinet check
```

## 📖 Usage Guide

### 1. Join the DAO 🤝

Before participating, you must join the DAO by staking the minimum required STX:

```clarity
(contract-call? .Datadao join-dao)
```

### 2. Submit a Breach Report 📝

Report a data breach with evidence:

```clarity
(contract-call? .Datadao submit-breach-report 
  "Company Name" 
  "Detailed breach description" 
  "evidence-hash-sha256" 
  u7)  ;; severity level 1-10
```

### 3. Vote on Proposals 🗳️

Cast your vote on breach reports:

```clarity
(contract-call? .Datadao vote-on-proposal u1 true)  ;; proposal-id, vote (true/false)
```

### 4. Finalize Proposals ⚖️

After voting period ends, finalize the proposal:

```clarity
(contract-call? .Datadao finalize-proposal u1)
```

### 5. Claim Rewards 💎

Whistleblowers can claim their rewards:

```clarity
(contract-call? .Datadao claim-rewards)
```

## 🔍 Read-Only Functions

### Get Proposal Details
```clarity
(contract-call? .Datadao get-proposal u1)
```

### Check Member Information
```clarity
(contract-call? .Datadao get-member-info 'SP1234...)
```

### View Company Breach History
```clarity
(contract-call? .Datadao get-company-history "Company Name")
```

### Check Pending Rewards
```clarity
(contract-call? .Datadao get-pending-rewards 'SP1234...)
```

## ⚙️ Configuration

- **Minimum Stake**: 1 STX (1,000,000 microSTX)
- **Voting Period**: 1,440 blocks (~10 days)
- **Quorum Threshold**: 51%
- **Reward Calculation**: Severity Level × 0.1 STX

## 🏗️ Contract Architecture

### Data Structures

- **DAO Members**: Stake amount, reputation, join date
- **Breach Proposals**: Company info, evidence, voting results
- **Voting Records**: Individual votes with stake weights
- **Company History**: Breach count and severity tracking
- **Reward Pool**: Pending whistleblower rewards

### Security Features

- ✅ Stake-based participation prevents spam
- ✅ Time-locked voting periods
- ✅ Cryptographic evidence hashing
- ✅ Reputation-based weighting
- ✅ Multi-signature proposal finalization

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request with tests
4. Ensure all Clarinet checks pass

## 📄 License

MIT License - see LICENSE file for details

## 🆘 Support

For questions or issues:
- Open a GitHub issue
- Join our Discord community
- Check the documentation wiki


