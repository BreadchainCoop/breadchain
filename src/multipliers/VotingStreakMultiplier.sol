// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IDynamicNFTMultiplier} from "src/interfaces/multipliers/IDynamicNFTMultiplier.sol";
import {YieldDistributor} from "src/YieldDistributor.sol";
import {IVotingStreakMultiplier} from "src/interfaces/multipliers/IVotingStreakMultiplier.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
/// @title VotingStreakMultiplier
/// @notice A contract for managing voting streak multipliers as NFTs
/// @dev Implements IDynamicNFTMultiplier interface

contract VotingStreakMultiplier is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    IDynamicNFTMultiplier,
    IVotingStreakMultiplier
{
    /// @notice The maximum multiplier incrementation
    uint256 public maxMultiplier;

    /// @notice The increment value for the multiplier
    uint256 public multiplierIncrement;

    /// @notice The YieldDistributor contract
    YieldDistributor public yieldDistributor;

    /// @notice Mapping of user addresses to their current multiplier factor
    mapping(address => uint256) public override userToFactor;

    /// @notice Mapping of user addresses to their multiplier validity period
    mapping(address => uint256) public override userToValidity;

    /// @notice Emitted when a user's multiplier is updated
    /// @param user The address of the user
    /// @param newFactor The new multiplier factor
    /// @param validity The new validity period
    event MultiplierUpdated(address indexed user, uint256 newFactor, uint256 validity);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param name The name of the NFT
    /// @param symbol The symbol of the NFT
    /// @param _yieldDistributor The address of the YieldDistributor contract
    /// @param _multiplierIncrement The initial multiplier increment value
    /// @param _maxMultiplier The maximum multiplier value
    function initialize(
        string memory name,
        string memory symbol,
        address _yieldDistributor,
        uint256 _multiplierIncrement,
        uint256 _maxMultiplier
    ) public initializer {
        __ERC721_init(name, symbol);
        __Ownable_init(msg.sender);

        yieldDistributor = YieldDistributor(_yieldDistributor);
        multiplierIncrement = _multiplierIncrement;
        maxMultiplier = _maxMultiplier;
    }

    /// @notice Updates the user's multiplier when a vote is cast
    /// @param voter The address of the voter
    function onVoteCast(address voter) external {
        require(msg.sender == address(yieldDistributor), "Only YieldDistributor can call");

        if (this.balanceOf(voter) == 0) {
            _safeMint(voter, uint256(uint160(voter)));
        }

        uint256 currentFactor = userToFactor[voter];
        uint256 newFactor = (currentFactor == 0)
            ? multiplierIncrement
            : Math.min(currentFactor + multiplierIncrement, maxMultiplier * multiplierIncrement);

        userToFactor[voter] = newFactor;
        userToValidity[voter] = yieldDistributor.lastClaimedBlockNumber() + 2 * yieldDistributor.cycleLength();

        emit MultiplierUpdated(voter, newFactor, userToValidity[voter]);
    }

    /// @notice Gets the current multiplying factor for a user
    /// @param user The address of the user
    /// @return The current multiplying factor
    function getMultiplyingFactor(address user) external view override returns (uint256) {
        if (block.number > userToValidity[user]) {
            return 0;
        }
        return userToFactor[user];
    }

    /// @notice Gets the validity period for a user's multiplier
    /// @param user The address of the user
    /// @return The block number until which the multiplier is valid
    function validUntil(address user) external view override returns (uint256) {
        return userToValidity[user];
    }

    /// @notice Checks if a user has an NFT
    /// @param user The address of the user
    /// @return True if the user has an NFT, false otherwise
    function hasNFT(address user) public view override returns (bool) {
        return balanceOf(user) > 0;
    }

    /// @notice Gets the address of this NFT contract
    /// @return The address of this contract as an IERC721
    function NFTAddress() external view override returns (IERC721) {
        return IERC721(address(this));
    }

    /// @notice Sets the YieldDistributor contract address
    /// @param _yieldDistributor The new YieldDistributor contract address
    function setYieldDistributor(address _yieldDistributor) external onlyOwner {
        yieldDistributor = YieldDistributor(_yieldDistributor);
    }

    /// @notice Sets the multiplier increment value
    /// @param _multiplierIncrement The new multiplier increment value
    function setMultiplierIncrement(uint256 _multiplierIncrement) external onlyOwner {
        multiplierIncrement = _multiplierIncrement;
    }

    /// @notice Sets the maximum multiplier value
    /// @param _maxMultiplier The new maximum multiplier value
    function setMaxMultiplier(uint256 _maxMultiplier) external onlyOwner {
        maxMultiplier = _maxMultiplier;
    }
}
