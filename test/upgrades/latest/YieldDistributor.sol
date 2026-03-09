// SPDX-License-Identifier: MIT
pragma solidity >=0.4.16 >=0.5.0 >=0.6.2 ^0.8.0 ^0.8.20 ^0.8.22 ^0.8.25 ^0.8.27;

// lib/gas-killer-solidity-sdk/flat/GasKillerSDK.flat.sol

// lib/eigenlayer-middleware/src/libraries/BN254.sol

// several functions are taken or adapted from https://github.com/HarryR/solcrypto/blob/master/contracts/altbn128.sol (MIT license):
// Copyright 2017 Christian Reitwiessner
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.

// The remainder of the code in this library is written by LayrLabs Inc. and is also under an MIT license

/**
 * @title Library for operations on the BN254 elliptic curve.
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 * @notice Contains BN254 parameters, common operations (addition, scalar mul, pairing), and BLS signature functionality.
 */
library BN254 {
    // modulus for the underlying field F_p of the elliptic curve
    uint256 internal constant FP_MODULUS =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;
    // modulus for the underlying field F_r of the elliptic curve
    uint256 internal constant FR_MODULUS =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    struct G1Point {
        uint256 X;
        uint256 Y;
    }

    // Encoding of field elements is: X[1] * i + X[0]
    struct G2Point {
        uint256[2] X;
        uint256[2] Y;
    }

    /// @dev Thrown when the sum of two points of G1 fails
    error ECAddFailed();
    /// @dev Thrown when the scalar multiplication of a point of G1 fails
    error ECMulFailed();
    /// @dev Thrown when the scalar is too large.
    error ScalarTooLarge();
    /// @dev Thrown when the pairing check fails
    error ECPairingFailed();
    /// @dev Thrown when the exponentiation mod fails
    error ExpModFailed();

    function generatorG1() internal pure returns (G1Point memory) {
        return G1Point(1, 2);
    }

    // generator of group G2
    /// @dev Generator point in F_q2 is of the form: (x0 + ix1, y0 + iy1).
    uint256 internal constant G2x1 =
        11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 internal constant G2x0 =
        10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 internal constant G2y1 =
        4082367875863433681332203403145435568316851327593401208105741076214120093531;
    uint256 internal constant G2y0 =
        8495653923123431417604973247489272438418190587263600148770280649306958101930;

    /// @notice returns the G2 generator
    /// @dev mind the ordering of the 1s and 0s!
    ///      this is because of the (unknown to us) convention used in the bn254 pairing precompile contract
    ///      "Elements a * i + b of F_p^2 are encoded as two elements of F_p, (a, b)."
    ///      https://github.com/ethereum/EIPs/blob/master/EIPS/eip-197.md#encoding
    function generatorG2() internal pure returns (G2Point memory) {
        return G2Point([G2x1, G2x0], [G2y1, G2y0]);
    }

    // negation of the generator of group G2
    /// @dev Generator point in F_q2 is of the form: (x0 + ix1, y0 + iy1).
    uint256 internal constant nG2x1 =
        11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 internal constant nG2x0 =
        10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 internal constant nG2y1 =
        17805874995975841540914202342111839520379459829704422454583296818431106115052;
    uint256 internal constant nG2y0 =
        13392588948715843804641432497768002650278120570034223513918757245338268106653;

    function negGeneratorG2() internal pure returns (G2Point memory) {
        return G2Point([nG2x1, nG2x0], [nG2y1, nG2y0]);
    }

    bytes32 internal constant powersOfTauMerkleRoot =
        0x22c998e49752bbb1918ba87d6d59dd0e83620a311ba91dd4b2cc84990b31b56f;

    /**
     * @param p Some point in G1.
     * @return The negation of `p`, i.e. p.plus(p.negate()) should be zero.
     */
    function negate(
        G1Point memory p
    ) internal pure returns (G1Point memory) {
        // The prime q in the base field F_q for G1
        if (p.X == 0 && p.Y == 0) {
            return G1Point(0, 0);
        } else {
            return G1Point(p.X, FP_MODULUS - (p.Y % FP_MODULUS));
        }
    }

    /**
     * @return r the sum of two points of G1
     */
    function plus(G1Point memory p1, G1Point memory p2) internal view returns (G1Point memory r) {
        uint256[4] memory input;
        input[0] = p1.X;
        input[1] = p1.Y;
        input[2] = p2.X;
        input[3] = p2.Y;
        bool success;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 6, input, 0x80, r, 0x40)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }

        require(success, ECAddFailed());
    }

    /**
     * @notice an optimized ecMul implementation that takes O(log_2(s)) ecAdds
     * @param p the point to multiply
     * @param s the scalar to multiply by
     * @dev this function is only safe to use if the scalar is 9 bits or less
     */
    function scalar_mul_tiny(
        BN254.G1Point memory p,
        uint16 s
    ) internal view returns (BN254.G1Point memory) {
        require(s < 2 ** 9, ScalarTooLarge());

        // if s is 1 return p
        if (s == 1) {
            return p;
        }

        // the accumulated product to return
        BN254.G1Point memory acc = BN254.G1Point(0, 0);
        // the 2^n*p to add to the accumulated product in each iteration
        BN254.G1Point memory p2n = p;
        // value of most significant bit
        uint16 m = 1;
        // index of most significant bit
        uint8 i = 0;

        //loop until we reach the most significant bit
        while (s >= m) {
            unchecked {
                // if the  current bit is 1, add the 2^n*p to the accumulated product
                if ((s >> i) & 1 == 1) {
                    acc = plus(acc, p2n);
                }
                // double the 2^n*p for the next iteration
                p2n = plus(p2n, p2n);

                // increment the index and double the value of the most significant bit
                m <<= 1;
                ++i;
            }
        }

        // return the accumulated product
        return acc;
    }

    /**
     * @return r the product of a point on G1 and a scalar, i.e.
     *         p == p.scalar_mul(1) and p.plus(p) == p.scalar_mul(2) for all
     *         points p.
     */
    function scalar_mul(G1Point memory p, uint256 s) internal view returns (G1Point memory r) {
        uint256[3] memory input;
        input[0] = p.X;
        input[1] = p.Y;
        input[2] = s;
        bool success;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 7, input, 0x60, r, 0x40)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }
        require(success, ECMulFailed());
    }

    /**
     *  @return The result of computing the pairing check
     *         e(p1[0], p2[0]) *  .... * e(p1[n], p2[n]) == 1
     *         For example,
     *         pairing([P1(), P1().negate()], [P2(), P2()]) should return true.
     */
    function pairing(
        G1Point memory a1,
        G2Point memory a2,
        G1Point memory b1,
        G2Point memory b2
    ) internal view returns (bool) {
        G1Point[2] memory p1 = [a1, b1];
        G2Point[2] memory p2 = [a2, b2];

        uint256[12] memory input;

        for (uint256 i = 0; i < 2; i++) {
            uint256 j = i * 6;
            input[j + 0] = p1[i].X;
            input[j + 1] = p1[i].Y;
            input[j + 2] = p2[i].X[0];
            input[j + 3] = p2[i].X[1];
            input[j + 4] = p2[i].Y[0];
            input[j + 5] = p2[i].Y[1];
        }

        uint256[1] memory out;
        bool success;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 8, input, mul(12, 0x20), out, 0x20)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }

        require(success, ECPairingFailed());

        return out[0] != 0;
    }

    /**
     * @notice This function is functionally the same as pairing(), however it specifies a gas limit
     *         the user can set, as a precompile may use the entire gas budget if it reverts.
     */
    function safePairing(
        G1Point memory a1,
        G2Point memory a2,
        G1Point memory b1,
        G2Point memory b2,
        uint256 pairingGas
    ) internal view returns (bool, bool) {
        G1Point[2] memory p1 = [a1, b1];
        G2Point[2] memory p2 = [a2, b2];

        uint256[12] memory input;

        for (uint256 i = 0; i < 2; i++) {
            uint256 j = i * 6;
            input[j + 0] = p1[i].X;
            input[j + 1] = p1[i].Y;
            input[j + 2] = p2[i].X[0];
            input[j + 3] = p2[i].X[1];
            input[j + 4] = p2[i].Y[0];
            input[j + 5] = p2[i].Y[1];
        }

        uint256[1] memory out;
        bool success;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(pairingGas, 8, input, mul(12, 0x20), out, 0x20)
        }

        //Out is the output of the pairing precompile, either 0 or 1 based on whether the two pairings are equal.
        //Success is true if the precompile actually goes through (aka all inputs are valid)

        return (success, out[0] != 0);
    }

    /// @return hashedG1 the keccak256 hash of the G1 Point
    /// @dev used for BLS signatures
    function hashG1Point(
        BN254.G1Point memory pk
    ) internal pure returns (bytes32 hashedG1) {
        assembly {
            mstore(0, mload(pk))
            mstore(0x20, mload(add(0x20, pk)))
            hashedG1 := keccak256(0, 0x40)
        }
    }

    /// @return the keccak256 hash of the G2 Point
    /// @dev used for BLS signatures
    function hashG2Point(
        BN254.G2Point memory pk
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(pk.X[0], pk.X[1], pk.Y[0], pk.Y[1]));
    }

    /**
     * @notice adapted from https://github.com/HarryR/solcrypto/blob/master/contracts/altbn128.sol
     */
    function hashToG1(
        bytes32 _x
    ) internal view returns (G1Point memory) {
        uint256 beta = 0;
        uint256 y = 0;

        uint256 x = uint256(_x) % FP_MODULUS;

        while (true) {
            (beta, y) = findYFromX(x);

            // y^2 == beta
            if (beta == mulmod(y, y, FP_MODULUS)) {
                return G1Point(x, y);
            }

            x = addmod(x, 1, FP_MODULUS);
        }
        return G1Point(0, 0);
    }

    /**
     * Given X, find Y
     *
     *   where y = sqrt(x^3 + b)
     *
     * Returns: (x^3 + b), y
     */
    function findYFromX(
        uint256 x
    ) internal view returns (uint256, uint256) {
        // beta = (x^3 + b) % p
        uint256 beta = addmod(mulmod(mulmod(x, x, FP_MODULUS), x, FP_MODULUS), 3, FP_MODULUS);

        // y^2 = x^3 + b
        // this acts like: y = sqrt(beta) = beta^((p+1) / 4)
        uint256 y = expMod(
            beta, 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52, FP_MODULUS
        );

        return (beta, y);
    }

    function expMod(
        uint256 _base,
        uint256 _exponent,
        uint256 _modulus
    ) internal view returns (uint256 retval) {
        bool success;
        uint256[1] memory output;
        uint256[6] memory input;
        input[0] = 0x20; // baseLen = new(big.Int).SetBytes(getData(input, 0, 32))
        input[1] = 0x20; // expLen  = new(big.Int).SetBytes(getData(input, 32, 32))
        input[2] = 0x20; // modLen  = new(big.Int).SetBytes(getData(input, 64, 32))
        input[3] = _base;
        input[4] = _exponent;
        input[5] = _modulus;
        assembly {
            success := staticcall(sub(gas(), 2000), 5, input, 0xc0, output, 0x20)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }
        require(success, ExpModFailed());
        return output[0];
    }
}

// lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol

interface IAVSRegistrar {
    /**
     * @notice Called by the AllocationManager when an operator wants to register
     * for one or more operator sets. This method should revert if registration
     * is unsuccessful.
     * @param operator the registering operator
     * @param avs the AVS the operator is registering for. This should be the same as IAVSRegistrar.avs()
     * @param operatorSetIds the list of operator set ids being registered for
     * @param data arbitrary data the operator can provide as part of registration
     */
    function registerOperator(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external;

    /**
     * @notice Called by the AllocationManager when an operator is deregistered from
     * one or more operator sets. If this method reverts, it is ignored.
     * @param operator the deregistering operator
     * @param avs the AVS the operator is deregistering from. This should be the same as IAVSRegistrar.avs()
     * @param operatorSetIds the list of operator set ids being deregistered from
     */
    function deregisterOperator(address operator, address avs, uint32[] calldata operatorSetIds) external;

    /**
     * @notice Returns true if the AVS is supported by the registrar
     * @param avs the AVS to check
     * @return true if the AVS is supported, false otherwise
     */
    function supportsAVS(
        address avs
    ) external view returns (bool);
}

// lib/forge-std/src/interfaces/IERC165.sol

interface IERC165 {
    /// @notice Query if a contract implements an interface
    /// @param interfaceID The interface identifier, as specified in ERC-165
    /// @dev Interface identification is specified in ERC-165. This function
    /// uses less than 30,000 gas.
    /// @return `true` if the contract implements `interfaceID` and
    /// `interfaceID` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceID) external view returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20_0 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// lib/eigenlayer-middleware/src/interfaces/IIndexRegistry.sol

interface IIndexRegistryErrors {
    /// @notice Thrown when a function is called by an address that is not the RegistryCoordinator.
    error OnlyRegistryCoordinator();
    /// @notice Thrown when attempting to query a quorum that has no history.
    error QuorumDoesNotExist();
    /// @notice Thrown when attempting to look up an operator that does not exist at the specified block number.
    error OperatorIdDoesNotExist();
}

interface IIndexRegistryTypes {
    /// @notice Represents an update to an operator's status at a specific index.
    /// @param fromBlockNumber The block number from which this update takes effect.
    /// @param operatorId The unique identifier of the operator.
    struct OperatorUpdate {
        uint32 fromBlockNumber;
        bytes32 operatorId;
    }

    /// @notice Represents an update to the total number of operators in a quorum.
    /// @param fromBlockNumber The block number from which this update takes effect.
    /// @param numOperators The total number of operators after the update.
    struct QuorumUpdate {
        uint32 fromBlockNumber;
        uint32 numOperators;
    }
}

interface IIndexRegistryEvents is IIndexRegistryTypes {
    /*
     * @notice Emitted when an operator's index in a quorum is updated.
     * @param operatorId The unique identifier of the operator.
     * @param quorumNumber The identifier of the quorum.
     * @param newOperatorIndex The new index assigned to the operator.
     */
    event QuorumIndexUpdate(
        bytes32 indexed operatorId, uint8 quorumNumber, uint32 newOperatorIndex
    );
}

interface IIndexRegistry is IIndexRegistryErrors, IIndexRegistryEvents {
    /*
     * @notice Returns the special identifier used to indicate a non-existent operator.
     * @return The bytes32 constant OPERATOR_DOES_NOT_EXIST_ID.
     */
    function OPERATOR_DOES_NOT_EXIST_ID() external pure returns (bytes32);

    /*
     * @notice Returns the address of the RegistryCoordinator contract.
     * @return The address of the RegistryCoordinator.
     */
    function registryCoordinator() external view returns (address);

    /*
     * @notice Returns the current index of an operator with ID `operatorId` in quorum `quorumNumber`.
     * @dev This mapping is NOT updated when an operator is deregistered,
     * so it's possible that an index retrieved from this mapping is inaccurate.
     * If you're querying for an operator that might be deregistered, ALWAYS
     * check this index against the latest `_operatorIndexHistory` entry.
     * @param quorumNumber The identifier of the quorum.
     * @param operatorId The unique identifier of the operator.
     * @return The current index of the operator.
     */
    function currentOperatorIndex(
        uint8 quorumNumber,
        bytes32 operatorId
    ) external view returns (uint32);

    // ACTIONS

    /*
     * @notice Registers the operator with the specified `operatorId` for the quorums specified by `quorumNumbers`.
     * @param operatorId The unique identifier of the operator.
     * @param quorumNumbers The quorum numbers to register for.
     * @return An array containing a list of the number of operators (including the registering operator)
     *         in each of the quorums the operator is registered for.
     * @dev Access restricted to the RegistryCoordinator.
     * @dev Preconditions:
     *         1) `quorumNumbers` has no duplicates
     *         2) `quorumNumbers.length` != 0
     *         3) `quorumNumbers` is ordered in ascending order
     *         4) the operator is not already registered
     */
    function registerOperator(
        bytes32 operatorId,
        bytes calldata quorumNumbers
    ) external returns (uint32[] memory);

    /*
     * @notice Deregisters the operator with the specified `operatorId` for the quorums specified by `quorumNumbers`.
     * @param operatorId The unique identifier of the operator.
     * @param quorumNumbers The quorum numbers to deregister from.
     * @dev Access restricted to the RegistryCoordinator.
     * @dev Preconditions:
     *         1) `quorumNumbers` has no duplicates
     *         2) `quorumNumbers.length` != 0
     *         3) `quorumNumbers` is ordered in ascending order
     *         4) the operator is not already deregistered
     *         5) `quorumNumbers` is a subset of the quorumNumbers that the operator is registered for
     */
    function deregisterOperator(bytes32 operatorId, bytes calldata quorumNumbers) external;

    /*
     * @notice Initializes a new quorum `quorumNumber`.
     * @param quorumNumber The identifier of the quorum to initialize.
     */
    function initializeQuorum(
        uint8 quorumNumber
    ) external;

    // VIEW

    /*
     * @notice Returns the operator update at index `arrayIndex` for operator at index `operatorIndex` in quorum `quorumNumber`.
     * @param quorumNumber The identifier of the quorum.
     * @param operatorIndex The index of the operator.
     * @param arrayIndex The index in the update history.
     * @return The operator update entry.
     */
    function getOperatorUpdateAtIndex(
        uint8 quorumNumber,
        uint32 operatorIndex,
        uint32 arrayIndex
    ) external view returns (OperatorUpdate memory);

    /*
     * @notice Returns the quorum update at index `quorumIndex` for quorum `quorumNumber`.
     * @param quorumNumber The identifier of the quorum.
     * @param quorumIndex The index in the quorum's update history.
     * @return The quorum update entry.
     */
    function getQuorumUpdateAtIndex(
        uint8 quorumNumber,
        uint32 quorumIndex
    ) external view returns (QuorumUpdate memory);

    /*
     * @notice Returns the latest quorum update for quorum `quorumNumber`.
     * @param quorumNumber The identifier of the quorum.
     * @return The most recent quorum update.
     */
    function getLatestQuorumUpdate(
        uint8 quorumNumber
    ) external view returns (QuorumUpdate memory);

    /*
     * @notice Returns the latest operator update for operator at index `operatorIndex` in quorum `quorumNumber`.
     * @param quorumNumber The identifier of the quorum.
     * @param operatorIndex The index of the operator.
     * @return The most recent operator update.
     */
    function getLatestOperatorUpdate(
        uint8 quorumNumber,
        uint32 operatorIndex
    ) external view returns (OperatorUpdate memory);

    /*
     * @notice Returns the list of operators in quorum `quorumNumber` at block `blockNumber`.
     * @param quorumNumber The identifier of the quorum.
     * @param blockNumber The block number to query.
     * @return An array of operator IDs.
     */
    function getOperatorListAtBlockNumber(
        uint8 quorumNumber,
        uint32 blockNumber
    ) external view returns (bytes32[] memory);

    /*
     * @notice Returns the total number of operators in quorum `quorumNumber`.
     * @param quorumNumber The identifier of the quorum.
     * @return The total number of operators.
     */
    function totalOperatorsForQuorum(
        uint8 quorumNumber
    ) external view returns (uint32);

    /*
     * @notice Returns the total number of operators in quorum `quorumNumber` at block `blockNumber`.
     * @param quorumNumber The identifier of the quorum.
     * @param blockNumber The block number to query.
     * @return The total number of operators at the specified block.
     */
    function totalOperatorsForQuorumAtBlockNumber(
        uint8 quorumNumber,
        uint32 blockNumber
    ) external view returns (uint32);
}

// lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol

/**
 * @title Interface for the `PauserRegistry` contract.
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 */
interface IPauserRegistry {
    error OnlyUnpauser();
    error InputAddressZero();

    event PauserStatusChanged(address pauser, bool canPause);

    event UnpauserChanged(address previousUnpauser, address newUnpauser);

    /// @notice Mapping of addresses to whether they hold the pauser role.
    function isPauser(
        address pauser
    ) external view returns (bool);

    /// @notice Unique address that holds the unpauser role. Capable of changing *both* the pauser and unpauser addresses.
    function unpauser() external view returns (address);
}

// lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ISemVerMixin.sol

/// @title ISemVerMixin
/// @notice A mixin interface that provides semantic versioning functionality.
/// @dev Follows SemVer 2.0.0 specification (https://semver.org/)
interface ISemVerMixin {
    /// @notice Returns the semantic version string of the contract.
    /// @return The version string in SemVer format (e.g., "v1.1.1")
    function version() external view returns (string memory);
}

// lib/eigenlayer-middleware/src/interfaces/ISocketRegistry.sol

interface ISocketRegistryErrors {
    /// @notice Thrown when the caller is not the SlashingRegistryCoordinator
    error OnlySlashingRegistryCoordinator();
}

interface ISocketRegistry is ISocketRegistryErrors {
    /**
     * @notice Sets the socket for an operator.
     * @param _operatorId The id of the operator to set the socket for.
     * @param _socket The socket (any arbitrary string as deemed useful by an AVS) to set.
     * @dev Only callable by the SlashingRegistryCoordinator.
     */
    function setOperatorSocket(bytes32 _operatorId, string memory _socket) external;

    /**
     * @notice Gets the stored socket for an operator.
     * @param _operatorId The id of the operator to query.
     * @return The stored socket associated with the operator.
     */
    function getOperatorSocket(
        bytes32 _operatorId
    ) external view returns (string memory);
}

// lib/openzeppelin-contracts/contracts/utils/math/Math.sol

// OpenZeppelin Contracts (last updated v4.9.0) (utils/math/Math.sol)

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math_0 {
    enum Rounding {
        Down, // Toward negative infinity
        Up, // Toward infinity
        Zero // Toward zero
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv)
     * with further edits by Uniswap Labs also under MIT license.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            require(denominator > prod1, "Math: mulDiv overflow");

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator. Always >= 1.
            // See https://cs.stackexchange.com/q/138556/92363.

            // Does not overflow because the denominator cannot be zero at this stage in the function.
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2^256 / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
            // in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (rounding == Rounding.Up && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded down.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        //
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`. This value can be written `msb(a)=2**k` with `k=log2(a)`.
        //
        // This can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
        // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
        //
        // Consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1 << (log2(a) >> 1);

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + (rounding == Rounding.Up && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + (rounding == Rounding.Up && 1 << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + (rounding == Rounding.Up && 10 ** result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256, rounded down, of a positive value.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (rounding == Rounding.Up && 1 << (result << 3) < value ? 1 : 0);
        }
    }
}

// lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol

using OperatorSetLib for OperatorSet global;

/**
 * @notice An operator set identified by the AVS address and an identifier
 * @param avs The address of the AVS this operator set belongs to
 * @param id The unique identifier for the operator set
 */
struct OperatorSet {
    address avs;
    uint32 id;
}

library OperatorSetLib {
    function key(
        OperatorSet memory os
    ) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(os.avs, uint96(os.id)));
    }

    function decode(
        bytes32 _key
    ) internal pure returns (OperatorSet memory) {
        /// forgefmt: disable-next-item
        return OperatorSet({
            avs: address(uint160(uint256(_key) >> 96)),
            id: uint32(uint256(_key) & type(uint96).max)
        });
    }
}

// lib/eigenlayer-middleware/lib/openzeppelin-contracts-upgradeable/contracts/utils/math/SafeCastUpgradeable.sol

// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/SafeCast.sol)
// This file was procedurally generated from scripts/generate/templates/SafeCast.js.

/**
 * @dev Wrappers over Solidity's uintXX/intXX casting operators with added overflow
 * checks.
 *
 * Downcasting from uint256/int256 in Solidity does not revert on overflow. This can
 * easily result in undesired exploitation or bugs, since developers usually
 * assume that overflows raise errors. `SafeCast` restores this intuition by
 * reverting the transaction when such an operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 *
 * Can be combined with {SafeMath} and {SignedSafeMath} to extend it to smaller types, by performing
 * all math on `uint256` and `int256` and then downcasting.
 */
library SafeCastUpgradeable {
    /**
     * @dev Returns the downcasted uint248 from uint256, reverting on
     * overflow (when the input is greater than largest uint248).
     *
     * Counterpart to Solidity's `uint248` operator.
     *
     * Requirements:
     *
     * - input must fit into 248 bits
     *
     * _Available since v4.7._
     */
    function toUint248(uint256 value) internal pure returns (uint248) {
        require(value <= type(uint248).max, "SafeCast: value doesn't fit in 248 bits");
        return uint248(value);
    }

    /**
     * @dev Returns the downcasted uint240 from uint256, reverting on
     * overflow (when the input is greater than largest uint240).
     *
     * Counterpart to Solidity's `uint240` operator.
     *
     * Requirements:
     *
     * - input must fit into 240 bits
     *
     * _Available since v4.7._
     */
    function toUint240(uint256 value) internal pure returns (uint240) {
        require(value <= type(uint240).max, "SafeCast: value doesn't fit in 240 bits");
        return uint240(value);
    }

    /**
     * @dev Returns the downcasted uint232 from uint256, reverting on
     * overflow (when the input is greater than largest uint232).
     *
     * Counterpart to Solidity's `uint232` operator.
     *
     * Requirements:
     *
     * - input must fit into 232 bits
     *
     * _Available since v4.7._
     */
    function toUint232(uint256 value) internal pure returns (uint232) {
        require(value <= type(uint232).max, "SafeCast: value doesn't fit in 232 bits");
        return uint232(value);
    }

    /**
     * @dev Returns the downcasted uint224 from uint256, reverting on
     * overflow (when the input is greater than largest uint224).
     *
     * Counterpart to Solidity's `uint224` operator.
     *
     * Requirements:
     *
     * - input must fit into 224 bits
     *
     * _Available since v4.2._
     */
    function toUint224(uint256 value) internal pure returns (uint224) {
        require(value <= type(uint224).max, "SafeCast: value doesn't fit in 224 bits");
        return uint224(value);
    }

    /**
     * @dev Returns the downcasted uint216 from uint256, reverting on
     * overflow (when the input is greater than largest uint216).
     *
     * Counterpart to Solidity's `uint216` operator.
     *
     * Requirements:
     *
     * - input must fit into 216 bits
     *
     * _Available since v4.7._
     */
    function toUint216(uint256 value) internal pure returns (uint216) {
        require(value <= type(uint216).max, "SafeCast: value doesn't fit in 216 bits");
        return uint216(value);
    }

    /**
     * @dev Returns the downcasted uint208 from uint256, reverting on
     * overflow (when the input is greater than largest uint208).
     *
     * Counterpart to Solidity's `uint208` operator.
     *
     * Requirements:
     *
     * - input must fit into 208 bits
     *
     * _Available since v4.7._
     */
    function toUint208(uint256 value) internal pure returns (uint208) {
        require(value <= type(uint208).max, "SafeCast: value doesn't fit in 208 bits");
        return uint208(value);
    }

    /**
     * @dev Returns the downcasted uint200 from uint256, reverting on
     * overflow (when the input is greater than largest uint200).
     *
     * Counterpart to Solidity's `uint200` operator.
     *
     * Requirements:
     *
     * - input must fit into 200 bits
     *
     * _Available since v4.7._
     */
    function toUint200(uint256 value) internal pure returns (uint200) {
        require(value <= type(uint200).max, "SafeCast: value doesn't fit in 200 bits");
        return uint200(value);
    }

    /**
     * @dev Returns the downcasted uint192 from uint256, reverting on
     * overflow (when the input is greater than largest uint192).
     *
     * Counterpart to Solidity's `uint192` operator.
     *
     * Requirements:
     *
     * - input must fit into 192 bits
     *
     * _Available since v4.7._
     */
    function toUint192(uint256 value) internal pure returns (uint192) {
        require(value <= type(uint192).max, "SafeCast: value doesn't fit in 192 bits");
        return uint192(value);
    }

    /**
     * @dev Returns the downcasted uint184 from uint256, reverting on
     * overflow (when the input is greater than largest uint184).
     *
     * Counterpart to Solidity's `uint184` operator.
     *
     * Requirements:
     *
     * - input must fit into 184 bits
     *
     * _Available since v4.7._
     */
    function toUint184(uint256 value) internal pure returns (uint184) {
        require(value <= type(uint184).max, "SafeCast: value doesn't fit in 184 bits");
        return uint184(value);
    }

    /**
     * @dev Returns the downcasted uint176 from uint256, reverting on
     * overflow (when the input is greater than largest uint176).
     *
     * Counterpart to Solidity's `uint176` operator.
     *
     * Requirements:
     *
     * - input must fit into 176 bits
     *
     * _Available since v4.7._
     */
    function toUint176(uint256 value) internal pure returns (uint176) {
        require(value <= type(uint176).max, "SafeCast: value doesn't fit in 176 bits");
        return uint176(value);
    }

    /**
     * @dev Returns the downcasted uint168 from uint256, reverting on
     * overflow (when the input is greater than largest uint168).
     *
     * Counterpart to Solidity's `uint168` operator.
     *
     * Requirements:
     *
     * - input must fit into 168 bits
     *
     * _Available since v4.7._
     */
    function toUint168(uint256 value) internal pure returns (uint168) {
        require(value <= type(uint168).max, "SafeCast: value doesn't fit in 168 bits");
        return uint168(value);
    }

    /**
     * @dev Returns the downcasted uint160 from uint256, reverting on
     * overflow (when the input is greater than largest uint160).
     *
     * Counterpart to Solidity's `uint160` operator.
     *
     * Requirements:
     *
     * - input must fit into 160 bits
     *
     * _Available since v4.7._
     */
    function toUint160(uint256 value) internal pure returns (uint160) {
        require(value <= type(uint160).max, "SafeCast: value doesn't fit in 160 bits");
        return uint160(value);
    }

    /**
     * @dev Returns the downcasted uint152 from uint256, reverting on
     * overflow (when the input is greater than largest uint152).
     *
     * Counterpart to Solidity's `uint152` operator.
     *
     * Requirements:
     *
     * - input must fit into 152 bits
     *
     * _Available since v4.7._
     */
    function toUint152(uint256 value) internal pure returns (uint152) {
        require(value <= type(uint152).max, "SafeCast: value doesn't fit in 152 bits");
        return uint152(value);
    }

    /**
     * @dev Returns the downcasted uint144 from uint256, reverting on
     * overflow (when the input is greater than largest uint144).
     *
     * Counterpart to Solidity's `uint144` operator.
     *
     * Requirements:
     *
     * - input must fit into 144 bits
     *
     * _Available since v4.7._
     */
    function toUint144(uint256 value) internal pure returns (uint144) {
        require(value <= type(uint144).max, "SafeCast: value doesn't fit in 144 bits");
        return uint144(value);
    }

    /**
     * @dev Returns the downcasted uint136 from uint256, reverting on
     * overflow (when the input is greater than largest uint136).
     *
     * Counterpart to Solidity's `uint136` operator.
     *
     * Requirements:
     *
     * - input must fit into 136 bits
     *
     * _Available since v4.7._
     */
    function toUint136(uint256 value) internal pure returns (uint136) {
        require(value <= type(uint136).max, "SafeCast: value doesn't fit in 136 bits");
        return uint136(value);
    }

    /**
     * @dev Returns the downcasted uint128 from uint256, reverting on
     * overflow (when the input is greater than largest uint128).
     *
     * Counterpart to Solidity's `uint128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     *
     * _Available since v2.5._
     */
    function toUint128(uint256 value) internal pure returns (uint128) {
        require(value <= type(uint128).max, "SafeCast: value doesn't fit in 128 bits");
        return uint128(value);
    }

    /**
     * @dev Returns the downcasted uint120 from uint256, reverting on
     * overflow (when the input is greater than largest uint120).
     *
     * Counterpart to Solidity's `uint120` operator.
     *
     * Requirements:
     *
     * - input must fit into 120 bits
     *
     * _Available since v4.7._
     */
    function toUint120(uint256 value) internal pure returns (uint120) {
        require(value <= type(uint120).max, "SafeCast: value doesn't fit in 120 bits");
        return uint120(value);
    }

    /**
     * @dev Returns the downcasted uint112 from uint256, reverting on
     * overflow (when the input is greater than largest uint112).
     *
     * Counterpart to Solidity's `uint112` operator.
     *
     * Requirements:
     *
     * - input must fit into 112 bits
     *
     * _Available since v4.7._
     */
    function toUint112(uint256 value) internal pure returns (uint112) {
        require(value <= type(uint112).max, "SafeCast: value doesn't fit in 112 bits");
        return uint112(value);
    }

    /**
     * @dev Returns the downcasted uint104 from uint256, reverting on
     * overflow (when the input is greater than largest uint104).
     *
     * Counterpart to Solidity's `uint104` operator.
     *
     * Requirements:
     *
     * - input must fit into 104 bits
     *
     * _Available since v4.7._
     */
    function toUint104(uint256 value) internal pure returns (uint104) {
        require(value <= type(uint104).max, "SafeCast: value doesn't fit in 104 bits");
        return uint104(value);
    }

    /**
     * @dev Returns the downcasted uint96 from uint256, reverting on
     * overflow (when the input is greater than largest uint96).
     *
     * Counterpart to Solidity's `uint96` operator.
     *
     * Requirements:
     *
     * - input must fit into 96 bits
     *
     * _Available since v4.2._
     */
    function toUint96(uint256 value) internal pure returns (uint96) {
        require(value <= type(uint96).max, "SafeCast: value doesn't fit in 96 bits");
        return uint96(value);
    }

    /**
     * @dev Returns the downcasted uint88 from uint256, reverting on
     * overflow (when the input is greater than largest uint88).
     *
     * Counterpart to Solidity's `uint88` operator.
     *
     * Requirements:
     *
     * - input must fit into 88 bits
     *
     * _Available since v4.7._
     */
    function toUint88(uint256 value) internal pure returns (uint88) {
        require(value <= type(uint88).max, "SafeCast: value doesn't fit in 88 bits");
        return uint88(value);
    }

    /**
     * @dev Returns the downcasted uint80 from uint256, reverting on
     * overflow (when the input is greater than largest uint80).
     *
     * Counterpart to Solidity's `uint80` operator.
     *
     * Requirements:
     *
     * - input must fit into 80 bits
     *
     * _Available since v4.7._
     */
    function toUint80(uint256 value) internal pure returns (uint80) {
        require(value <= type(uint80).max, "SafeCast: value doesn't fit in 80 bits");
        return uint80(value);
    }

    /**
     * @dev Returns the downcasted uint72 from uint256, reverting on
     * overflow (when the input is greater than largest uint72).
     *
     * Counterpart to Solidity's `uint72` operator.
     *
     * Requirements:
     *
     * - input must fit into 72 bits
     *
     * _Available since v4.7._
     */
    function toUint72(uint256 value) internal pure returns (uint72) {
        require(value <= type(uint72).max, "SafeCast: value doesn't fit in 72 bits");
        return uint72(value);
    }

    /**
     * @dev Returns the downcasted uint64 from uint256, reverting on
     * overflow (when the input is greater than largest uint64).
     *
     * Counterpart to Solidity's `uint64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     *
     * _Available since v2.5._
     */
    function toUint64(uint256 value) internal pure returns (uint64) {
        require(value <= type(uint64).max, "SafeCast: value doesn't fit in 64 bits");
        return uint64(value);
    }

    /**
     * @dev Returns the downcasted uint56 from uint256, reverting on
     * overflow (when the input is greater than largest uint56).
     *
     * Counterpart to Solidity's `uint56` operator.
     *
     * Requirements:
     *
     * - input must fit into 56 bits
     *
     * _Available since v4.7._
     */
    function toUint56(uint256 value) internal pure returns (uint56) {
        require(value <= type(uint56).max, "SafeCast: value doesn't fit in 56 bits");
        return uint56(value);
    }

    /**
     * @dev Returns the downcasted uint48 from uint256, reverting on
     * overflow (when the input is greater than largest uint48).
     *
     * Counterpart to Solidity's `uint48` operator.
     *
     * Requirements:
     *
     * - input must fit into 48 bits
     *
     * _Available since v4.7._
     */
    function toUint48(uint256 value) internal pure returns (uint48) {
        require(value <= type(uint48).max, "SafeCast: value doesn't fit in 48 bits");
        return uint48(value);
    }

    /**
     * @dev Returns the downcasted uint40 from uint256, reverting on
     * overflow (when the input is greater than largest uint40).
     *
     * Counterpart to Solidity's `uint40` operator.
     *
     * Requirements:
     *
     * - input must fit into 40 bits
     *
     * _Available since v4.7._
     */
    function toUint40(uint256 value) internal pure returns (uint40) {
        require(value <= type(uint40).max, "SafeCast: value doesn't fit in 40 bits");
        return uint40(value);
    }

    /**
     * @dev Returns the downcasted uint32 from uint256, reverting on
     * overflow (when the input is greater than largest uint32).
     *
     * Counterpart to Solidity's `uint32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     *
     * _Available since v2.5._
     */
    function toUint32(uint256 value) internal pure returns (uint32) {
        require(value <= type(uint32).max, "SafeCast: value doesn't fit in 32 bits");
        return uint32(value);
    }

    /**
     * @dev Returns the downcasted uint24 from uint256, reverting on
     * overflow (when the input is greater than largest uint24).
     *
     * Counterpart to Solidity's `uint24` operator.
     *
     * Requirements:
     *
     * - input must fit into 24 bits
     *
     * _Available since v4.7._
     */
    function toUint24(uint256 value) internal pure returns (uint24) {
        require(value <= type(uint24).max, "SafeCast: value doesn't fit in 24 bits");
        return uint24(value);
    }

    /**
     * @dev Returns the downcasted uint16 from uint256, reverting on
     * overflow (when the input is greater than largest uint16).
     *
     * Counterpart to Solidity's `uint16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     *
     * _Available since v2.5._
     */
    function toUint16(uint256 value) internal pure returns (uint16) {
        require(value <= type(uint16).max, "SafeCast: value doesn't fit in 16 bits");
        return uint16(value);
    }

    /**
     * @dev Returns the downcasted uint8 from uint256, reverting on
     * overflow (when the input is greater than largest uint8).
     *
     * Counterpart to Solidity's `uint8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits
     *
     * _Available since v2.5._
     */
    function toUint8(uint256 value) internal pure returns (uint8) {
        require(value <= type(uint8).max, "SafeCast: value doesn't fit in 8 bits");
        return uint8(value);
    }

    /**
     * @dev Converts a signed int256 into an unsigned uint256.
     *
     * Requirements:
     *
     * - input must be greater than or equal to 0.
     *
     * _Available since v3.0._
     */
    function toUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0, "SafeCast: value must be positive");
        return uint256(value);
    }

    /**
     * @dev Returns the downcasted int248 from int256, reverting on
     * overflow (when the input is less than smallest int248 or
     * greater than largest int248).
     *
     * Counterpart to Solidity's `int248` operator.
     *
     * Requirements:
     *
     * - input must fit into 248 bits
     *
     * _Available since v4.7._
     */
    function toInt248(int256 value) internal pure returns (int248 downcasted) {
        downcasted = int248(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 248 bits");
    }

    /**
     * @dev Returns the downcasted int240 from int256, reverting on
     * overflow (when the input is less than smallest int240 or
     * greater than largest int240).
     *
     * Counterpart to Solidity's `int240` operator.
     *
     * Requirements:
     *
     * - input must fit into 240 bits
     *
     * _Available since v4.7._
     */
    function toInt240(int256 value) internal pure returns (int240 downcasted) {
        downcasted = int240(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 240 bits");
    }

    /**
     * @dev Returns the downcasted int232 from int256, reverting on
     * overflow (when the input is less than smallest int232 or
     * greater than largest int232).
     *
     * Counterpart to Solidity's `int232` operator.
     *
     * Requirements:
     *
     * - input must fit into 232 bits
     *
     * _Available since v4.7._
     */
    function toInt232(int256 value) internal pure returns (int232 downcasted) {
        downcasted = int232(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 232 bits");
    }

    /**
     * @dev Returns the downcasted int224 from int256, reverting on
     * overflow (when the input is less than smallest int224 or
     * greater than largest int224).
     *
     * Counterpart to Solidity's `int224` operator.
     *
     * Requirements:
     *
     * - input must fit into 224 bits
     *
     * _Available since v4.7._
     */
    function toInt224(int256 value) internal pure returns (int224 downcasted) {
        downcasted = int224(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 224 bits");
    }

    /**
     * @dev Returns the downcasted int216 from int256, reverting on
     * overflow (when the input is less than smallest int216 or
     * greater than largest int216).
     *
     * Counterpart to Solidity's `int216` operator.
     *
     * Requirements:
     *
     * - input must fit into 216 bits
     *
     * _Available since v4.7._
     */
    function toInt216(int256 value) internal pure returns (int216 downcasted) {
        downcasted = int216(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 216 bits");
    }

    /**
     * @dev Returns the downcasted int208 from int256, reverting on
     * overflow (when the input is less than smallest int208 or
     * greater than largest int208).
     *
     * Counterpart to Solidity's `int208` operator.
     *
     * Requirements:
     *
     * - input must fit into 208 bits
     *
     * _Available since v4.7._
     */
    function toInt208(int256 value) internal pure returns (int208 downcasted) {
        downcasted = int208(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 208 bits");
    }

    /**
     * @dev Returns the downcasted int200 from int256, reverting on
     * overflow (when the input is less than smallest int200 or
     * greater than largest int200).
     *
     * Counterpart to Solidity's `int200` operator.
     *
     * Requirements:
     *
     * - input must fit into 200 bits
     *
     * _Available since v4.7._
     */
    function toInt200(int256 value) internal pure returns (int200 downcasted) {
        downcasted = int200(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 200 bits");
    }

    /**
     * @dev Returns the downcasted int192 from int256, reverting on
     * overflow (when the input is less than smallest int192 or
     * greater than largest int192).
     *
     * Counterpart to Solidity's `int192` operator.
     *
     * Requirements:
     *
     * - input must fit into 192 bits
     *
     * _Available since v4.7._
     */
    function toInt192(int256 value) internal pure returns (int192 downcasted) {
        downcasted = int192(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 192 bits");
    }

    /**
     * @dev Returns the downcasted int184 from int256, reverting on
     * overflow (when the input is less than smallest int184 or
     * greater than largest int184).
     *
     * Counterpart to Solidity's `int184` operator.
     *
     * Requirements:
     *
     * - input must fit into 184 bits
     *
     * _Available since v4.7._
     */
    function toInt184(int256 value) internal pure returns (int184 downcasted) {
        downcasted = int184(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 184 bits");
    }

    /**
     * @dev Returns the downcasted int176 from int256, reverting on
     * overflow (when the input is less than smallest int176 or
     * greater than largest int176).
     *
     * Counterpart to Solidity's `int176` operator.
     *
     * Requirements:
     *
     * - input must fit into 176 bits
     *
     * _Available since v4.7._
     */
    function toInt176(int256 value) internal pure returns (int176 downcasted) {
        downcasted = int176(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 176 bits");
    }

    /**
     * @dev Returns the downcasted int168 from int256, reverting on
     * overflow (when the input is less than smallest int168 or
     * greater than largest int168).
     *
     * Counterpart to Solidity's `int168` operator.
     *
     * Requirements:
     *
     * - input must fit into 168 bits
     *
     * _Available since v4.7._
     */
    function toInt168(int256 value) internal pure returns (int168 downcasted) {
        downcasted = int168(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 168 bits");
    }

    /**
     * @dev Returns the downcasted int160 from int256, reverting on
     * overflow (when the input is less than smallest int160 or
     * greater than largest int160).
     *
     * Counterpart to Solidity's `int160` operator.
     *
     * Requirements:
     *
     * - input must fit into 160 bits
     *
     * _Available since v4.7._
     */
    function toInt160(int256 value) internal pure returns (int160 downcasted) {
        downcasted = int160(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 160 bits");
    }

    /**
     * @dev Returns the downcasted int152 from int256, reverting on
     * overflow (when the input is less than smallest int152 or
     * greater than largest int152).
     *
     * Counterpart to Solidity's `int152` operator.
     *
     * Requirements:
     *
     * - input must fit into 152 bits
     *
     * _Available since v4.7._
     */
    function toInt152(int256 value) internal pure returns (int152 downcasted) {
        downcasted = int152(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 152 bits");
    }

    /**
     * @dev Returns the downcasted int144 from int256, reverting on
     * overflow (when the input is less than smallest int144 or
     * greater than largest int144).
     *
     * Counterpart to Solidity's `int144` operator.
     *
     * Requirements:
     *
     * - input must fit into 144 bits
     *
     * _Available since v4.7._
     */
    function toInt144(int256 value) internal pure returns (int144 downcasted) {
        downcasted = int144(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 144 bits");
    }

    /**
     * @dev Returns the downcasted int136 from int256, reverting on
     * overflow (when the input is less than smallest int136 or
     * greater than largest int136).
     *
     * Counterpart to Solidity's `int136` operator.
     *
     * Requirements:
     *
     * - input must fit into 136 bits
     *
     * _Available since v4.7._
     */
    function toInt136(int256 value) internal pure returns (int136 downcasted) {
        downcasted = int136(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 136 bits");
    }

    /**
     * @dev Returns the downcasted int128 from int256, reverting on
     * overflow (when the input is less than smallest int128 or
     * greater than largest int128).
     *
     * Counterpart to Solidity's `int128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     *
     * _Available since v3.1._
     */
    function toInt128(int256 value) internal pure returns (int128 downcasted) {
        downcasted = int128(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 128 bits");
    }

    /**
     * @dev Returns the downcasted int120 from int256, reverting on
     * overflow (when the input is less than smallest int120 or
     * greater than largest int120).
     *
     * Counterpart to Solidity's `int120` operator.
     *
     * Requirements:
     *
     * - input must fit into 120 bits
     *
     * _Available since v4.7._
     */
    function toInt120(int256 value) internal pure returns (int120 downcasted) {
        downcasted = int120(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 120 bits");
    }

    /**
     * @dev Returns the downcasted int112 from int256, reverting on
     * overflow (when the input is less than smallest int112 or
     * greater than largest int112).
     *
     * Counterpart to Solidity's `int112` operator.
     *
     * Requirements:
     *
     * - input must fit into 112 bits
     *
     * _Available since v4.7._
     */
    function toInt112(int256 value) internal pure returns (int112 downcasted) {
        downcasted = int112(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 112 bits");
    }

    /**
     * @dev Returns the downcasted int104 from int256, reverting on
     * overflow (when the input is less than smallest int104 or
     * greater than largest int104).
     *
     * Counterpart to Solidity's `int104` operator.
     *
     * Requirements:
     *
     * - input must fit into 104 bits
     *
     * _Available since v4.7._
     */
    function toInt104(int256 value) internal pure returns (int104 downcasted) {
        downcasted = int104(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 104 bits");
    }

    /**
     * @dev Returns the downcasted int96 from int256, reverting on
     * overflow (when the input is less than smallest int96 or
     * greater than largest int96).
     *
     * Counterpart to Solidity's `int96` operator.
     *
     * Requirements:
     *
     * - input must fit into 96 bits
     *
     * _Available since v4.7._
     */
    function toInt96(int256 value) internal pure returns (int96 downcasted) {
        downcasted = int96(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 96 bits");
    }

    /**
     * @dev Returns the downcasted int88 from int256, reverting on
     * overflow (when the input is less than smallest int88 or
     * greater than largest int88).
     *
     * Counterpart to Solidity's `int88` operator.
     *
     * Requirements:
     *
     * - input must fit into 88 bits
     *
     * _Available since v4.7._
     */
    function toInt88(int256 value) internal pure returns (int88 downcasted) {
        downcasted = int88(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 88 bits");
    }

    /**
     * @dev Returns the downcasted int80 from int256, reverting on
     * overflow (when the input is less than smallest int80 or
     * greater than largest int80).
     *
     * Counterpart to Solidity's `int80` operator.
     *
     * Requirements:
     *
     * - input must fit into 80 bits
     *
     * _Available since v4.7._
     */
    function toInt80(int256 value) internal pure returns (int80 downcasted) {
        downcasted = int80(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 80 bits");
    }

    /**
     * @dev Returns the downcasted int72 from int256, reverting on
     * overflow (when the input is less than smallest int72 or
     * greater than largest int72).
     *
     * Counterpart to Solidity's `int72` operator.
     *
     * Requirements:
     *
     * - input must fit into 72 bits
     *
     * _Available since v4.7._
     */
    function toInt72(int256 value) internal pure returns (int72 downcasted) {
        downcasted = int72(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 72 bits");
    }

    /**
     * @dev Returns the downcasted int64 from int256, reverting on
     * overflow (when the input is less than smallest int64 or
     * greater than largest int64).
     *
     * Counterpart to Solidity's `int64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     *
     * _Available since v3.1._
     */
    function toInt64(int256 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 64 bits");
    }

    /**
     * @dev Returns the downcasted int56 from int256, reverting on
     * overflow (when the input is less than smallest int56 or
     * greater than largest int56).
     *
     * Counterpart to Solidity's `int56` operator.
     *
     * Requirements:
     *
     * - input must fit into 56 bits
     *
     * _Available since v4.7._
     */
    function toInt56(int256 value) internal pure returns (int56 downcasted) {
        downcasted = int56(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 56 bits");
    }

    /**
     * @dev Returns the downcasted int48 from int256, reverting on
     * overflow (when the input is less than smallest int48 or
     * greater than largest int48).
     *
     * Counterpart to Solidity's `int48` operator.
     *
     * Requirements:
     *
     * - input must fit into 48 bits
     *
     * _Available since v4.7._
     */
    function toInt48(int256 value) internal pure returns (int48 downcasted) {
        downcasted = int48(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 48 bits");
    }

    /**
     * @dev Returns the downcasted int40 from int256, reverting on
     * overflow (when the input is less than smallest int40 or
     * greater than largest int40).
     *
     * Counterpart to Solidity's `int40` operator.
     *
     * Requirements:
     *
     * - input must fit into 40 bits
     *
     * _Available since v4.7._
     */
    function toInt40(int256 value) internal pure returns (int40 downcasted) {
        downcasted = int40(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 40 bits");
    }

    /**
     * @dev Returns the downcasted int32 from int256, reverting on
     * overflow (when the input is less than smallest int32 or
     * greater than largest int32).
     *
     * Counterpart to Solidity's `int32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     *
     * _Available since v3.1._
     */
    function toInt32(int256 value) internal pure returns (int32 downcasted) {
        downcasted = int32(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 32 bits");
    }

    /**
     * @dev Returns the downcasted int24 from int256, reverting on
     * overflow (when the input is less than smallest int24 or
     * greater than largest int24).
     *
     * Counterpart to Solidity's `int24` operator.
     *
     * Requirements:
     *
     * - input must fit into 24 bits
     *
     * _Available since v4.7._
     */
    function toInt24(int256 value) internal pure returns (int24 downcasted) {
        downcasted = int24(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 24 bits");
    }

    /**
     * @dev Returns the downcasted int16 from int256, reverting on
     * overflow (when the input is less than smallest int16 or
     * greater than largest int16).
     *
     * Counterpart to Solidity's `int16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     *
     * _Available since v3.1._
     */
    function toInt16(int256 value) internal pure returns (int16 downcasted) {
        downcasted = int16(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 16 bits");
    }

    /**
     * @dev Returns the downcasted int8 from int256, reverting on
     * overflow (when the input is less than smallest int8 or
     * greater than largest int8).
     *
     * Counterpart to Solidity's `int8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits
     *
     * _Available since v3.1._
     */
    function toInt8(int256 value) internal pure returns (int8 downcasted) {
        downcasted = int8(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 8 bits");
    }

    /**
     * @dev Converts an unsigned uint256 into a signed int256.
     *
     * Requirements:
     *
     * - input must be less than or equal to maxInt256.
     *
     * _Available since v3.0._
     */
    function toInt256(uint256 value) internal pure returns (int256) {
        // Note: Unsafe cast below is okay because `type(int256).max` is guaranteed to be positive
        require(value <= uint256(type(int256).max), "SafeCast: value doesn't fit in an int256");
        return int256(value);
    }
}

// src/StateChangeHandlerLib.sol

enum StateUpdateType {
    STORE,
    CALL,
    LOG0,
    LOG1,
    LOG2,
    LOG3,
    LOG4
}

library StateChangeHandlerLib {
    /// @notice Decodes and executes a series of state updates
    /// @dev This function processes an array of state updates, executing them in sequence. Each update can be one of:
    ///      - STORE: Direct storage writes using assembly
    ///      - CALL: External contract calls with value transfer
    ///      - LOG0-LOG4: Event emission with 0-4 indexed topics
    /// @param types Array of StateUpdateType enums indicating the type of each state update operation
    /// @param args Array of ABI-encoded arguments corresponding to each operation type
    /// @dev types and args arrays must be equal length, with args[i] containing the encoded parameters for types[i]
    function _runStateUpdates(StateUpdateType[] memory types, bytes[] memory args) internal {
        require(types.length == args.length, InvalidArguments());
        for (uint256 i = 0; i < types.length; i++) {
            StateUpdateType stateUpdateType = types[i];
            bytes memory arg = args[i];

            if (stateUpdateType == StateUpdateType.STORE) {
                (bytes32 slot, bytes32 value) = abi.decode(arg, (bytes32, bytes32));
                assembly {
                    sstore(slot, value)
                }
            } else if (stateUpdateType == StateUpdateType.CALL) {
                (address target, uint256 value, bytes memory callargs) = abi.decode(arg, (address, uint256, bytes));
                bool success;
                // TOOD: might need better gas handling
                uint256 callgas = gasleft();
                assembly {
                    success := call(callgas, target, value, add(callargs, 0x20), mload(callargs), 0, 0)
                }
                // TODO: this section needs heavy testing
                if (!success) {
                    uint256 _returndatasize;
                    assembly {
                        _returndatasize := returndatasize()
                    }
                    bytes memory revertData = new bytes(_returndatasize);
                    assembly {
                        returndatacopy(add(revertData, 0x20), 0, _returndatasize)
                    }
                    revert RevertingContext(i, target, revertData, callargs);
                }
            } else if (stateUpdateType == StateUpdateType.LOG0) {
                // NOTE: For consistency I decode an abi encoding of bytes from bytes, but technically it's redundant
                (bytes memory data) = abi.decode(arg, (bytes));
                assembly {
                    log0(add(data, 0x20), mload(data))
                }
            } else if (stateUpdateType == StateUpdateType.LOG1) {
                (bytes memory data, bytes32 topic1) = abi.decode(arg, (bytes, bytes32));
                assembly {
                    log1(add(data, 0x20), mload(data), topic1)
                }
            } else if (stateUpdateType == StateUpdateType.LOG2) {
                (bytes memory data, bytes32 topic1, bytes32 topic2) = abi.decode(arg, (bytes, bytes32, bytes32));
                assembly {
                    log2(add(data, 0x20), mload(data), topic1, topic2)
                }
            } else if (stateUpdateType == StateUpdateType.LOG3) {
                (bytes memory data, bytes32 topic1, bytes32 topic2, bytes32 topic3) =
                    abi.decode(arg, (bytes, bytes32, bytes32, bytes32));
                assembly {
                    log3(add(data, 0x20), mload(data), topic1, topic2, topic3)
                }
            } else if (stateUpdateType == StateUpdateType.LOG4) {
                (bytes memory data, bytes32 topic1, bytes32 topic2, bytes32 topic3, bytes32 topic4) =
                    abi.decode(arg, (bytes, bytes32, bytes32, bytes32, bytes32));
                assembly {
                    log4(add(data, 0x20), mload(data), topic1, topic2, topic3, topic4)
                }
            }
        }
    }

    error InvalidArguments();
    error RevertingContext(uint256 index, address target, bytes revertData, bytes callargs);
}

// src/StateTracker.sol

/**
 * @title StateTracker
 * @notice A contract that tracks state transitions using a storage slot
 * @dev This contract provides functionality to track the number of state transitions
 *      that have occurred in a contract. It uses a precomputed storage slot to store
 *      the transition count.
 *
 *      The storage slot is computed as:
 *      keccak256("gasKiller.stateTracker") - 1
 *
 *      This contract is meant to be inherited by other contracts that need to track
 *      their state transitions for Gas Killer functionality.
 */
contract StateTracker {
    /**
     * @notice The precomputed storage slot for tracking state transitions
     * @dev This slot is computed as keccak256("gasKiller.stateTracker") - 1
     *      It is used to store the number of state transitions that have occurred
     */
    bytes32 internal constant STATE_TRACKER_STORAGE_LOCATION =
        0xdebfdfd5a50ad117c10898d68b5ccf0893c6b40d4f443f902e2e7646601bdeaf;

    /**
     * @notice Modifier that increments the state transition counter
     * @dev This modifier should be used on functions that modify the contract's state
     *      and need to be tracked for Gas Killer functionality.
     *
     *      The modifier:
     *      1. Loads the current transition count from storage
     *      2. Increments it by 1
     *      3. Stores the new count back to storage
     *      4. Executes the modified function
     */
    modifier trackState() {
        assembly {
            let count := sload(STATE_TRACKER_STORAGE_LOCATION)
            sstore(STATE_TRACKER_STORAGE_LOCATION, add(0x01, count))
        }
        _;
    }

    /**
     * @notice Returns the current number of state transitions
     * @return count The number of state transitions that have occurred
     * @dev This function reads the transition count directly from storage
     */
    function stateTransitionCount() public view returns (uint256 count) {
        assembly {
            count := sload(STATE_TRACKER_STORAGE_LOCATION)
        }
    }
}

// lib/eigenlayer-middleware/src/interfaces/IBLSApkRegistry.sol

interface IBLSApkRegistryErrors {
    /// @notice Thrown when a non-RegistryCoordinator owner address calls a restricted function.
    error OnlyRegistryCoordinatorOwner();
    /// @notice Thrown when a non-RegistryCoordinator address calls a restricted function.
    error OnlyRegistryCoordinator();
    /// @notice Thrown when attempting to initialize a quorum that already exists.
    error QuorumAlreadyExists();
    /// @notice Thrown when a quorum does not exist.
    error QuorumDoesNotExist();
    /// @notice Thrown when a BLS pubkey provided is zero pubkey
    error ZeroPubKey();
    /// @notice Thrown when an operator has already registered a BLS pubkey.
    error OperatorAlreadyRegistered();
    /// @notice Thrown when the operator is not registered.
    error OperatorNotRegistered();
    /// @notice Thrown when a BLS pubkey has already been registered for an operator.
    error BLSPubkeyAlreadyRegistered();
    /// @notice Thrown when either the G1 signature is wrong, or G1 and G2 private key do not match.
    error InvalidBLSSignatureOrPrivateKey();
    /// @notice Thrown when the quorum apk update block number is too recent.
    error BlockNumberTooRecent();
    /// @notice Thrown when blocknumber and index provided is not the latest apk update.
    error BlockNumberNotLatest();
    /// @notice Thrown when the block number is before the first update.
    error BlockNumberBeforeFirstUpdate();
    /// @notice Thrown when a G2 pubkey has already been set for an operator
    error G2PubkeyAlreadySet();
}

interface IBLSApkRegistryTypes {
    /// @notice Tracks the history of aggregate public key updates for a quorum.
    /// @dev Each update contains a hash of the aggregate public key and block numbers for timing.
    /// @param apkHash First 24 bytes of keccak256(apk_x0, apk_x1, apk_y0, apk_y1) representing the aggregate public key.
    /// @param updateBlockNumber Block number when this update occurred (inclusive).
    /// @param nextUpdateBlockNumber Block number when the next update occurred (exclusive), or 0 if this is the latest update.
    struct ApkUpdate {
        bytes24 apkHash;
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
    }

    /// @notice Parameters required when registering a new BLS public key.
    /// @dev Contains the registration signature and both G1/G2 public key components.
    /// @param pubkeyRegistrationSignature Registration message signed by operator's private key to prove ownership.
    /// @param pubkeyG1 The operator's public key in G1 group format.
    /// @param pubkeyG2 The operator's public key in G2 group format, must correspond to the same private key as pubkeyG1.
    struct PubkeyRegistrationParams {
        BN254.G1Point pubkeyRegistrationSignature;
        BN254.G1Point pubkeyG1;
        BN254.G2Point pubkeyG2;
    }
}

interface IBLSApkRegistryEvents is IBLSApkRegistryTypes {
    /*
     * @notice Emitted when `operator` registers their BLS public key pair (`pubkeyG1` and `pubkeyG2`).
     * @param operator The address of the operator registering the keys.
     * @param pubkeyG1 The operator's G1 public key.
     * @param pubkeyG2 The operator's G2 public key.
     */
    event NewPubkeyRegistration(
        address indexed operator, BN254.G1Point pubkeyG1, BN254.G2Point pubkeyG2
    );

    /*
     * @notice Emitted when `operator`'s pubkey is registered for `quorumNumbers`.
     * @param operator The address of the operator being registered.
     * @param operatorId The unique identifier for this operator (pubkey hash).
     * @param quorumNumbers The quorum numbers the operator is being registered for.
     */
    event OperatorAddedToQuorums(address operator, bytes32 operatorId, bytes quorumNumbers);

    /*
     * @notice Emitted when `operator`'s pubkey is deregistered from `quorumNumbers`.
     * @param operator The address of the operator being deregistered.
     * @param operatorId The unique identifier for this operator (pubkey hash).
     * @param quorumNumbers The quorum numbers the operator is being deregistered from.
     */
    event OperatorRemovedFromQuorums(address operator, bytes32 operatorId, bytes quorumNumbers);

    /// @notice Emitted when a G2 public key is registered for an operator
    event NewG2PubkeyRegistration(address indexed operator, BN254.G2Point pubkeyG2);
}

interface IBLSApkRegistry is IBLSApkRegistryErrors, IBLSApkRegistryEvents {
    /* STORAGE */

    /*
     * @notice Returns the address of the registry coordinator contract.
     * @return The address of the registry coordinator.
     * @dev This value is immutable and set during contract construction.
     */
    function registryCoordinator() external view returns (address);

    /*
     * @notice Maps `operator` to their BLS public key hash (`operatorId`).
     * @param operator The address of the operator.
     * @return operatorId The hash of the operator's BLS public key.
     */
    function operatorToPubkeyHash(
        address operator
    ) external view returns (bytes32 operatorId);

    /*
     * @notice Maps `pubkeyHash` to their corresponding `operator` address.
     * @param pubkeyHash The hash of a BLS public key.
     * @return operator The address of the operator who registered this public key.
     */
    function pubkeyHashToOperator(
        bytes32 pubkeyHash
    ) external view returns (address operator);

    /*
     * @notice Maps `operator` to their BLS public key in G1.
     * @dev Returns a non-encoded BN254.G1Point.
     * @param operator The address of the operator.
     * @return The operator's BLS public key in G1.
     */
    function operatorToPubkey(
        address operator
    ) external view returns (uint256, uint256);

    /*
     * @notice Maps `operator` to their BLS public key in G2.
     * @param operator The address of the operator.
     * @return The operator's BLS public key in G2.
     */
    function getOperatorPubkeyG2(
        address operator
    ) external view returns (BN254.G2Point memory);

    /*
     * @notice Stores the history of aggregate public key updates for `quorumNumber` at `index`.
     * @dev Returns a non-encoded IBLSApkRegistryTypes.ApkUpdate.
     * @param quorumNumber The identifier of the quorum.
     * @param index The index in the history array.
     * @return The APK update entry at the specified index for the given quorum.
     * @dev Each entry contains the APK hash, update block number, and next update block number.
     */
    function apkHistory(
        uint8 quorumNumber,
        uint256 index
    ) external view returns (bytes24, uint32, uint32);

    /*
     * @notice Maps `quorumNumber` to their current aggregate public key.
     * @dev Returns a non-encoded BN254.G1Point.
     * @param quorumNumber The identifier of the quorum.
     * @return The current APK as a G1 point.
     */
    function currentApk(
        uint8 quorumNumber
    ) external view returns (uint256, uint256);

    /* ACTIONS */

    /*
     * @notice Registers `operator`'s pubkey for `quorumNumbers`.
     * @param operator The address of the operator to register.
     * @param quorumNumbers The quorum numbers to register for, where each byte is an 8-bit integer.
     * @dev Access restricted to the RegistryCoordinator.
     * @dev Preconditions (assumed, not validated):
     *      1. `quorumNumbers` has no duplicates
     *      2. `quorumNumbers.length` != 0
     *      3. `quorumNumbers` is ordered ascending
     *      4. The operator is not already registered
     */
    function registerOperator(address operator, bytes calldata quorumNumbers) external;

    /*
     * @notice Deregisters `operator`'s pubkey from `quorumNumbers`.
     * @param operator The address of the operator to deregister.
     * @param quorumNumbers The quorum numbers to deregister from, where each byte is an 8-bit integer.
     * @dev Access restricted to the RegistryCoordinator.
     * @dev Preconditions (assumed, not validated):
     *      1. `quorumNumbers` has no duplicates
     *      2. `quorumNumbers.length` != 0
     *      3. `quorumNumbers` is ordered ascending
     *      4. The operator is not already deregistered
     *      5. `quorumNumbers` is a subset of the operator's registered quorums
     */
    function deregisterOperator(address operator, bytes calldata quorumNumbers) external;

    /*
     * @notice Initializes `quorumNumber` by pushing its first APK update.
     * @param quorumNumber The number of the new quorum.
     */
    function initializeQuorum(
        uint8 quorumNumber
    ) external;

    /*
     * @notice Registers `operator` as the owner of a BLS public key using `params` and `pubkeyRegistrationMessageHash`.
     * @param operator The operator for whom the key is being registered.
     * @param params Contains the G1 & G2 public keys and ownership proof signature.
     * @param pubkeyRegistrationMessageHash The hash that must be signed to prove key ownership.
     * @return operatorId The unique identifier (pubkey hash) for this operator.
     * @dev Called by the RegistryCoordinator.
     */
    function registerBLSPublicKey(
        address operator,
        IBLSApkRegistryTypes.PubkeyRegistrationParams calldata params,
        BN254.G1Point calldata pubkeyRegistrationMessageHash
    ) external returns (bytes32 operatorId);

    /* VIEW */

    /*
     * @notice Returns the pubkey and pubkey hash of `operator`.
     * @param operator The address of the operator.
     * @return The operator's G1 public key and its hash.
     * @dev Reverts if the operator has not registered a valid pubkey.
     */
    function getRegisteredPubkey(
        address operator
    ) external view returns (BN254.G1Point memory, bytes32);

    /*
     * @notice Returns the APK indices at `blockNumber` for `quorumNumbers`.
     * @param quorumNumbers The quorum numbers to get indices for.
     * @param blockNumber The block number to query at.
     * @return Array of indices corresponding to each quorum number.
     */
    function getApkIndicesAtBlockNumber(
        bytes calldata quorumNumbers,
        uint256 blockNumber
    ) external view returns (uint32[] memory);

    /*
     * @notice Returns the current aggregate public key for `quorumNumber`.
     * @param quorumNumber The quorum to query.
     * @return The current APK as a G1 point.
     */
    function getApk(
        uint8 quorumNumber
    ) external view returns (BN254.G1Point memory);

    /*
     * @notice Returns an APK update entry for `quorumNumber` at `index`.
     * @param quorumNumber The quorum to query.
     * @param index The index in the APK history.
     * @return The APK update entry.
     */
    function getApkUpdateAtIndex(
        uint8 quorumNumber,
        uint256 index
    ) external view returns (IBLSApkRegistryTypes.ApkUpdate memory);

    /*
     * @notice Gets the 24-byte hash of `quorumNumber`'s APK at `blockNumber` and `index`.
     * @param quorumNumber The quorum to query.
     * @param blockNumber The block number to get the APK hash for.
     * @param index The index in the APK history.
     * @return The 24-byte APK hash.
     * @dev Called by checkSignatures in BLSSignatureChecker.sol.
     */
    function getApkHashAtBlockNumberAndIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        uint256 index
    ) external view returns (bytes24);

    /*
     * @notice Returns the number of APK updates for `quorumNumber`.
     * @param quorumNumber The quorum to query.
     * @return The length of the APK history.
     */
    function getApkHistoryLength(
        uint8 quorumNumber
    ) external view returns (uint32);

    /*
     * @notice Maps `operator` to their corresponding public key hash.
     * @param operator The address of the operator.
     * @return operatorId The hash of the operator's BLS public key.
     * @dev Returns bytes32(0) if the operator hasn't registered a key.
     */
    function getOperatorId(
        address operator
    ) external view returns (bytes32 operatorId);

    /*
     * @notice Maps `pubkeyHash` to their corresponding operator address.
     * @param pubkeyHash The hash of a BLS public key.
     * @return operator The address of the operator who registered this public key.
     * @dev Returns address(0) if the public key hash hasn't been registered.
     */
    function getOperatorFromPubkeyHash(
        bytes32 pubkeyHash
    ) external view returns (address operator);

    /**
     * @notice Gets an operator's ID if it exists, or registers a new BLS public key and returns the new ID
     * @param operator The address of the operator
     * @param params The parameters for registering a new BLS public key
     * @param pubkeyRegistrationMessageHash The hash of the message to sign for registration
     * @return operatorId The operator's ID (pubkey hash)
     */
    function getOrRegisterOperatorId(
        address operator,
        PubkeyRegistrationParams calldata params,
        BN254.G1Point calldata pubkeyRegistrationMessageHash
    ) external returns (bytes32 operatorId);
}

// lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol

interface ISignatureUtilsMixinErrors {
    /// @notice Thrown when a signature is invalid.
    error InvalidSignature();
    /// @notice Thrown when a signature has expired.
    error SignatureExpired();
}

interface ISignatureUtilsMixinTypes {
    /// @notice Struct that bundles together a signature and an expiration time for the signature.
    /// @dev Used primarily for stack management.
    struct SignatureWithExpiry {
        // the signature itself, formatted as a single bytes object
        bytes signature;
        // the expiration timestamp (UTC) of the signature
        uint256 expiry;
    }

    /// @notice Struct that bundles together a signature, a salt for uniqueness, and an expiration time for the signature.
    /// @dev Used primarily for stack management.
    struct SignatureWithSaltAndExpiry {
        // the signature itself, formatted as a single bytes object
        bytes signature;
        // the salt used to generate the signature
        bytes32 salt;
        // the expiration timestamp (UTC) of the signature
        uint256 expiry;
    }
}

/**
 * @title The interface for common signature utilities.
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 */
interface ISignatureUtilsMixin is ISignatureUtilsMixinErrors, ISignatureUtilsMixinTypes, ISemVerMixin {
    /// @notice Computes the EIP-712 domain separator used for signature validation.
    /// @dev The domain separator is computed according to EIP-712 specification, using:
    ///      - The hardcoded name "EigenLayer"
    ///      - The contract's version string
    ///      - The current chain ID
    ///      - This contract's address
    /// @return The 32-byte domain separator hash used in EIP-712 structured data signing.
    /// @dev See https://eips.ethereum.org/EIPS/eip-712#definition-of-domainseparator.
    function domainSeparator() external view returns (bytes32);
}

// lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/libraries/SlashingLib.sol

/// @dev All scaling factors have `1e18` as an initial/default value. This value is represented
/// by the constant `WAD`, which is used to preserve precision with uint256 math.
///
/// When applying scaling factors, they are typically multiplied/divided by `WAD`, allowing this
/// constant to act as a "1" in mathematical formulae.
uint64 constant WAD = 1e18;

/*
 * There are 2 types of shares:
 *      1. deposit shares
 *          - These can be converted to an amount of tokens given a strategy
 *              - by calling `sharesToUnderlying` on the strategy address (they're already tokens 
 *              in the case of EigenPods)
 *          - These live in the storage of the EigenPodManager and individual StrategyManager strategies 
 *      2. withdrawable shares
 *          - For a staker, this is the amount of shares that they can withdraw
 *          - For an operator, the shares delegated to them are equal to the sum of their stakers'
 *            withdrawable shares
 *
 * Along with a slashing factor, the DepositScalingFactor is used to convert between the two share types.
 */
struct DepositScalingFactor {
    uint256 _scalingFactor;
}

using SlashingLib for DepositScalingFactor global;

library SlashingLib {
    using Math_0 for uint256;
    using SlashingLib for uint256;
    using SafeCastUpgradeable for uint256;

    // WAD MATH

    function mulWad(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.mulDiv(y, WAD);
    }

    function divWad(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.mulDiv(WAD, y);
    }

    /**
     * @notice Used explicitly for calculating slashed magnitude, we want to ensure even in the
     * situation where an operator is slashed several times and precision has been lost over time,
     * an incoming slashing request isn't rounded down to 0 and an operator is able to avoid slashing penalties.
     */
    function mulWadRoundUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.mulDiv(y, WAD, Math_0.Rounding.Up);
    }

    // GETTERS

    function scalingFactor(
        DepositScalingFactor memory dsf
    ) internal pure returns (uint256) {
        return dsf._scalingFactor == 0 ? WAD : dsf._scalingFactor;
    }

    function scaleForQueueWithdrawal(
        DepositScalingFactor memory dsf,
        uint256 depositSharesToWithdraw
    ) internal pure returns (uint256) {
        return depositSharesToWithdraw.mulWad(dsf.scalingFactor());
    }

    function scaleForCompleteWithdrawal(uint256 scaledShares, uint256 slashingFactor) internal pure returns (uint256) {
        return scaledShares.mulWad(slashingFactor);
    }

    /**
     * @notice Scales shares according to the difference in an operator's magnitude before and
     * after being slashed. This is used to calculate the number of slashable shares in the
     * withdrawal queue.
     * NOTE: max magnitude is guaranteed to only ever decrease.
     */
    function scaleForBurning(
        uint256 scaledShares,
        uint64 prevMaxMagnitude,
        uint64 newMaxMagnitude
    ) internal pure returns (uint256) {
        return scaledShares.mulWad(prevMaxMagnitude - newMaxMagnitude);
    }

    function update(
        DepositScalingFactor storage dsf,
        uint256 prevDepositShares,
        uint256 addedShares,
        uint256 slashingFactor
    ) internal {
        if (prevDepositShares == 0) {
            // If this is the staker's first deposit or they are delegating to an operator,
            // the slashing factor is inverted and applied to the existing DSF. This has the
            // effect of "forgiving" prior slashing for any subsequent deposits.
            dsf._scalingFactor = dsf.scalingFactor().divWad(slashingFactor);
            return;
        }

        /**
         * Base Equations:
         * (1) newShares = currentShares + addedShares
         * (2) newDepositShares = prevDepositShares + addedShares
         * (3) newShares = newDepositShares * newDepositScalingFactor * slashingFactor
         *
         * Plugging (1) into (3):
         * (4) newDepositShares * newDepositScalingFactor * slashingFactor = currentShares + addedShares
         *
         * Solving for newDepositScalingFactor
         * (5) newDepositScalingFactor = (currentShares + addedShares) / (newDepositShares * slashingFactor)
         *
         * Plugging in (2) into (5):
         * (7) newDepositScalingFactor = (currentShares + addedShares) / ((prevDepositShares + addedShares) * slashingFactor)
         * Note that magnitudes must be divided by WAD for precision. Thus,
         *
         * (8) newDepositScalingFactor = WAD * (currentShares + addedShares) / ((prevDepositShares + addedShares) * slashingFactor / WAD)
         * (9) newDepositScalingFactor = (currentShares + addedShares) * WAD / (prevDepositShares + addedShares) * WAD / slashingFactor
         */

        // Step 1: Calculate Numerator
        uint256 currentShares = dsf.calcWithdrawable(prevDepositShares, slashingFactor);

        // Step 2: Compute currentShares + addedShares
        uint256 newShares = currentShares + addedShares;

        // Step 3: Calculate newDepositScalingFactor
        /// forgefmt: disable-next-item
        uint256 newDepositScalingFactor = newShares
            .divWad(prevDepositShares + addedShares)
            .divWad(slashingFactor);

        dsf._scalingFactor = newDepositScalingFactor;
    }

    /// @dev Reset the staker's DSF for a strategy by setting it to 0. This is the same
    /// as setting it to WAD (see the `scalingFactor` getter above).
    ///
    /// A DSF is reset when a staker reduces their deposit shares to 0, either by queueing
    /// a withdrawal, or undelegating from their operator. This ensures that subsequent
    /// delegations/deposits do not use a stale DSF (e.g. from a prior operator).
    function reset(
        DepositScalingFactor storage dsf
    ) internal {
        dsf._scalingFactor = 0;
    }

    // CONVERSION

    function calcWithdrawable(
        DepositScalingFactor memory dsf,
        uint256 depositShares,
        uint256 slashingFactor
    ) internal pure returns (uint256) {
        /// forgefmt: disable-next-item
        return depositShares
            .mulWad(dsf.scalingFactor())
            .mulWad(slashingFactor);
    }

    function calcDepositShares(
        DepositScalingFactor memory dsf,
        uint256 withdrawableShares,
        uint256 slashingFactor
    ) internal pure returns (uint256) {
        /// forgefmt: disable-next-item
        return withdrawableShares
            .divWad(dsf.scalingFactor())
            .divWad(slashingFactor);
    }

    function calcSlashedAmount(
        uint256 operatorShares,
        uint256 prevMaxMagnitude,
        uint256 newMaxMagnitude
    ) internal pure returns (uint256) {
        // round up mulDiv so we don't overslash
        return operatorShares - operatorShares.mulDiv(newMaxMagnitude, prevMaxMagnitude, Math_0.Rounding.Up);
    }
}

// lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol

interface IStrategyErrors {
    /// @dev Thrown when called by an account that is not strategy manager.
    error OnlyStrategyManager();
    /// @dev Thrown when new shares value is zero.
    error NewSharesZero();
    /// @dev Thrown when total shares exceeds max.
    error TotalSharesExceedsMax();
    /// @dev Thrown when amount shares is greater than total shares.
    error WithdrawalAmountExceedsTotalDeposits();
    /// @dev Thrown when attempting an action with a token that is not accepted.
    error OnlyUnderlyingToken();

    /// StrategyBaseWithTVLLimits

    /// @dev Thrown when `maxPerDeposit` exceeds max.
    error MaxPerDepositExceedsMax();
    /// @dev Thrown when balance exceeds max total deposits.
    error BalanceExceedsMaxTotalDeposits();
}

interface IStrategyEvents {
    /**
     * @notice Used to emit an event for the exchange rate between 1 share and underlying token in a strategy contract
     * @param rate is the exchange rate in wad 18 decimals
     * @dev Tokens that do not have 18 decimals must have offchain services scale the exchange rate by the proper magnitude
     */
    event ExchangeRateEmitted(uint256 rate);

    /**
     * Used to emit the underlying token and its decimals on strategy creation
     * @notice token
     * @param token is the ERC20 token of the strategy
     * @param decimals are the decimals of the ERC20 token in the strategy
     */
    event StrategyTokenSet(IERC20_0 token, uint8 decimals);
}

/**
 * @title Minimal interface for an `Strategy` contract.
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 * @notice Custom `Strategy` implementations may expand extensively on this interface.
 */
interface IStrategy is IStrategyErrors, IStrategyEvents, ISemVerMixin {
    /**
     * @notice Used to deposit tokens into this Strategy
     * @param token is the ERC20 token being deposited
     * @param amount is the amount of token being deposited
     * @dev This function is only callable by the strategyManager contract. It is invoked inside of the strategyManager's
     * `depositIntoStrategy` function, and individual share balances are recorded in the strategyManager as well.
     * @return newShares is the number of new shares issued at the current exchange ratio.
     */
    function deposit(IERC20_0 token, uint256 amount) external returns (uint256);

    /**
     * @notice Used to withdraw tokens from this Strategy, to the `recipient`'s address
     * @param recipient is the address to receive the withdrawn funds
     * @param token is the ERC20 token being transferred out
     * @param amountShares is the amount of shares being withdrawn
     * @dev This function is only callable by the strategyManager contract. It is invoked inside of the strategyManager's
     * other functions, and individual share balances are recorded in the strategyManager as well.
     */
    function withdraw(address recipient, IERC20_0 token, uint256 amountShares) external;

    /**
     * @notice Used to convert a number of shares to the equivalent amount of underlying tokens for this strategy.
     * For a staker using this function and trying to calculate the amount of underlying tokens they have in total they
     * should input into `amountShares` their withdrawable shares read from the `DelegationManager` contract.
     * @notice In contrast to `sharesToUnderlyingView`, this function **may** make state modifications
     * @param amountShares is the amount of shares to calculate its conversion into the underlying token
     * @return The amount of underlying tokens corresponding to the input `amountShares`
     * @dev Implementation for these functions in particular may vary significantly for different strategies
     */
    function sharesToUnderlying(
        uint256 amountShares
    ) external returns (uint256);

    /**
     * @notice Used to convert an amount of underlying tokens to the equivalent amount of shares in this strategy.
     * @notice In contrast to `underlyingToSharesView`, this function **may** make state modifications
     * @param amountUnderlying is the amount of `underlyingToken` to calculate its conversion into strategy shares
     * @return The amount of shares corresponding to the input `amountUnderlying`.  This is used as deposit shares
     * in the `StrategyManager` contract.
     * @dev Implementation for these functions in particular may vary significantly for different strategies
     */
    function underlyingToShares(
        uint256 amountUnderlying
    ) external returns (uint256);

    /**
     * @notice convenience function for fetching the current underlying value of all of the `user`'s shares in
     * this strategy. In contrast to `userUnderlyingView`, this function **may** make state modifications
     */
    function userUnderlying(
        address user
    ) external returns (uint256);

    /**
     * @notice convenience function for fetching the current total shares of `user` in this strategy, by
     * querying the `strategyManager` contract
     */
    function shares(
        address user
    ) external view returns (uint256);

    /**
     * @notice Used to convert a number of shares to the equivalent amount of underlying tokens for this strategy.
     * For a staker using this function and trying to calculate the amount of underlying tokens they have in total they
     * should input into `amountShares` their withdrawable shares read from the `DelegationManager` contract.
     * @notice In contrast to `sharesToUnderlying`, this function guarantees no state modifications
     * @param amountShares is the amount of shares to calculate its conversion into the underlying token
     * @return The amount of underlying tokens corresponding to the input `amountShares`
     * @dev Implementation for these functions in particular may vary significantly for different strategies
     */
    function sharesToUnderlyingView(
        uint256 amountShares
    ) external view returns (uint256);

    /**
     * @notice Used to convert an amount of underlying tokens to the equivalent amount of shares in this strategy.
     * @notice In contrast to `underlyingToShares`, this function guarantees no state modifications
     * @param amountUnderlying is the amount of `underlyingToken` to calculate its conversion into strategy shares
     * @return The amount of shares corresponding to the input `amountUnderlying`. This is used as deposit shares
     * in the `StrategyManager` contract.
     * @dev Implementation for these functions in particular may vary significantly for different strategies
     */
    function underlyingToSharesView(
        uint256 amountUnderlying
    ) external view returns (uint256);

    /**
     * @notice convenience function for fetching the current underlying value of all of the `user`'s shares in
     * this strategy. In contrast to `userUnderlying`, this function guarantees no state modifications
     */
    function userUnderlyingView(
        address user
    ) external view returns (uint256);

    /// @notice The underlying token for shares in this Strategy
    function underlyingToken() external view returns (IERC20_0);

    /// @notice The total number of extant shares in this Strategy
    function totalShares() external view returns (uint256);

    /// @notice Returns either a brief string explaining the strategy's goal & purpose, or a link to metadata that explains in more detail.
    function explanation() external view returns (string memory);
}

// lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol

interface IDelegationManagerErrors {
    /// @dev Thrown when caller is neither the StrategyManager or EigenPodManager contract.
    error OnlyStrategyManagerOrEigenPodManager();
    /// @dev Thrown when msg.sender is not the EigenPodManager
    error OnlyEigenPodManager();
    /// @dev Throw when msg.sender is not the AllocationManager
    error OnlyAllocationManager();

    /// Delegation Status

    /// @dev Thrown when an operator attempts to undelegate.
    error OperatorsCannotUndelegate();
    /// @dev Thrown when an account is actively delegated.
    error ActivelyDelegated();
    /// @dev Thrown when an account is not actively delegated.
    error NotActivelyDelegated();
    /// @dev Thrown when `operator` is not a registered operator.
    error OperatorNotRegistered();

    /// Invalid Inputs

    /// @dev Thrown when attempting to execute an action that was not queued.
    error WithdrawalNotQueued();
    /// @dev Thrown when caller cannot undelegate on behalf of a staker.
    error CallerCannotUndelegate();
    /// @dev Thrown when two array parameters have mismatching lengths.
    error InputArrayLengthMismatch();
    /// @dev Thrown when input arrays length is zero.
    error InputArrayLengthZero();

    /// Slashing

    /// @dev Thrown when an operator has been fully slashed(maxMagnitude is 0) for a strategy.
    /// or if the staker has had been natively slashed to the point of their beaconChainScalingFactor equalling 0.
    error FullySlashed();

    /// Signatures

    /// @dev Thrown when attempting to spend a spent eip-712 salt.
    error SaltSpent();

    /// Withdrawal Processing

    /// @dev Thrown when attempting to withdraw before delay has elapsed.
    error WithdrawalDelayNotElapsed();
    /// @dev Thrown when withdrawer is not the current caller.
    error WithdrawerNotCaller();
}

interface IDelegationManagerTypes {
    // @notice Struct used for storing information about a single operator who has registered with EigenLayer
    struct OperatorDetails {
        /// @notice DEPRECATED -- this field is no longer used, payments are handled in RewardsCoordinator.sol
        address __deprecated_earningsReceiver;
        /**
         * @notice Address to verify signatures when a staker wishes to delegate to the operator, as well as controlling "forced undelegations".
         * @dev Signature verification follows these rules:
         * 1) If this address is left as address(0), then any staker will be free to delegate to the operator, i.e. no signature verification will be performed.
         * 2) If this address is an EOA (i.e. it has no code), then we follow standard ECDSA signature verification for delegations to the operator.
         * 3) If this address is a contract (i.e. it has code) then we forward a call to the contract and verify that it returns the correct EIP-1271 "magic value".
         */
        address delegationApprover;
        /// @notice DEPRECATED -- this field is no longer used. An analogous field is the `allocationDelay` stored in the AllocationManager
        uint32 __deprecated_stakerOptOutWindowBlocks;
    }

    /**
     * @notice Abstract struct used in calculating an EIP712 signature for an operator's delegationApprover to approve that a specific staker delegate to the operator.
     * @dev Used in computing the `DELEGATION_APPROVAL_TYPEHASH` and as a reference in the computation of the approverDigestHash in the `_delegate` function.
     */
    struct DelegationApproval {
        // the staker who is delegating
        address staker;
        // the operator being delegated to
        address operator;
        // the operator's provided salt
        bytes32 salt;
        // the expiration timestamp (UTC) of the signature
        uint256 expiry;
    }

    /**
     * @dev A struct representing an existing queued withdrawal. After the withdrawal delay has elapsed, this withdrawal can be completed via `completeQueuedWithdrawal`.
     * A `Withdrawal` is created by the `DelegationManager` when `queueWithdrawals` is called. The `withdrawalRoots` hashes returned by `queueWithdrawals` can be used
     * to fetch the corresponding `Withdrawal` from storage (via `getQueuedWithdrawal`).
     *
     * @param staker The address that queued the withdrawal
     * @param delegatedTo The address that the staker was delegated to at the time the withdrawal was queued. Used to determine if additional slashing occurred before
     * this withdrawal became completable.
     * @param withdrawer The address that will call the contract to complete the withdrawal. Note that this will always equal `staker`; alternate withdrawers are not
     * supported at this time.
     * @param nonce The staker's `cumulativeWithdrawalsQueued` at time of queuing. Used to ensure withdrawals have unique hashes.
     * @param startBlock The block number when the withdrawal was queued.
     * @param strategies The strategies requested for withdrawal when the withdrawal was queued
     * @param scaledShares The staker's deposit shares requested for withdrawal, scaled by the staker's `depositScalingFactor`. Upon completion, these will be
     * scaled by the appropriate slashing factor as of the withdrawal's completable block. The result is what is actually withdrawable.
     */
    struct Withdrawal {
        address staker;
        address delegatedTo;
        address withdrawer;
        uint256 nonce;
        uint32 startBlock;
        IStrategy[] strategies;
        uint256[] scaledShares;
    }

    /**
     * @param strategies The strategies to withdraw from
     * @param depositShares For each strategy, the number of deposit shares to withdraw. Deposit shares can
     * be queried via `getDepositedShares`.
     * NOTE: The number of shares ultimately received when a withdrawal is completed may be lower depositShares
     * if the staker or their delegated operator has experienced slashing.
     * @param __deprecated_withdrawer This field is ignored. The only party that may complete a withdrawal
     * is the staker that originally queued it. Alternate withdrawers are not supported.
     */
    struct QueuedWithdrawalParams {
        IStrategy[] strategies;
        uint256[] depositShares;
        address __deprecated_withdrawer;
    }
}

interface IDelegationManagerEvents is IDelegationManagerTypes {
    // @notice Emitted when a new operator registers in EigenLayer and provides their delegation approver.
    event OperatorRegistered(address indexed operator, address delegationApprover);

    /// @notice Emitted when an operator updates their delegation approver
    event DelegationApproverUpdated(address indexed operator, address newDelegationApprover);

    /**
     * @notice Emitted when @param operator indicates that they are updating their MetadataURI string
     * @dev Note that these strings are *never stored in storage* and are instead purely emitted in events for off-chain indexing
     */
    event OperatorMetadataURIUpdated(address indexed operator, string metadataURI);

    /// @notice Emitted whenever an operator's shares are increased for a given strategy. Note that shares is the delta in the operator's shares.
    event OperatorSharesIncreased(address indexed operator, address staker, IStrategy strategy, uint256 shares);

    /// @notice Emitted whenever an operator's shares are decreased for a given strategy. Note that shares is the delta in the operator's shares.
    event OperatorSharesDecreased(address indexed operator, address staker, IStrategy strategy, uint256 shares);

    /// @notice Emitted when @param staker delegates to @param operator.
    event StakerDelegated(address indexed staker, address indexed operator);

    /// @notice Emitted when @param staker undelegates from @param operator.
    event StakerUndelegated(address indexed staker, address indexed operator);

    /// @notice Emitted when @param staker is undelegated via a call not originating from the staker themself
    event StakerForceUndelegated(address indexed staker, address indexed operator);

    /// @notice Emitted when a staker's depositScalingFactor is updated
    event DepositScalingFactorUpdated(address staker, IStrategy strategy, uint256 newDepositScalingFactor);

    /**
     * @notice Emitted when a new withdrawal is queued.
     * @param withdrawalRoot Is the hash of the `withdrawal`.
     * @param withdrawal Is the withdrawal itself.
     * @param sharesToWithdraw Is an array of the expected shares that were queued for withdrawal corresponding to the strategies in the `withdrawal`.
     */
    event SlashingWithdrawalQueued(bytes32 withdrawalRoot, Withdrawal withdrawal, uint256[] sharesToWithdraw);

    /// @notice Emitted when a queued withdrawal is completed
    event SlashingWithdrawalCompleted(bytes32 withdrawalRoot);

    /// @notice Emitted whenever an operator's shares are slashed for a given strategy
    event OperatorSharesSlashed(address indexed operator, IStrategy strategy, uint256 totalSlashedShares);
}

/**
 * @title DelegationManager
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 * @notice  This is the contract for delegation in EigenLayer. The main functionalities of this contract are
 * - enabling anyone to register as an operator in EigenLayer
 * - allowing operators to specify parameters related to stakers who delegate to them
 * - enabling any staker to delegate its stake to the operator of its choice (a given staker can only delegate to a single operator at a time)
 * - enabling a staker to undelegate its assets from the operator it is delegated to (performed as part of the withdrawal process, initiated through the StrategyManager)
 */
interface IDelegationManager is ISignatureUtilsMixin, IDelegationManagerErrors, IDelegationManagerEvents {
    /**
     * @dev Initializes the initial owner and paused status.
     */
    function initialize(address initialOwner, uint256 initialPausedStatus) external;

    /**
     * @notice Registers the caller as an operator in EigenLayer.
     * @param initDelegationApprover is an address that, if set, must provide a signature when stakers delegate
     * to an operator.
     * @param allocationDelay The delay before allocations take effect.
     * @param metadataURI is a URI for the operator's metadata, i.e. a link providing more details on the operator.
     *
     * @dev Once an operator is registered, they cannot 'deregister' as an operator, and they will forever be considered "delegated to themself".
     * @dev This function will revert if the caller is already delegated to an operator.
     * @dev Note that the `metadataURI` is *never stored * and is only emitted in the `OperatorMetadataURIUpdated` event
     */
    function registerAsOperator(
        address initDelegationApprover,
        uint32 allocationDelay,
        string calldata metadataURI
    ) external;

    /**
     * @notice Updates an operator's stored `delegationApprover`.
     * @param operator is the operator to update the delegationApprover for
     * @param newDelegationApprover is the new delegationApprover for the operator
     *
     * @dev The caller must have previously registered as an operator in EigenLayer.
     */
    function modifyOperatorDetails(address operator, address newDelegationApprover) external;

    /**
     * @notice Called by an operator to emit an `OperatorMetadataURIUpdated` event indicating the information has updated.
     * @param operator The operator to update metadata for
     * @param metadataURI The URI for metadata associated with an operator
     * @dev Note that the `metadataURI` is *never stored * and is only emitted in the `OperatorMetadataURIUpdated` event
     */
    function updateOperatorMetadataURI(address operator, string calldata metadataURI) external;

    /**
     * @notice Caller delegates their stake to an operator.
     * @param operator The account (`msg.sender`) is delegating its assets to for use in serving applications built on EigenLayer.
     * @param approverSignatureAndExpiry (optional) Verifies the operator approves of this delegation
     * @param approverSalt (optional) A unique single use value tied to an individual signature.
     * @dev The signature/salt are used ONLY if the operator has configured a delegationApprover.
     * If they have not, these params can be left empty.
     */
    function delegateTo(
        address operator,
        SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external;

    /**
     * @notice Undelegates the staker from their operator and queues a withdrawal for all of their shares
     * @param staker The account to be undelegated
     * @return withdrawalRoots The roots of the newly queued withdrawals, if a withdrawal was queued. Returns
     * an empty array if none was queued.
     *
     * @dev Reverts if the `staker` is also an operator, since operators are not allowed to undelegate from themselves.
     * @dev Reverts if the caller is not the staker, nor the operator who the staker is delegated to, nor the operator's specified "delegationApprover"
     * @dev Reverts if the `staker` is not delegated to an operator
     */
    function undelegate(
        address staker
    ) external returns (bytes32[] memory withdrawalRoots);

    /**
     * @notice Undelegates the staker from their current operator, and redelegates to `newOperator`
     * Queues a withdrawal for all of the staker's withdrawable shares. These shares will only be
     * delegated to `newOperator` AFTER the withdrawal is completed.
     * @dev This method acts like a call to `undelegate`, then `delegateTo`
     * @param newOperator the new operator that will be delegated all assets
     * @dev NOTE: the following 2 params are ONLY checked if `newOperator` has a `delegationApprover`.
     * If not, they can be left empty.
     * @param newOperatorApproverSig A signature from the operator's `delegationApprover`
     * @param approverSalt A unique single use value tied to the approver's signature
     */
    function redelegate(
        address newOperator,
        SignatureWithExpiry memory newOperatorApproverSig,
        bytes32 approverSalt
    ) external returns (bytes32[] memory withdrawalRoots);

    /**
     * @notice Allows a staker to queue a withdrawal of their deposit shares. The withdrawal can be
     * completed after the MIN_WITHDRAWAL_DELAY_BLOCKS via either of the completeQueuedWithdrawal methods.
     *
     * While in the queue, these shares are removed from the staker's balance, as well as from their operator's
     * delegated share balance (if applicable). Note that while in the queue, deposit shares are still subject
     * to slashing. If any slashing has occurred, the shares received may be less than the queued deposit shares.
     *
     * @dev To view all the staker's strategies/deposit shares that can be queued for withdrawal, see `getDepositedShares`
     * @dev To view the current conversion between a staker's deposit shares and withdrawable shares, see `getWithdrawableShares`
     */
    function queueWithdrawals(
        QueuedWithdrawalParams[] calldata params
    ) external returns (bytes32[] memory);

    /**
     * @notice Used to complete a queued withdrawal
     * @param withdrawal The withdrawal to complete
     * @param tokens Array in which the i-th entry specifies the `token` input to the 'withdraw' function of the i-th Strategy in the `withdrawal.strategies` array.
     * @param tokens For each `withdrawal.strategies`, the underlying token of the strategy
     * NOTE: if `receiveAsTokens` is false, the `tokens` array is unused and can be filled with default values. However, `tokens.length` MUST still be equal to `withdrawal.strategies.length`.
     * NOTE: For the `beaconChainETHStrategy`, the corresponding `tokens` value is ignored (can be 0).
     * @param receiveAsTokens If true, withdrawn shares will be converted to tokens and sent to the caller. If false, the caller receives shares that can be delegated to an operator.
     * NOTE: if the caller receives shares and is currently delegated to an operator, the received shares are
     * automatically delegated to the caller's current operator.
     */
    function completeQueuedWithdrawal(
        Withdrawal calldata withdrawal,
        IERC20_0[] calldata tokens,
        bool receiveAsTokens
    ) external;

    /**
     * @notice Used to complete multiple queued withdrawals
     * @param withdrawals Array of Withdrawals to complete. See `completeQueuedWithdrawal` for the usage of a single Withdrawal.
     * @param tokens Array of tokens for each Withdrawal. See `completeQueuedWithdrawal` for the usage of a single array.
     * @param receiveAsTokens Whether or not to complete each withdrawal as tokens. See `completeQueuedWithdrawal` for the usage of a single boolean.
     * @dev See `completeQueuedWithdrawal` for relevant dev tags
     */
    function completeQueuedWithdrawals(
        Withdrawal[] calldata withdrawals,
        IERC20_0[][] calldata tokens,
        bool[] calldata receiveAsTokens
    ) external;

    /**
     * @notice Called by a share manager when a staker's deposit share balance in a strategy increases.
     * This method delegates any new shares to an operator (if applicable), and updates the staker's
     * deposit scaling factor regardless.
     * @param staker The address whose deposit shares have increased
     * @param strategy The strategy in which shares have been deposited
     * @param prevDepositShares The number of deposit shares the staker had in the strategy prior to the increase
     * @param addedShares The number of deposit shares added by the staker
     *
     * @dev Note that if the either the staker's current operator has been slashed 100% for `strategy`, OR the
     * staker has been slashed 100% on the beacon chain such that the calculated slashing factor is 0, this
     * method WILL REVERT.
     */
    function increaseDelegatedShares(
        address staker,
        IStrategy strategy,
        uint256 prevDepositShares,
        uint256 addedShares
    ) external;

    /**
     * @notice If the staker is delegated, decreases its operator's shares in response to
     * a decrease in balance in the beaconChainETHStrategy
     * @param staker the staker whose operator's balance will be decreased
     * @param curDepositShares the current deposit shares held by the staker
     * @param beaconChainSlashingFactorDecrease the amount that the staker's beaconChainSlashingFactor has decreased by
     * @dev Note: `beaconChainSlashingFactorDecrease` are assumed to ALWAYS be < 1 WAD.
     * These invariants are maintained in the EigenPodManager.
     */
    function decreaseDelegatedShares(
        address staker,
        uint256 curDepositShares,
        uint64 beaconChainSlashingFactorDecrease
    ) external;

    /**
     * @notice Decreases the operators shares in storage after a slash and increases the burnable shares by calling
     * into either the StrategyManager or EigenPodManager (if the strategy is beaconChainETH).
     * @param operator The operator to decrease shares for
     * @param strategy The strategy to decrease shares for
     * @param prevMaxMagnitude the previous maxMagnitude of the operator
     * @param newMaxMagnitude the new maxMagnitude of the operator
     * @dev Callable only by the AllocationManager
     * @dev Note: Assumes `prevMaxMagnitude <= newMaxMagnitude`. This invariant is maintained in
     * the AllocationManager.
     */
    function slashOperatorShares(
        address operator,
        IStrategy strategy,
        uint64 prevMaxMagnitude,
        uint64 newMaxMagnitude
    ) external;

    /**
     *
     *                         VIEW FUNCTIONS
     *
     */

    /**
     * @notice returns the address of the operator that `staker` is delegated to.
     * @notice Mapping: staker => operator whom the staker is currently delegated to.
     * @dev Note that returning address(0) indicates that the staker is not actively delegated to any operator.
     */
    function delegatedTo(
        address staker
    ) external view returns (address);

    /**
     * @notice Mapping: delegationApprover => 32-byte salt => whether or not the salt has already been used by the delegationApprover.
     * @dev Salts are used in the `delegateTo` function. Note that this function only processes the delegationApprover's
     * signature + the provided salt if the operator being delegated to has specified a nonzero address as their `delegationApprover`.
     */
    function delegationApproverSaltIsSpent(address _delegationApprover, bytes32 salt) external view returns (bool);

    /// @notice Mapping: staker => cumulative number of queued withdrawals they have ever initiated.
    /// @dev This only increments (doesn't decrement), and is used to help ensure that otherwise identical withdrawals have unique hashes.
    function cumulativeWithdrawalsQueued(
        address staker
    ) external view returns (uint256);

    /**
     * @notice Returns 'true' if `staker` *is* actively delegated, and 'false' otherwise.
     */
    function isDelegated(
        address staker
    ) external view returns (bool);

    /**
     * @notice Returns true is an operator has previously registered for delegation.
     */
    function isOperator(
        address operator
    ) external view returns (bool);

    /**
     * @notice Returns the delegationApprover account for an operator
     */
    function delegationApprover(
        address operator
    ) external view returns (address);

    /**
     * @notice Returns the shares that an operator has delegated to them in a set of strategies
     * @param operator the operator to get shares for
     * @param strategies the strategies to get shares for
     */
    function getOperatorShares(
        address operator,
        IStrategy[] memory strategies
    ) external view returns (uint256[] memory);

    /**
     * @notice Returns the shares that a set of operators have delegated to them in a set of strategies
     * @param operators the operators to get shares for
     * @param strategies the strategies to get shares for
     */
    function getOperatorsShares(
        address[] memory operators,
        IStrategy[] memory strategies
    ) external view returns (uint256[][] memory);

    /**
     * @notice Returns amount of withdrawable shares from an operator for a strategy that is still in the queue
     * and therefore slashable. Note that the *actual* slashable amount could be less than this value as this doesn't account
     * for amounts that have already been slashed. This assumes that none of the shares have been slashed.
     * @param operator the operator to get shares for
     * @param strategy the strategy to get shares for
     * @return the amount of shares that are slashable in the withdrawal queue for an operator and a strategy
     */
    function getSlashableSharesInQueue(address operator, IStrategy strategy) external view returns (uint256);

    /**
     * @notice Given a staker and a set of strategies, return the shares they can queue for withdrawal and the
     * corresponding depositShares.
     * This value depends on which operator the staker is delegated to.
     * The shares amount returned is the actual amount of Strategy shares the staker would receive (subject
     * to each strategy's underlying shares to token ratio).
     */
    function getWithdrawableShares(
        address staker,
        IStrategy[] memory strategies
    ) external view returns (uint256[] memory withdrawableShares, uint256[] memory depositShares);

    /**
     * @notice Returns the number of shares in storage for a staker and all their strategies
     */
    function getDepositedShares(
        address staker
    ) external view returns (IStrategy[] memory, uint256[] memory);

    /**
     * @notice Returns the scaling factor applied to a staker's deposits for a given strategy
     */
    function depositScalingFactor(address staker, IStrategy strategy) external view returns (uint256);

    /**
     * @notice Returns the Withdrawal associated with a `withdrawalRoot`.
     * @param withdrawalRoot The hash identifying the queued withdrawal.
     * @return withdrawal The withdrawal details.
     */
    function queuedWithdrawals(
        bytes32 withdrawalRoot
    ) external view returns (Withdrawal memory withdrawal);

    /**
     * @notice Returns the Withdrawal and corresponding shares associated with a `withdrawalRoot`
     * @param withdrawalRoot The hash identifying the queued withdrawal
     * @return withdrawal The withdrawal details
     * @return shares Array of shares corresponding to each strategy in the withdrawal
     * @dev The shares are what a user would receive from completing a queued withdrawal, assuming all slashings are applied
     * @dev Withdrawals queued before the slashing release cannot be queried with this method
     */
    function getQueuedWithdrawal(
        bytes32 withdrawalRoot
    ) external view returns (Withdrawal memory withdrawal, uint256[] memory shares);

    /**
     * @notice Returns all queued withdrawals and their corresponding shares for a staker.
     * @param staker The address of the staker to query withdrawals for.
     * @return withdrawals Array of Withdrawal structs containing details about each queued withdrawal.
     * @return shares 2D array of shares, where each inner array corresponds to the strategies in the withdrawal.
     * @dev The shares are what a user would receive from completing a queued withdrawal, assuming all slashings are applied.
     */
    function getQueuedWithdrawals(
        address staker
    ) external view returns (Withdrawal[] memory withdrawals, uint256[][] memory shares);

    /// @notice Returns a list of queued withdrawal roots for the `staker`.
    /// NOTE that this only returns withdrawals queued AFTER the slashing release.
    function getQueuedWithdrawalRoots(
        address staker
    ) external view returns (bytes32[] memory);

    /**
     * @notice Converts shares for a set of strategies to deposit shares, likely in order to input into `queueWithdrawals`.
     * This function will revert from a division by 0 error if any of the staker's strategies have a slashing factor of 0.
     * @param staker the staker to convert shares for
     * @param strategies the strategies to convert shares for
     * @param withdrawableShares the shares to convert
     * @return the deposit shares
     * @dev will be a few wei off due to rounding errors
     */
    function convertToDepositShares(
        address staker,
        IStrategy[] memory strategies,
        uint256[] memory withdrawableShares
    ) external view returns (uint256[] memory);

    /// @notice Returns the keccak256 hash of `withdrawal`.
    function calculateWithdrawalRoot(
        Withdrawal memory withdrawal
    ) external pure returns (bytes32);

    /**
     * @notice Calculates the digest hash to be signed by the operator's delegationApprove and used in the `delegateTo` function.
     * @param staker The account delegating their stake
     * @param operator The account receiving delegated stake
     * @param _delegationApprover the operator's `delegationApprover` who will be signing the delegationHash (in general)
     * @param approverSalt A unique and single use value associated with the approver signature.
     * @param expiry Time after which the approver's signature becomes invalid
     */
    function calculateDelegationApprovalDigestHash(
        address staker,
        address operator,
        address _delegationApprover,
        bytes32 approverSalt,
        uint256 expiry
    ) external view returns (bytes32);

    /// @notice return address of the beaconChainETHStrategy
    function beaconChainETHStrategy() external view returns (IStrategy);

    /**
     * @notice Returns the minimum withdrawal delay in blocks to pass for withdrawals queued to be completable.
     * Also applies to legacy withdrawals so any withdrawals not completed prior to the slashing upgrade will be subject
     * to this longer delay.
     * @dev Backwards-compatible interface to return the internal `MIN_WITHDRAWAL_DELAY_BLOCKS` value
     * @dev Previous value in storage was deprecated. See `__deprecated_minWithdrawalDelayBlocks`
     */
    function minWithdrawalDelayBlocks() external view returns (uint32);

    /// @notice The EIP-712 typehash for the DelegationApproval struct used by the contract
    function DELEGATION_APPROVAL_TYPEHASH() external view returns (bytes32);
}

// lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol

interface IAllocationManagerErrors {
    /// Input Validation

    /// @dev Thrown when `wadToSlash` is zero or greater than 1e18
    error InvalidWadToSlash();
    /// @dev Thrown when two array parameters have mismatching lengths.
    error InputArrayLengthMismatch();
    /// @dev Thrown when the AVSRegistrar is not correctly configured to prevent an AVSRegistrar contract
    /// from being used with the wrong AVS
    error InvalidAVSRegistrar();

    /// Caller

    /// @dev Thrown when caller is not authorized to call a function.
    error InvalidCaller();

    /// Operator Status

    /// @dev Thrown when an invalid operator is provided.
    error InvalidOperator();
    /// @dev Thrown when an invalid avs whose metadata is not registered is provided.
    error NonexistentAVSMetadata();
    /// @dev Thrown when an operator's allocation delay has yet to be set.
    error UninitializedAllocationDelay();
    /// @dev Thrown when attempting to slash an operator when they are not slashable.
    error OperatorNotSlashable();
    /// @dev Thrown when trying to add an operator to a set they are already a member of
    error AlreadyMemberOfSet();
    /// @dev Thrown when trying to slash/remove an operator from a set they are not a member of
    error NotMemberOfSet();

    /// Operator Set Status

    /// @dev Thrown when an invalid operator set is provided.
    error InvalidOperatorSet();
    /// @dev Thrown when provided `strategies` are not in ascending order.
    error StrategiesMustBeInAscendingOrder();
    /// @dev Thrown when trying to add a strategy to an operator set that already contains it.
    error StrategyAlreadyInOperatorSet();
    /// @dev Thrown when a strategy is referenced that does not belong to an operator set.
    error StrategyNotInOperatorSet();

    /// Modifying Allocations

    /// @dev Thrown when an operator attempts to set their allocation for an operatorSet to the same value
    error SameMagnitude();
    /// @dev Thrown when an allocation is attempted for a given operator when they have pending allocations or deallocations.
    error ModificationAlreadyPending();
    /// @dev Thrown when an allocation is attempted that exceeds a given operators total allocatable magnitude.
    error InsufficientMagnitude();
}

interface IAllocationManagerTypes {
    /**
     * @notice Defines allocation information from a strategy to an operator set, for an operator
     * @param currentMagnitude the current magnitude allocated from the strategy to the operator set
     * @param pendingDiff a pending change in magnitude, if it exists (0 otherwise)
     * @param effectBlock the block at which the pending magnitude diff will take effect
     */
    struct Allocation {
        uint64 currentMagnitude;
        int128 pendingDiff;
        uint32 effectBlock;
    }

    /**
     * @notice Struct containing allocation delay metadata for a given operator.
     * @param delay Current allocation delay
     * @param isSet Whether the operator has initially set an allocation delay. Note that this could be false but the
     * block.number >= effectBlock in which we consider their delay to be configured and active.
     * @param pendingDelay The delay that will take effect after `effectBlock`
     * @param effectBlock The block number after which a pending delay will take effect
     */
    struct AllocationDelayInfo {
        uint32 delay;
        bool isSet;
        uint32 pendingDelay;
        uint32 effectBlock;
    }

    /**
     * @notice Contains registration details for an operator pertaining to an operator set
     * @param registered Whether the operator is currently registered for the operator set
     * @param slashableUntil If the operator is not registered, they are still slashable until
     * this block is reached.
     */
    struct RegistrationStatus {
        bool registered;
        uint32 slashableUntil;
    }

    /**
     * @notice Contains allocation info for a specific strategy
     * @param maxMagnitude the maximum magnitude that can be allocated between all operator sets
     * @param encumberedMagnitude the currently-allocated magnitude for the strategy
     */
    struct StrategyInfo {
        uint64 maxMagnitude;
        uint64 encumberedMagnitude;
    }

    /**
     * @notice Struct containing parameters to slashing
     * @param operator the address to slash
     * @param operatorSetId the ID of the operatorSet the operator is being slashed on behalf of
     * @param strategies the set of strategies to slash
     * @param wadsToSlash the parts in 1e18 to slash, this will be proportional to the operator's
     * slashable stake allocation for the operatorSet
     * @param description the description of the slashing provided by the AVS for legibility
     */
    struct SlashingParams {
        address operator;
        uint32 operatorSetId;
        IStrategy[] strategies;
        uint256[] wadsToSlash;
        string description;
    }

    /**
     * @notice struct used to modify the allocation of slashable magnitude to an operator set
     * @param operatorSet the operator set to modify the allocation for
     * @param strategies the strategies to modify allocations for
     * @param newMagnitudes the new magnitude to allocate for each strategy to this operator set
     */
    struct AllocateParams {
        OperatorSet operatorSet;
        IStrategy[] strategies;
        uint64[] newMagnitudes;
    }

    /**
     * @notice Parameters used to register for an AVS's operator sets
     * @param avs the AVS being registered for
     * @param operatorSetIds the operator sets within the AVS to register for
     * @param data extra data to be passed to the AVS to complete registration
     */
    struct RegisterParams {
        address avs;
        uint32[] operatorSetIds;
        bytes data;
    }

    /**
     * @notice Parameters used to deregister from an AVS's operator sets
     * @param operator the operator being deregistered
     * @param avs the avs being deregistered from
     * @param operatorSetIds the operator sets within the AVS being deregistered from
     */
    struct DeregisterParams {
        address operator;
        address avs;
        uint32[] operatorSetIds;
    }

    /**
     * @notice Parameters used by an AVS to create new operator sets
     * @param operatorSetId the id of the operator set to create
     * @param strategies the strategies to add as slashable to the operator set
     */
    struct CreateSetParams {
        uint32 operatorSetId;
        IStrategy[] strategies;
    }
}

interface IAllocationManagerEvents is IAllocationManagerTypes {
    /// @notice Emitted when operator updates their allocation delay.
    event AllocationDelaySet(address operator, uint32 delay, uint32 effectBlock);

    /// @notice Emitted when an operator's magnitude is updated for a given operatorSet and strategy
    event AllocationUpdated(
        address operator, OperatorSet operatorSet, IStrategy strategy, uint64 magnitude, uint32 effectBlock
    );

    /// @notice Emitted when operator's encumbered magnitude is updated for a given strategy
    event EncumberedMagnitudeUpdated(address operator, IStrategy strategy, uint64 encumberedMagnitude);

    /// @notice Emitted when an operator's max magnitude is updated for a given strategy
    event MaxMagnitudeUpdated(address operator, IStrategy strategy, uint64 maxMagnitude);

    /// @notice Emitted when an operator is slashed by an operator set for a strategy
    /// `wadSlashed` is the proportion of the operator's total delegated stake that was slashed
    event OperatorSlashed(
        address operator, OperatorSet operatorSet, IStrategy[] strategies, uint256[] wadSlashed, string description
    );

    /// @notice Emitted when an AVS configures the address that will handle registration/deregistration
    event AVSRegistrarSet(address avs, IAVSRegistrar registrar);

    /// @notice Emitted when an AVS updates their metadata URI (Uniform Resource Identifier).
    /// @dev The URI is never stored; it is simply emitted through an event for off-chain indexing.
    event AVSMetadataURIUpdated(address indexed avs, string metadataURI);

    /// @notice Emitted when an operator set is created by an AVS.
    event OperatorSetCreated(OperatorSet operatorSet);

    /// @notice Emitted when an operator is added to an operator set.
    event OperatorAddedToOperatorSet(address indexed operator, OperatorSet operatorSet);

    /// @notice Emitted when an operator is removed from an operator set.
    event OperatorRemovedFromOperatorSet(address indexed operator, OperatorSet operatorSet);

    /// @notice Emitted when a strategy is added to an operator set.
    event StrategyAddedToOperatorSet(OperatorSet operatorSet, IStrategy strategy);

    /// @notice Emitted when a strategy is removed from an operator set.
    event StrategyRemovedFromOperatorSet(OperatorSet operatorSet, IStrategy strategy);
}

interface IAllocationManager is IAllocationManagerErrors, IAllocationManagerEvents, ISemVerMixin {
    /**
     * @dev Initializes the initial owner and paused status.
     */
    function initialize(address initialOwner, uint256 initialPausedStatus) external;

    /**
     * @notice Called by an AVS to slash an operator in a given operator set. The operator must be registered
     * and have slashable stake allocated to the operator set.
     *
     * @param avs The AVS address initiating the slash.
     * @param params The slashing parameters, containing:
     *  - operator: The operator to slash.
     *  - operatorSetId: The ID of the operator set the operator is being slashed from.
     *  - strategies: Array of strategies to slash allocations from (must be in ascending order).
     *  - wadsToSlash: Array of proportions to slash from each strategy (must be between 0 and 1e18).
     *  - description: Description of why the operator was slashed.
     *
     * @dev For each strategy:
     *      1. Reduces the operator's current allocation magnitude by wadToSlash proportion.
     *      2. Reduces the strategy's max and encumbered magnitudes proportionally.
     *      3. If there is a pending deallocation, reduces it proportionally.
     *      4. Updates the operator's shares in the DelegationManager.
     *
     * @dev Small slashing amounts may not result in actual token burns due to
     *      rounding, which will result in small amounts of tokens locked in the contract
     *      rather than fully burning through the burn mechanism.
     */
    function slashOperator(address avs, SlashingParams calldata params) external;

    /**
     * @notice Modifies the proportions of slashable stake allocated to an operator set from a list of strategies
     * Note that deallocations remain slashable for DEALLOCATION_DELAY blocks therefore when they are cleared they may
     * free up less allocatable magnitude than initially deallocated.
     * @param operator the operator to modify allocations for
     * @param params array of magnitude adjustments for one or more operator sets
     * @dev Updates encumberedMagnitude for the updated strategies
     */
    function modifyAllocations(address operator, AllocateParams[] calldata params) external;

    /**
     * @notice This function takes a list of strategies and for each strategy, removes from the deallocationQueue
     * all clearable deallocations up to max `numToClear` number of deallocations, updating the encumberedMagnitude
     * of the operator as needed.
     *
     * @param operator address to clear deallocations for
     * @param strategies a list of strategies to clear deallocations for
     * @param numToClear a list of number of pending deallocations to clear for each strategy
     *
     * @dev can be called permissionlessly by anyone
     */
    function clearDeallocationQueue(
        address operator,
        IStrategy[] calldata strategies,
        uint16[] calldata numToClear
    ) external;

    /**
     * @notice Allows an operator to register for one or more operator sets for an AVS. If the operator
     * has any stake allocated to these operator sets, it immediately becomes slashable.
     * @dev After registering within the ALM, this method calls the AVS Registrar's `IAVSRegistrar.
     * registerOperator` method to complete registration. This call MUST succeed in order for
     * registration to be successful.
     */
    function registerForOperatorSets(address operator, RegisterParams calldata params) external;

    /**
     * @notice Allows an operator or AVS to deregister the operator from one or more of the AVS's operator sets.
     * If the operator has any slashable stake allocated to the AVS, it remains slashable until the
     * DEALLOCATION_DELAY has passed.
     * @dev After deregistering within the ALM, this method calls the AVS Registrar's `IAVSRegistrar.
     * deregisterOperator` method to complete deregistration. This call MUST succeed in order for
     * deregistration to be successful.
     */
    function deregisterFromOperatorSets(
        DeregisterParams calldata params
    ) external;

    /**
     * @notice Called by the delegation manager OR an operator to set an operator's allocation delay.
     * This is set when the operator first registers, and is the number of blocks between an operator
     * allocating magnitude to an operator set, and the magnitude becoming slashable.
     * @param operator The operator to set the delay on behalf of.
     * @param delay the allocation delay in blocks
     */
    function setAllocationDelay(address operator, uint32 delay) external;

    /**
     * @notice Called by an AVS to configure the address that is called when an operator registers
     * or is deregistered from the AVS's operator sets. If not set (or set to 0), defaults
     * to the AVS's address.
     * @param registrar the new registrar address
     */
    function setAVSRegistrar(address avs, IAVSRegistrar registrar) external;

    /**
     *  @notice Called by an AVS to emit an `AVSMetadataURIUpdated` event indicating the information has updated.
     *
     *  @param metadataURI The URI for metadata associated with an AVS.
     *
     *  @dev Note that the `metadataURI` is *never stored* and is only emitted in the `AVSMetadataURIUpdated` event.
     */
    function updateAVSMetadataURI(address avs, string calldata metadataURI) external;

    /**
     * @notice Allows an AVS to create new operator sets, defining strategies that the operator set uses
     */
    function createOperatorSets(address avs, CreateSetParams[] calldata params) external;

    /**
     * @notice Allows an AVS to add strategies to an operator set
     * @dev Strategies MUST NOT already exist in the operator set
     * @param avs the avs to set strategies for
     * @param operatorSetId the operator set to add strategies to
     * @param strategies the strategies to add
     */
    function addStrategiesToOperatorSet(address avs, uint32 operatorSetId, IStrategy[] calldata strategies) external;

    /**
     * @notice Allows an AVS to remove strategies from an operator set
     * @dev Strategies MUST already exist in the operator set
     * @param avs the avs to remove strategies for
     * @param operatorSetId the operator set to remove strategies from
     * @param strategies the strategies to remove
     */
    function removeStrategiesFromOperatorSet(
        address avs,
        uint32 operatorSetId,
        IStrategy[] calldata strategies
    ) external;

    /**
     *
     *                         VIEW FUNCTIONS
     *
     */

    /**
     * @notice Returns the number of operator sets for the AVS
     * @param avs the AVS to query
     */
    function getOperatorSetCount(
        address avs
    ) external view returns (uint256);

    /**
     * @notice Returns the list of operator sets the operator has current or pending allocations/deallocations in
     * @param operator the operator to query
     * @return the list of operator sets the operator has current or pending allocations/deallocations in
     */
    function getAllocatedSets(
        address operator
    ) external view returns (OperatorSet[] memory);

    /**
     * @notice Returns the list of strategies an operator has current or pending allocations/deallocations from
     * given a specific operator set.
     * @param operator the operator to query
     * @param operatorSet the operator set to query
     * @return the list of strategies
     */
    function getAllocatedStrategies(
        address operator,
        OperatorSet memory operatorSet
    ) external view returns (IStrategy[] memory);

    /**
     * @notice Returns the current/pending stake allocation an operator has from a strategy to an operator set
     * @param operator the operator to query
     * @param operatorSet the operator set to query
     * @param strategy the strategy to query
     * @return the current/pending stake allocation
     */
    function getAllocation(
        address operator,
        OperatorSet memory operatorSet,
        IStrategy strategy
    ) external view returns (Allocation memory);

    /**
     * @notice Returns the current/pending stake allocations for multiple operators from a strategy to an operator set
     * @param operators the operators to query
     * @param operatorSet the operator set to query
     * @param strategy the strategy to query
     * @return each operator's allocation
     */
    function getAllocations(
        address[] memory operators,
        OperatorSet memory operatorSet,
        IStrategy strategy
    ) external view returns (Allocation[] memory);

    /**
     * @notice Given a strategy, returns a list of operator sets and corresponding stake allocations.
     * @dev Note that this returns a list of ALL operator sets the operator has allocations in. This means
     * some of the returned allocations may be zero.
     * @param operator the operator to query
     * @param strategy the strategy to query
     * @return the list of all operator sets the operator has allocations for
     * @return the corresponding list of allocations from the specific `strategy`
     */
    function getStrategyAllocations(
        address operator,
        IStrategy strategy
    ) external view returns (OperatorSet[] memory, Allocation[] memory);

    /**
     * @notice For a strategy, get the amount of magnitude that is allocated across one or more operator sets
     * @param operator the operator to query
     * @param strategy the strategy to get allocatable magnitude for
     * @return currently allocated magnitude
     */
    function getEncumberedMagnitude(address operator, IStrategy strategy) external view returns (uint64);

    /**
     * @notice For a strategy, get the amount of magnitude not currently allocated to any operator set
     * @param operator the operator to query
     * @param strategy the strategy to get allocatable magnitude for
     * @return magnitude available to be allocated to an operator set
     */
    function getAllocatableMagnitude(address operator, IStrategy strategy) external view returns (uint64);

    /**
     * @notice Returns the maximum magnitude an operator can allocate for the given strategy
     * @dev The max magnitude of an operator starts at WAD (1e18), and is decreased anytime
     * the operator is slashed. This value acts as a cap on the max magnitude of the operator.
     * @param operator the operator to query
     * @param strategy the strategy to get the max magnitude for
     * @return the max magnitude for the strategy
     */
    function getMaxMagnitude(address operator, IStrategy strategy) external view returns (uint64);

    /**
     * @notice Returns the maximum magnitude an operator can allocate for the given strategies
     * @dev The max magnitude of an operator starts at WAD (1e18), and is decreased anytime
     * the operator is slashed. This value acts as a cap on the max magnitude of the operator.
     * @param operator the operator to query
     * @param strategies the strategies to get the max magnitudes for
     * @return the max magnitudes for each strategy
     */
    function getMaxMagnitudes(
        address operator,
        IStrategy[] calldata strategies
    ) external view returns (uint64[] memory);

    /**
     * @notice Returns the maximum magnitudes each operator can allocate for the given strategy
     * @dev The max magnitude of an operator starts at WAD (1e18), and is decreased anytime
     * the operator is slashed. This value acts as a cap on the max magnitude of the operator.
     * @param operators the operators to query
     * @param strategy the strategy to get the max magnitudes for
     * @return the max magnitudes for each operator
     */
    function getMaxMagnitudes(
        address[] calldata operators,
        IStrategy strategy
    ) external view returns (uint64[] memory);

    /**
     * @notice Returns the maximum magnitude an operator can allocate for the given strategies
     * at a given block number
     * @dev The max magnitude of an operator starts at WAD (1e18), and is decreased anytime
     * the operator is slashed. This value acts as a cap on the max magnitude of the operator.
     * @param operator the operator to query
     * @param strategies the strategies to get the max magnitudes for
     * @param blockNumber the blockNumber at which to check the max magnitudes
     * @return the max magnitudes for each strategy
     */
    function getMaxMagnitudesAtBlock(
        address operator,
        IStrategy[] calldata strategies,
        uint32 blockNumber
    ) external view returns (uint64[] memory);

    /**
     * @notice Returns the time in blocks between an operator allocating slashable magnitude
     * and the magnitude becoming slashable. If the delay has not been set, `isSet` will be false.
     * @dev The operator must have a configured delay before allocating magnitude
     * @param operator The operator to query
     * @return isSet Whether the operator has configured a delay
     * @return delay The time in blocks between allocating magnitude and magnitude becoming slashable
     */
    function getAllocationDelay(
        address operator
    ) external view returns (bool isSet, uint32 delay);

    /**
     * @notice Returns a list of all operator sets the operator is registered for
     * @param operator The operator address to query.
     */
    function getRegisteredSets(
        address operator
    ) external view returns (OperatorSet[] memory operatorSets);

    /**
     * @notice Returns whether the operator is registered for the operator set
     * @param operator The operator to query
     * @param operatorSet The operator set to query
     */
    function isMemberOfOperatorSet(address operator, OperatorSet memory operatorSet) external view returns (bool);

    /**
     * @notice Returns whether the operator set exists
     */
    function isOperatorSet(
        OperatorSet memory operatorSet
    ) external view returns (bool);

    /**
     * @notice Returns all the operators registered to an operator set
     * @param operatorSet The operatorSet to query.
     */
    function getMembers(
        OperatorSet memory operatorSet
    ) external view returns (address[] memory operators);

    /**
     * @notice Returns the number of operators registered to an operatorSet.
     * @param operatorSet The operatorSet to get the member count for
     */
    function getMemberCount(
        OperatorSet memory operatorSet
    ) external view returns (uint256);

    /**
     * @notice Returns the address that handles registration/deregistration for the AVS
     * If not set, defaults to the input address (`avs`)
     */
    function getAVSRegistrar(
        address avs
    ) external view returns (IAVSRegistrar);

    /**
     * @notice Returns an array of strategies in the operatorSet.
     * @param operatorSet The operatorSet to query.
     */
    function getStrategiesInOperatorSet(
        OperatorSet memory operatorSet
    ) external view returns (IStrategy[] memory strategies);

    /**
     * @notice Returns the minimum amount of stake that will be slashable as of some future block,
     * according to each operator's allocation from each strategy to the operator set. Note that this function
     * will return 0 for the slashable stake if the operator is not slashable at the time of the call.
     * @dev This method queries actual delegated stakes in the DelegationManager and applies
     * each operator's allocation to the stake to produce the slashable stake each allocation
     * represents. This method does not consider slashable stake in the withdrawal queue even though there could be
     * slashable stake in the queue.
     * @dev This minimum takes into account `futureBlock`, and will omit any pending magnitude
     * diffs that will not be in effect as of `futureBlock`. NOTE that in order to get the true
     * minimum slashable stake as of some future block, `futureBlock` MUST be greater than block.number
     * @dev NOTE that `futureBlock` should be fewer than `DEALLOCATION_DELAY` blocks in the future,
     * or the values returned from this method may not be accurate due to deallocations.
     * @param operatorSet the operator set to query
     * @param operators the list of operators whose slashable stakes will be returned
     * @param strategies the strategies that each slashable stake corresponds to
     * @param futureBlock the block at which to get allocation information. Should be a future block.
     */
    function getMinimumSlashableStake(
        OperatorSet memory operatorSet,
        address[] memory operators,
        IStrategy[] memory strategies,
        uint32 futureBlock
    ) external view returns (uint256[][] memory slashableStake);

    /**
     * @notice Returns the current allocated stake, irrespective of the operator's slashable status for the operatorSet.
     * @param operatorSet the operator set to query
     * @param operators the operators to query
     * @param strategies the strategies to query
     */
    function getAllocatedStake(
        OperatorSet memory operatorSet,
        address[] memory operators,
        IStrategy[] memory strategies
    ) external view returns (uint256[][] memory slashableStake);

    /**
     * @notice Returns whether an operator is slashable by an operator set.
     * This returns true if the operator is registered or their slashableUntil block has not passed.
     * This is because even when operators are deregistered, they still remain slashable for a period of time.
     * @param operator the operator to check slashability for
     * @param operatorSet the operator set to check slashability for
     */
    function isOperatorSlashable(address operator, OperatorSet memory operatorSet) external view returns (bool);
}

// lib/eigenlayer-middleware/src/interfaces/IStakeRegistry.sol

/// @notice Interface containing all error definitions for the StakeRegistry contract.
interface IStakeRegistryErrors {
    /// @dev Thrown when the caller is not the registry coordinator
    error OnlySlashingRegistryCoordinator();
    /// @dev Thrown when the caller is not the owner of the registry coordinator
    error OnlySlashingRegistryCoordinatorOwner();
    /// @dev Thrown when the stake is below the minimum required for a quorum
    error BelowMinimumStakeRequirement();
    /// @notice Thrown when attempting to create a quorum that already exists.
    error QuorumAlreadyExists();
    /// @notice Thrown when attempting to interact with a quorum that does not exist.
    error QuorumDoesNotExist();
    /// @notice Thrown when two array parameters have mismatching lengths.
    error InputArrayLengthMismatch();
    /// @notice Thrown when an input array has zero length.
    error InputArrayLengthZero();
    /// @notice Thrown when a duplicate strategy is provided in an input array.
    error InputDuplicateStrategy();
    /// @notice Thrown when a multiplier input is zero.
    error InputMultiplierZero();
    /// @notice Thrown when the provided block number is invalid for the stake update.
    error InvalidBlockNumber();
    /// @notice Thrown when attempting to access stake history that doesn't exist for a quorum.
    error EmptyStakeHistory();
    /// @notice Thrown when the quorum is not slashable and the caller attempts to set the look ahead period.
    error QuorumNotSlashable();
    /// @notice Thrown when the look ahead period is too long.
    error LookAheadPeriodTooLong();
}

interface IStakeRegistryTypes {
    /// @notice Defines the type of stake being tracked.
    /// @param TOTAL_DELEGATED Represents the total delegated stake.
    /// @param TOTAL_SLASHABLE Represents the total slashable stake.
    enum StakeType {
        TOTAL_DELEGATED,
        TOTAL_SLASHABLE
    }

    /// @notice Stores stake information for an operator or total stakes at a specific block.
    /// @param updateBlockNumber The block number at which the stake amounts were updated.
    /// @param nextUpdateBlockNumber The block number at which the next update occurred (0 if no next update).
    /// @param stake The stake weight for the quorum.
    struct StakeUpdate {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint96 stake;
    }

    /// @notice Parameters for weighing a particular strategy's stake.
    /// @param strategy The strategy contract address.
    /// @param multiplier The weight multiplier applied to the strategy's stake.
    struct StrategyParams {
        IStrategy strategy;
        uint96 multiplier;
    }
}

interface IStakeRegistryEvents is IStakeRegistryTypes {
    /**
     * @notice Emitted when an operator's stake is updated.
     * @param operatorId The unique identifier of the operator (indexed).
     * @param quorumNumber The quorum number for which the stake was updated.
     * @param stake The new stake amount.
     */
    event OperatorStakeUpdate(bytes32 indexed operatorId, uint8 quorumNumber, uint96 stake);

    /**
     * @notice Emitted when the look ahead period for checking operator shares is updated.
     * @param oldLookAheadBlocks The previous look ahead period.
     * @param newLookAheadBlocks The new look ahead period.
     */
    event LookAheadPeriodChanged(uint32 oldLookAheadBlocks, uint32 newLookAheadBlocks);

    /**
     * @notice Emitted when the stake type is updated.
     * @param newStakeType The new stake type being set.
     */
    event StakeTypeSet(StakeType newStakeType);

    /**
     * @notice Emitted when the minimum stake for a quorum is updated.
     * @param quorumNumber The quorum number being updated (indexed).
     * @param minimumStake The new minimum stake requirement.
     */
    event MinimumStakeForQuorumUpdated(uint8 indexed quorumNumber, uint96 minimumStake);

    /**
     * @notice Emitted when a new quorum is created.
     * @param quorumNumber The number of the newly created quorum (indexed).
     */
    event QuorumCreated(uint8 indexed quorumNumber);

    /**
     * @notice Emitted when a strategy is added to a quorum.
     * @param quorumNumber The quorum number the strategy was added to (indexed).
     * @param strategy The strategy contract that was added.
     */
    event StrategyAddedToQuorum(uint8 indexed quorumNumber, IStrategy strategy);

    /**
     * @notice Emitted when a strategy is removed from a quorum.
     * @param quorumNumber The quorum number the strategy was removed from (indexed).
     * @param strategy The strategy contract that was removed.
     */
    event StrategyRemovedFromQuorum(uint8 indexed quorumNumber, IStrategy strategy);

    /**
     * @notice Emitted when a strategy's multiplier is updated.
     * @param quorumNumber The quorum number for the strategy update (indexed).
     * @param strategy The strategy contract being updated.
     * @param multiplier The new multiplier value.
     */
    event StrategyMultiplierUpdated(
        uint8 indexed quorumNumber, IStrategy strategy, uint256 multiplier
    );
}

interface IStakeRegistry is IStakeRegistryErrors, IStakeRegistryEvents {
    /// STATE

    /**
     * @notice Returns the EigenLayer delegation manager contract.
     */
    function delegation() external view returns (IDelegationManager);

    /// ACTIONS

    /**
     * @notice Registers the `operator` with `operatorId` for the specified `quorumNumbers`.
     * @param operator The address of the operator to register.
     * @param operatorId The id of the operator to register.
     * @param quorumNumbers The quorum numbers the operator is registering for, where each byte is an 8 bit integer quorumNumber.
     * @return operatorStakes The operator's current stake for each quorum.
     * @return totalStakes The total stake for each quorum.
     * @dev Access restricted to the RegistryCoordinator.
     * @dev Preconditions (these are assumed, not validated in this contract):
     *     1) `quorumNumbers` has no duplicates.
     *     2) `quorumNumbers.length` != 0.
     *     3) `quorumNumbers` is ordered in ascending order.
     *     4) The operator is not already registered.
     */
    function registerOperator(
        address operator,
        bytes32 operatorId,
        bytes memory quorumNumbers
    ) external returns (uint96[] memory operatorStakes, uint96[] memory totalStakes);

    /**
     * @notice Deregisters the operator with `operatorId` for the specified `quorumNumbers`.
     * @param operatorId The id of the operator to deregister.
     * @param quorumNumbers The quorum numbers the operator is deregistering from, where each byte is an 8 bit integer quorumNumber.
     * @dev Access restricted to the RegistryCoordinator.
     * @dev Preconditions (these are assumed, not validated in this contract):
     *     1) `quorumNumbers` has no duplicates.
     *     2) `quorumNumbers.length` != 0.
     *     3) `quorumNumbers` is ordered in ascending order.
     *     4) The operator is not already deregistered.
     *     5) `quorumNumbers` is a subset of the quorumNumbers that the operator is registered for.
     */
    function deregisterOperator(bytes32 operatorId, bytes memory quorumNumbers) external;

    /**
     * @notice Called by the registry coordinator to update the stake of a list of operators for a specific quorum.
     * @param operators The addresses of the operators to update.
     * @param operatorIds The ids of the operators to update.
     * @param quorumNumber The quorum number to update the stake for.
     * @return A list of bools, true if the corresponding operator should be deregistered since they no longer meet the minimum stake requirement.
     */
    function updateOperatorsStake(
        address[] memory operators,
        bytes32[] memory operatorIds,
        uint8 quorumNumber
    ) external returns (bool[] memory);

    /**
     * @notice Initialize a new quorum created by the registry coordinator by setting strategies, weights, and minimum stake.
     * @param quorumNumber The number of the quorum to initialize.
     * @param minimumStake The minimum stake required for the quorum.
     * @param strategyParams The initial strategy parameters for the quorum.
     */
    function initializeDelegatedStakeQuorum(
        uint8 quorumNumber,
        uint96 minimumStake,
        StrategyParams[] memory strategyParams
    ) external;

    /**
     * @notice Initialize a new quorum and push its first history update.
     * @param quorumNumber The number of the quorum to initialize.
     * @param minimumStake The minimum stake required for the quorum.
     * @param lookAheadPeriod The look ahead period for checking operator shares.
     * @param strategyParams The initial strategy parameters for the quorum.
     */
    function initializeSlashableStakeQuorum(
        uint8 quorumNumber,
        uint96 minimumStake,
        uint32 lookAheadPeriod,
        StrategyParams[] memory strategyParams
    ) external;

    /**
     * @notice Sets the minimum stake requirement for a quorum `quorumNumber`.
     * @param quorumNumber The quorum number to set the minimum stake for.
     * @param minimumStake The new minimum stake requirement.
     */
    function setMinimumStakeForQuorum(uint8 quorumNumber, uint96 minimumStake) external;

    /**
     * @notice Sets the look ahead time to `lookAheadBlocks` for checking operator shares for a specific quorum.
     * @param quorumNumber The quorum number to set the look ahead period for.
     * @param lookAheadBlocks The number of blocks to look ahead when checking shares.
     */
    function setSlashableStakeLookahead(uint8 quorumNumber, uint32 lookAheadBlocks) external;

    /**
     * @notice Adds new strategies and their associated multipliers to the specified quorum.
     * @dev Checks to make sure that the *same* strategy cannot be added multiple times (checks against both against existing and new strategies).
     * @dev This function has no check to make sure that the strategies for a single quorum have the same underlying asset. This is a concious choice,
     * since a middleware may want, e.g., a stablecoin quorum that accepts USDC, USDT, DAI, etc. as underlying assets and trades them as "equivalent".
     * @param quorumNumber The quorum number to add strategies to.
     * @param strategyParams The strategy parameters to add.
     */
    function addStrategies(uint8 quorumNumber, StrategyParams[] memory strategyParams) external;

    /**
     * @notice Removes strategies and their associated weights from the specified quorum.
     * @param quorumNumber The quorum number to remove strategies from.
     * @param indicesToRemove The indices of strategies to remove.
     * @dev Higher indices should be *first* in the list of `indicesToRemove`, since otherwise
     *     the removal of lower index entries will cause a shift in the indices of the other strategiesToRemove.
     */
    function removeStrategies(uint8 quorumNumber, uint256[] calldata indicesToRemove) external;

    /**
     * @notice Modifies the weights of strategies that are already in the mapping strategyParams.
     * @param quorumNumber The quorum number to change the strategy for.
     * @param strategyIndices The indices of the strategies to change.
     * @param newMultipliers The new multipliers for the strategies.
     */
    function modifyStrategyParams(
        uint8 quorumNumber,
        uint256[] calldata strategyIndices,
        uint96[] calldata newMultipliers
    ) external;

    /// VIEW

    /**
     * @notice Returns the minimum stake requirement for a quorum `quorumNumber`.
     * @dev In order to register for a quorum i, an operator must have at least `minimumStakeForQuorum[i]`.
     * @param quorumNumber The quorum number to query.
     * @return The minimum stake requirement.
     */
    function minimumStakeForQuorum(
        uint8 quorumNumber
    ) external view returns (uint96);

    /**
     * @notice Returns the length of the dynamic array stored in `strategyParams[quorumNumber]`.
     * @param quorumNumber The quorum number to query.
     * @return The number of strategies for the quorum.
     */
    function strategyParamsLength(
        uint8 quorumNumber
    ) external view returns (uint256);

    /**
     * @notice Returns the strategy and weight multiplier for the `index`'th strategy in the quorum.
     * @param quorumNumber The quorum number to query.
     * @param index The index of the strategy to query.
     * @return The strategy parameters.
     */
    function strategyParamsByIndex(
        uint8 quorumNumber,
        uint256 index
    ) external view returns (StrategyParams memory);

    /**
     * @notice Returns the length of the stake history for an operator in a quorum.
     * @param operatorId The id of the operator to query.
     * @param quorumNumber The quorum number to query.
     * @return The length of the stake history array.
     */
    function getStakeHistoryLength(
        bytes32 operatorId,
        uint8 quorumNumber
    ) external view returns (uint256);

    /**
     * @notice Computes the total weight of the operator in the specified quorum.
     * @param quorumNumber The quorum number to query.
     * @param operator The operator address to query.
     * @return The total weight of the operator.
     * @dev Reverts if `quorumNumber` is greater than or equal to `quorumCount`.
     */
    function weightOfOperatorForQuorum(
        uint8 quorumNumber,
        address operator
    ) external view returns (uint96);

    /**
     * @notice Returns the entire stake history array for an operator in a quorum.
     * @param operatorId The id of the operator of interest.
     * @param quorumNumber The quorum number to get the stake for.
     * @return The array of stake updates.
     */
    function getStakeHistory(
        bytes32 operatorId,
        uint8 quorumNumber
    ) external view returns (StakeUpdate[] memory);

    /**
     * @notice Returns the length of the total stake history for a quorum.
     * @param quorumNumber The quorum number to query.
     * @return The length of the total stake history array.
     */
    function getTotalStakeHistoryLength(
        uint8 quorumNumber
    ) external view returns (uint256);

    /**
     * @notice Returns the stake update at the specified index in the total stake history.
     * @param quorumNumber The quorum number to query.
     * @param index The index to query.
     * @return The stake update at the specified index.
     */
    function getTotalStakeUpdateAtIndex(
        uint8 quorumNumber,
        uint256 index
    ) external view returns (StakeUpdate memory);

    /**
     * @notice Returns the index of the operator's stake update at the specified block number.
     * @param operatorId The id of the operator to query.
     * @param quorumNumber The quorum number to query.
     * @param blockNumber The block number to query.
     * @return The index of the stake update.
     */
    function getStakeUpdateIndexAtBlockNumber(
        bytes32 operatorId,
        uint8 quorumNumber,
        uint32 blockNumber
    ) external view returns (uint32);

    /**
     * @notice Returns the indices of total stakes for the provided quorums at the given block number.
     * @param blockNumber The block number to query.
     * @param quorumNumbers The quorum numbers to query.
     * @return The array of stake update indices.
     */
    function getTotalStakeIndicesAtBlockNumber(
        uint32 blockNumber,
        bytes calldata quorumNumbers
    ) external view returns (uint32[] memory);

    /**
     * @notice Returns the stake update at the specified index for an operator in a quorum.
     * @param quorumNumber The quorum number to query.
     * @param operatorId The id of the operator to query.
     * @param index The index to query.
     * @return The stake update at the specified index.
     * @dev Function will revert if `index` is out-of-bounds.
     */
    function getStakeUpdateAtIndex(
        uint8 quorumNumber,
        bytes32 operatorId,
        uint256 index
    ) external view returns (StakeUpdate memory);

    /**
     * @notice Returns the most recent stake update for an operator in a quorum.
     * @param operatorId The id of the operator to query.
     * @param quorumNumber The quorum number to query.
     * @return The most recent stake update.
     * @dev Returns a StakeUpdate struct with all entries equal to 0 if the operator has no stake history.
     */
    function getLatestStakeUpdate(
        bytes32 operatorId,
        uint8 quorumNumber
    ) external view returns (StakeUpdate memory);

    /**
     * @notice Returns the stake at the specified block number and index for an operator in a quorum.
     * @param quorumNumber The quorum number to query.
     * @param blockNumber The block number to query.
     * @param operatorId The id of the operator to query.
     * @param index The index to query.
     * @return The stake amount.
     * @dev Function will revert if `index` is out-of-bounds.
     * @dev Used by the BLSSignatureChecker to get past stakes of signing operators.
     */
    function getStakeAtBlockNumberAndIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        bytes32 operatorId,
        uint256 index
    ) external view returns (uint96);

    /**
     * @notice Returns the total stake at the specified block number and index for a quorum.
     * @param quorumNumber The quorum number to query.
     * @param blockNumber The block number to query.
     * @param index The index to query.
     * @return The total stake amount.
     * @dev Function will revert if `index` is out-of-bounds.
     * @dev Used by the BLSSignatureChecker to get past stakes of signing operators.
     */
    function getTotalStakeAtBlockNumberFromIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        uint256 index
    ) external view returns (uint96);

    /**
     * @notice Returns the current stake for an operator in a quorum.
     * @param operatorId The id of the operator to query.
     * @param quorumNumber The quorum number to query.
     * @return The current stake amount.
     * @dev Returns 0 if the operator has no stake history.
     */
    function getCurrentStake(
        bytes32 operatorId,
        uint8 quorumNumber
    ) external view returns (uint96);

    /**
     * @notice Returns the stake of an operator at a specific block number.
     * @param operatorId The id of the operator to query.
     * @param quorumNumber The quorum number to query.
     * @param blockNumber The block number to query.
     * @return The stake amount at the specified block.
     */
    function getStakeAtBlockNumber(
        bytes32 operatorId,
        uint8 quorumNumber,
        uint32 blockNumber
    ) external view returns (uint96);

    /**
     * @notice Returns the current total stake for a quorum.
     * @param quorumNumber The quorum number to query.
     * @return The current total stake amount.
     * @dev Will revert if `_totalStakeHistory[quorumNumber]` is empty.
     */
    function getCurrentTotalStake(
        uint8 quorumNumber
    ) external view returns (uint96);
}

// lib/eigenlayer-middleware/src/interfaces/ISlashingRegistryCoordinator.sol

interface ISlashingRegistryCoordinatorErrors {
    /// @notice Thrown when array lengths in input parameters don't match.
    error InputLengthMismatch();
    /// @notice Thrown when an invalid registration type is provided.
    error InvalidRegistrationType();
    /// @notice Thrown when non-allocation manager calls restricted function.
    error OnlyAllocationManager();
    /// @notice Thrown when non-ejector calls restricted function.
    error OnlyEjector();
    /// @notice Thrown when operating on a non-existent quorum.
    error QuorumDoesNotExist();
    /// @notice Thrown when registering/deregistering with empty bitmap.
    error BitmapEmpty();
    /// @notice Thrown when registering for already registered quorums.
    error AlreadyRegisteredForQuorums();
    /// @notice Thrown when registering before ejection cooldown expires.
    error CannotReregisterYet();
    /// @notice Thrown when unregistered operator attempts restricted operation.
    error NotRegistered();
    /// @notice Thrown when operator attempts self-churn.
    error CannotChurnSelf();
    /// @notice Thrown when operator count doesn't match quorum requirements.
    error QuorumOperatorCountMismatch();
    /// @notice Thrown when operator has insufficient stake for churn.
    error InsufficientStakeForChurn();
    /// @notice Thrown when attempting to kick operator above stake threshold.
    error CannotKickOperatorAboveThreshold();
    /// @notice Thrown when updating to zero bitmap.
    error BitmapCannotBeZero();
    /// @notice Thrown when deregistering from unregistered quorum.
    error NotRegisteredForQuorum();
    /// @notice Thrown when churn approver salt is already used.
    error ChurnApproverSaltUsed();
    /// @notice Thrown when operators or quorums list is not sorted ascending.
    error NotSorted();
    /// @notice Thrown when maximum quorum count is reached.
    error MaxQuorumsReached();
    /// @notice Thrown when the provided AVS address does not match the expected one.
    error InvalidAVS();
    /// @notice Thrown when attempting to kick an operator that is not registered.
    error OperatorNotRegistered();
    /// @notice Thrown when lookAheadPeriod is greater than or equal to DEALLOCATION_DELAY.
    error LookAheadPeriodTooLong();
    /// @notice Thrown when the number of operators in a quorum would exceed the maximum allowed.
    error MaxOperatorCountReached();
    /// @notice Thrown when the operator is not registered for the quorum.
    error OperatorNotRegisteredForQuorum();
}

interface ISlashingRegistryCoordinatorTypes {
    /// @notice Core data structure for tracking operator information.
    /// @dev Links an operator's unique identifier with their current registration status.
    /// @param operatorId Unique identifier for the operator, typically derived from their BLS public key.
    /// @param status Current registration state of the operator in the system.
    struct OperatorInfo {
        bytes32 operatorId;
        OperatorStatus status;
    }

    /// @notice Records historical changes to an operator's quorum registrations.
    /// @dev Used for querying an operator's quorum memberships at specific block numbers.
    /// @param updateBlockNumber Block number when this update occurred (inclusive).
    /// @param nextUpdateBlockNumber Block number when the next update occurred (exclusive), or 0 if this is the latest update.
    /// @param quorumBitmap Bitmap where each bit represents registration in a specific quorum (1 = registered, 0 = not registered).
    struct QuorumBitmapUpdate {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint192 quorumBitmap;
    }

    /// @notice Configuration parameters for operator management within a quorum.
    /// @dev All BIPs (Basis Points) values are in relation to BIPS_DENOMINATOR (10000).
    /// @param maxOperatorCount Maximum number of operators allowed in the quorum.
    /// @param kickBIPsOfOperatorStake Required stake ratio (in BIPs) between new and existing operator for churn.
    ///        Example: 10500 means new operator needs 105% of existing operator's stake.
    /// @param kickBIPsOfTotalStake Minimum stake ratio (in BIPs) of total quorum stake an operator must maintain.
    ///        Example: 100 means operator needs 1% of total quorum stake to avoid being churned.
    struct OperatorSetParam {
        uint32 maxOperatorCount;
        uint16 kickBIPsOfOperatorStake;
        uint16 kickBIPsOfTotalStake;
    }

    /// @notice Parameters for removing an operator during churn.
    /// @dev Used in registerOperatorWithChurn to specify which operator to replace.
    /// @param quorumNumber The quorum from which to remove the operator.
    /// @param operator Address of the operator to be removed.
    struct OperatorKickParam {
        uint8 quorumNumber;
        address operator;
    }

    /// @notice Represents the registration state of an operator.
    /// @dev Used to track an operator's lifecycle in the system.
    /// @custom:enum NEVER_REGISTERED The operator has never registered with the system.
    /// @custom:enum REGISTERED The operator is currently registered and active.
    /// @custom:enum DEREGISTERED The operator was previously registered but has since deregistered.
    enum OperatorStatus {
        NEVER_REGISTERED,
        REGISTERED,
        DEREGISTERED
    }

    /**
     * @notice Enum representing the type of operator registration.
     * @custom:enum NORMAL Represents a normal operator registration.
     * @custom:enum CHURN Represents an operator registration during a churn event.
     */
    enum RegistrationType {
        NORMAL,
        CHURN
    }

    /**
     * @notice Data structure for storing the results of a registerOperator call.
     * @dev Contains arrays storing per-quorum information about operator counts and stakes.
     * @param numOperatorsPerQuorum For each quorum the operator registered for, stores the number of operators registered.
     * @param operatorStakes For each quorum the operator registered for, stores the stake of the operator in the quorum.
     * @param totalStakes For each quorum the operator registered for, stores the total stake of the quorum.
     */
    struct RegisterResults {
        uint32[] numOperatorsPerQuorum;
        uint96[] operatorStakes;
        uint96[] totalStakes;
    }
}

interface ISlashingRegistryCoordinatorEvents is ISlashingRegistryCoordinatorTypes {
    /**
     * @notice Emitted when an operator registers for service in one or more quorums.
     * @dev Emitted in _registerOperator() and _registerOperatorToOperatorSet().
     * @param operator The address of the registered operator.
     * @param operatorId The unique identifier of the operator (BLS public key hash).
     */
    event OperatorRegistered(address indexed operator, bytes32 indexed operatorId);

    /**
     * @notice Emitted when an operator deregisters from service in one or more quorums.
     * @dev Emitted in _deregisterOperator().
     * @param operator The address of the deregistered operator.
     * @param operatorId The unique identifier of the operator (BLS public key hash).
     */
    event OperatorDeregistered(address indexed operator, bytes32 indexed operatorId);

    /**
     * @notice Emitted when a new quorum is created.
     * @param quorumNumber The identifier of the quorum being created.
     * @param operatorSetParams The operator set parameters for the quorum.
     * @param minimumStake The minimum stake required for operators in this quorum.
     * @param strategyParams The strategy parameters for stake calculation.
     * @param stakeType The type of stake being tracked (TOTAL_DELEGATED or TOTAL_SLASHABLE).
     * @param lookAheadPeriod The number of blocks to look ahead when calculating slashable stake (only used for TOTAL_SLASHABLE).
     */
    event QuorumCreated(
        uint8 indexed quorumNumber,
        OperatorSetParam operatorSetParams,
        uint96 minimumStake,
        IStakeRegistryTypes.StrategyParams[] strategyParams,
        IStakeRegistryTypes.StakeType stakeType,
        uint32 lookAheadPeriod
    );

    /**
     * @notice Emitted when a quorum's operator set parameters are updated.
     * @dev Emitted in _setOperatorSetParams().
     * @param quorumNumber The identifier of the quorum being updated.
     * @param operatorSetParams The new operator set parameters for the quorum.
     */
    event OperatorSetParamsUpdated(uint8 indexed quorumNumber, OperatorSetParam operatorSetParams);

    /**
     * @notice Emitted when the churn approver address is updated.
     * @dev Emitted in _setChurnApprover().
     * @param prevChurnApprover The previous churn approver address.
     * @param newChurnApprover The new churn approver address.
     */
    event ChurnApproverUpdated(address prevChurnApprover, address newChurnApprover);

    /**
     * @notice Emitted when the AVS address is updated.
     * @param prevAVS The previous AVS address.
     * @param newAVS The new AVS address.
     */
    event AVSUpdated(address prevAVS, address newAVS);

    /**
     * @notice Emitted when the ejector address is updated.
     * @dev Emitted in _setEjector().
     * @param prevEjector The previous ejector address.
     * @param newEjector The new ejector address.
     */
    event EjectorUpdated(address prevEjector, address newEjector);

    /**
     * @notice Emitted when all operators in a quorum are updated simultaneously.
     * @dev Emitted in updateOperatorsForQuorum().
     * @param quorumNumber The identifier of the quorum being updated.
     * @param blocknumber The block number at which the quorum update occurred.
     */
    event QuorumBlockNumberUpdated(uint8 indexed quorumNumber, uint256 blocknumber);

    /**
     * @notice Emitted when an operator's socket is updated.
     * @dev Emitted in updateSocket().
     * @param operatorId The unique identifier of the operator (BLS public key hash).
     * @param socket The new socket address for the operator (typically an IP address).
     */
    event OperatorSocketUpdate(bytes32 indexed operatorId, string socket);

    /**
     * @notice Emitted when the ejection cooldown period is updated.
     * @dev Emitted in setEjectionCooldown().
     * @param prevEjectionCooldown The previous cooldown duration in seconds.
     * @param newEjectionCooldown The new cooldown duration in seconds.
     */
    event EjectionCooldownUpdated(uint256 prevEjectionCooldown, uint256 newEjectionCooldown);
}

interface ISlashingRegistryCoordinator is
    IAVSRegistrar,
    ISlashingRegistryCoordinatorErrors,
    ISlashingRegistryCoordinatorEvents
{
    /// IMMUTABLES & CONSTANTS

    /**
     * @notice EIP-712 typehash for operator churn approval signatures.
     * @return The typehash constant.
     */
    function OPERATOR_CHURN_APPROVAL_TYPEHASH() external view returns (bytes32);

    /**
     * @notice EIP-712 typehash for pubkey registration signatures.
     * @return The typehash constant.
     */
    function PUBKEY_REGISTRATION_TYPEHASH() external view returns (bytes32);

    /**
     * @notice Reference to the BLSApkRegistry contract.
     * @return The BLSApkRegistry contract interface.
     */
    function blsApkRegistry() external view returns (IBLSApkRegistry);

    /**
     * @notice Reference to the StakeRegistry contract.
     * @return The StakeRegistry contract interface.
     */
    function stakeRegistry() external view returns (IStakeRegistry);

    /**
     * @notice Reference to the IndexRegistry contract.
     * @return The IndexRegistry contract interface.
     */
    function indexRegistry() external view returns (IIndexRegistry);

    /**
     * @notice Reference to the AllocationManager contract.
     * @return The AllocationManager contract interface.
     * @dev This is only relevant for Slashing AVSs
     */
    function allocationManager() external view returns (IAllocationManager);

    /**
     * @notice Reference to the SocketRegistry contract.
     * @return The SocketRegistry contract interface.
     */
    function socketRegistry() external view returns (ISocketRegistry);

    /// STORAGE

    /**
     * @notice The total number of quorums that have been created.
     * @return The count of quorums.
     */
    function quorumCount() external view returns (uint8);

    /**
     * @notice Checks if a churn approver salt has been used.
     * @param salt The salt to check.
     * @return True if the salt has been used, false otherwise.
     */
    function isChurnApproverSaltUsed(
        bytes32 salt
    ) external view returns (bool);

    /**
     * @notice Gets the last block number when all operators in a quorum were updated.
     * @param quorumNumber The quorum identifier.
     * @return The block number of the last update.
     */
    function quorumUpdateBlockNumber(
        uint8 quorumNumber
    ) external view returns (uint256);

    /**
     * @notice The address authorized to approve operator churn operations.
     * @return The churn approver address.
     */
    function churnApprover() external view returns (address);

    /**
     * @notice The address authorized to forcibly eject operators.
     * @return The ejector address.
     */
    function ejector() external view returns (address);

    /**
     * @notice Gets the timestamp of an operator's last ejection.
     * @param operator The operator address.
     * @return The timestamp of the last ejection.
     */
    function lastEjectionTimestamp(
        address operator
    ) external view returns (uint256);

    /**
     * @notice The cooldown period after ejection before an operator can re-register.
     * @return The cooldown duration in seconds.
     */
    function ejectionCooldown() external view returns (uint256);

    /// ACTIONS

    /**
     * @notice Updates stake weights for specified operators. If any operator is found to be below
     * the minimum stake for their registered quorums, they are deregistered from those quorums.
     * @param operators The operators whose stakes should be updated.
     * @dev Stakes are queried from the Eigenlayer core DelegationManager contract.
     * @dev WILL BE DEPRECATED IN FAVOR OF updateOperatorsForQuorum
     */
    function updateOperators(
        address[] memory operators
    ) external;

    /**
     * @notice For each quorum in `quorumNumbers`, updates the StakeRegistry's view of ALL its registered operators' stakes.
     * Each quorum's `quorumUpdateBlockNumber` is also updated, which tracks the most recent block number when ALL registered
     * operators were updated.
     * @dev stakes are queried from the Eigenlayer core DelegationManager contract
     * @param operatorsPerQuorum for each quorum in `quorumNumbers`, this has a corresponding list of operators to update.
     * @dev Each list of operator addresses MUST be sorted in ascending order
     * @dev Each list of operator addresses MUST represent the entire list of registered operators for the corresponding quorum
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being updated
     * @dev invariant: Each list of `operatorsPerQuorum` MUST be a sorted version of `IndexRegistry.getOperatorListAtBlockNumber`
     * for the corresponding quorum.
     * @dev note on race condition: if an operator registers/deregisters for any quorum in `quorumNumbers` after a txn to
     * this method is broadcast (but before it is executed), the method will fail
     */
    function updateOperatorsForQuorum(
        address[][] memory operatorsPerQuorum,
        bytes calldata quorumNumbers
    ) external;

    /**
     * @notice Updates the socket of the msg.sender given they are a registered operator.
     * @param socket The new socket address for the operator (typically an IP address).
     * @dev Will revert if msg.sender is not a registered operator.
     */
    function updateSocket(
        string memory socket
    ) external;

    /**
     * @notice Forcibly removes an operator from specified quorums and sets their ejection timestamp.
     * @param operator The operator address to eject.
     * @param quorumNumbers The quorum numbers to eject the operator from.
     * @dev Can only be called by the ejector address.
     * @dev The operator cannot re-register until ejectionCooldown period has passed.
     */
    function ejectOperator(address operator, bytes memory quorumNumbers) external;

    /**
     * @notice Creates a new quorum that tracks total delegated stake for operators.
     * @param operatorSetParams Configures the quorum's max operator count and churn parameters.
     * @param minimumStake Sets the minimum stake required for an operator to register or remain registered.
     * @param strategyParams A list of strategies and multipliers used by the StakeRegistry to calculate
     * an operator's stake weight for the quorum.
     * @dev For m2 AVS this function has the same behavior as createQuorum before.
     * @dev For migrated AVS that enable operator sets this will create a quorum that measures total delegated stake for operator set.
     */
    function createTotalDelegatedStakeQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistryTypes.StrategyParams[] memory strategyParams
    ) external;

    /**
     * @notice Creates a new quorum that tracks slashable stake for operators.
     * @param operatorSetParams Configures the quorum's max operator count and churn parameters.
     * @param minimumStake Sets the minimum stake required for an operator to register or remain registered.
     * @param strategyParams A list of strategies and multipliers used by the StakeRegistry to calculate
     * an operator's stake weight for the quorum.
     * @param lookAheadPeriod The number of blocks to look ahead when calculating slashable stake.
     * @dev Can only be called when operator sets are enabled.
     */
    function createSlashableStakeQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistryTypes.StrategyParams[] memory strategyParams,
        uint32 lookAheadPeriod
    ) external;

    /**
     * @notice Updates the configuration parameters for an existing operator set quorum.
     * @param quorumNumber The identifier of the quorum to update.
     * @param operatorSetParams The new operator set parameters to apply.
     * @dev Can only be called by the contract owner.
     */
    function setOperatorSetParams(
        uint8 quorumNumber,
        OperatorSetParam memory operatorSetParams
    ) external;

    /**
     * @notice Updates the address authorized to approve operator churn operations.
     * @param _churnApprover The new churn approver address.
     * @dev Can only be called by the contract owner.
     * @dev The churn approver is responsible for signing off on operator replacements in full quorums.
     */
    function setChurnApprover(
        address _churnApprover
    ) external;

    /**
     * @notice Updates the address authorized to forcibly eject operators.
     * @param _ejector The new ejector address.
     * @dev Can only be called by the contract owner.
     * @dev The ejector can force-remove operators from quorums regardless of their stake.
     */
    function setEjector(
        address _ejector
    ) external;

    /**
     * @notice Updates the duration operators must wait after ejection before re-registering.
     * @param _ejectionCooldown The new cooldown duration in seconds.
     * @dev Can only be called by the contract owner.
     */
    function setEjectionCooldown(
        uint256 _ejectionCooldown
    ) external;

    /**
     * @notice Updates the avs address for this AVS (used for UAM integration in EigenLayer)
     * @param _avs The new avs address
     * @dev Can only be called by the contract owner
     * @dev NOTE: Updating this value will break existing OperatorSets and UAM integration. This value should only be set once.
     */
    function setAVS(
        address _avs
    ) external;

    /// VIEW

    /**
     * @notice Returns the hash of the message that operators must sign with their BLS key to register
     * @param operator The operator's Ethereum address
     */
    function calculatePubkeyRegistrationMessageHash(
        address operator
    ) external view returns (bytes32);

    /**
     * @notice Returns the operator set parameters for a given quorum.
     * @param quorumNumber The identifier of the quorum to query.
     * @return The OperatorSetParam struct containing max operator count and churn thresholds.
     */
    function getOperatorSetParams(
        uint8 quorumNumber
    ) external view returns (OperatorSetParam memory);

    /**
     * @notice Returns the complete operator information for a given address.
     * @param operator The operator address to query.
     * @return An OperatorInfo struct containing the operator's ID and registration status.
     */
    function getOperator(
        address operator
    ) external view returns (OperatorInfo memory);

    /**
     * @notice Returns the unique identifier for a given operator address.
     * @param operator The operator address to query.
     * @return The operator's ID (derived from their BLS public key hash).
     */
    function getOperatorId(
        address operator
    ) external view returns (bytes32);

    /**
     * @notice Returns the operator address associated with a given operator ID.
     * @param operatorId The unique identifier to look up.
     * @return The operator's address.
     * @dev Returns address(0) if the ID is not registered.
     */
    function getOperatorFromId(
        bytes32 operatorId
    ) external view returns (address);

    /**
     * @notice Returns the current registration status for a given operator.
     * @param operator The operator address to query.
     * @return The operator's status (NEVER_REGISTERED, REGISTERED, or DEREGISTERED).
     */
    function getOperatorStatus(
        address operator
    ) external view returns (OperatorStatus);

    /**
     * @notice Returns the indices needed to look up quorum bitmaps for operators at a specific block.
     * @param blockNumber The historical block number to query.
     * @param operatorIds Array of operator IDs to get indices for.
     * @return Array of indices corresponding to each operator ID.
     * @dev Reverts if any operator had not yet registered at the specified block.
     * @dev This function is designed to find proper inputs for getQuorumBitmapAtBlockNumberByIndex.
     */
    function getQuorumBitmapIndicesAtBlockNumber(
        uint32 blockNumber,
        bytes32[] memory operatorIds
    ) external view returns (uint32[] memory);

    /**
     * @notice Returns the quorum bitmap for an operator at a specific historical block.
     * @param operatorId The operator's unique identifier.
     * @param blockNumber The historical block number to query.
     * @param index The index in the operator's bitmap history (from getQuorumBitmapIndicesAtBlockNumber).
     * @return The quorum bitmap showing which quorums the operator was registered for.
     * @dev Reverts if the index is incorrect for the specified block number.
     */
    function getQuorumBitmapAtBlockNumberByIndex(
        bytes32 operatorId,
        uint32 blockNumber,
        uint256 index
    ) external view returns (uint192);

    /**
     * @notice Returns a specific update from an operator's quorum bitmap history.
     * @param operatorId The operator's unique identifier.
     * @param index The index in the bitmap history to query.
     * @return The QuorumBitmapUpdate struct at that index.
     */
    function getQuorumBitmapUpdateByIndex(
        bytes32 operatorId,
        uint256 index
    ) external view returns (QuorumBitmapUpdate memory);

    /**
     * @notice Returns the current quorum bitmap for an operator.
     * @param operatorId The operator's unique identifier.
     * @return A bitmap where each bit represents registration in a specific quorum.
     * @dev Returns 0 if the operator is not registered for any quorums.
     */
    function getCurrentQuorumBitmap(
        bytes32 operatorId
    ) external view returns (uint192);

    /**
     * @notice Returns the number of updates in an operator's bitmap history.
     * @param operatorId The operator's unique identifier.
     * @return The length of the bitmap history array.
     */
    function getQuorumBitmapHistoryLength(
        bytes32 operatorId
    ) external view returns (uint256);

    /**
     * @notice Calculates the digest hash that must be signed by the churn approver.
     * @param registeringOperator The address of the operator attempting to register.
     * @param registeringOperatorId The unique ID of the registering operator.
     * @param operatorKickParams Parameters specifying which operators to replace in full quorums.
     * @param salt Random value to ensure signature uniqueness.
     * @param expiry Timestamp after which the signature becomes invalid.
     * @return The EIP-712 typed data hash to be signed.
     */
    function calculateOperatorChurnApprovalDigestHash(
        address registeringOperator,
        bytes32 registeringOperatorId,
        OperatorKickParam[] memory operatorKickParams,
        bytes32 salt,
        uint256 expiry
    ) external view returns (bytes32);

    /**
     * @notice Returns the message hash that an operator must sign to register their BLS public key.
     * @param operator The address of the operator registering their key.
     * @return A point on the G1 curve representing the message hash.
     */
    function pubkeyRegistrationMessageHash(
        address operator
    ) external view returns (BN254.G1Point memory);

    /**
     * @notice Returns the avs address for this AVS (used for UAM integration in EigenLayer)
     * @dev NOTE: Updating this value will break existing OperatorSets and UAM integration. This value should only be set once.
     * @return The avs address
     */
    function avs() external view returns (address);
}

// lib/eigenlayer-middleware/src/interfaces/IBLSSignatureChecker.sol

interface IBLSSignatureCheckerErrors {
    /// @notice Thrown when the caller is not the registry coordinator owner.
    error OnlyRegistryCoordinatorOwner();
    /// @notice Thrown when the quorum numbers input in is empty.
    error InputEmptyQuorumNumbers();
    /// @notice Thrown when two array parameters have mismatching lengths.
    error InputArrayLengthMismatch();
    /// @notice Thrown when the non-signer pubkey length does not match non-signer bitmap indices length.
    error InputNonSignerLengthMismatch();
    /// @notice Thrown when the reference block number is invalid.
    error InvalidReferenceBlocknumber();
    /// @notice Thrown when the non signer pubkeys are not sorted.
    error NonSignerPubkeysNotSorted();
    /// @notice Thrown when the quorum apk hash in storage does not match provided quorum apk.
    error InvalidQuorumApkHash();
    /// @notice Thrown when BLS pairing precompile call fails.
    error InvalidBLSPairingKey();
    /// @notice Thrown when BLS signature is invalid.
    error InvalidBLSSignature();
}

interface IBLSSignatureCheckerTypes {
    /// @notice Contains bitmap and pubkey hash information for non-signing operators.
    /// @param quorumBitmaps Array of bitmaps indicating which quorums each non-signer was registered for.
    /// @param pubkeyHashes Array of BLS public key hashes for each non-signer.
    struct NonSignerInfo {
        uint256[] quorumBitmaps;
        bytes32[] pubkeyHashes;
    }

    /// @notice Contains non-signer information and aggregated signature data for BLS verification.
    /// @param nonSignerQuorumBitmapIndices The indices of all non-signer quorum bitmaps.
    /// @param nonSignerPubkeys The G1 public keys of all non-signers.
    /// @param quorumApks The aggregate G1 public key of each quorum.
    /// @param apkG2 The aggregate G2 public key of all signers.
    /// @param sigma The aggregate G1 signature of all signers.
    /// @param quorumApkIndices The indices of each quorum's aggregate public key in the APK registry.
    /// @param totalStakeIndices The indices of each quorum's total stake in the stake registry.
    /// @param nonSignerStakeIndices The indices of each non-signer's stake within each quorum.
    /// @dev Used as input to checkSignatures() to verify BLS signatures.
    struct NonSignerStakesAndSignature {
        uint32[] nonSignerQuorumBitmapIndices;
        BN254.G1Point[] nonSignerPubkeys;
        BN254.G1Point[] quorumApks;
        BN254.G2Point apkG2;
        BN254.G1Point sigma;
        uint32[] quorumApkIndices;
        uint32[] totalStakeIndices;
        uint32[][] nonSignerStakeIndices;
    }

    /// @notice Records the total stake amounts for operators in each quorum.
    /// @param signedStakeForQuorum Array of total stake amounts from operators who signed, per quorum.
    /// @param totalStakeForQuorum Array of total stake amounts from all operators, per quorum.
    /// @dev Used to track stake distribution and calculate quorum thresholds. Array indices correspond to quorum numbers.
    struct QuorumStakeTotals {
        uint96[] signedStakeForQuorum;
        uint96[] totalStakeForQuorum;
    }
}

interface IBLSSignatureChecker is IBLSSignatureCheckerErrors, IBLSSignatureCheckerTypes {
    /* STATE */

    /*
     * @notice Returns the address of the registry coordinator contract.
     * @return The address of the registry coordinator.
     * @dev This value is immutable and set during contract construction.
     */
    function registryCoordinator() external view returns (ISlashingRegistryCoordinator);

    /*
     * @notice Returns the address of the stake registry contract.
     * @return The address of the stake registry.
     * @dev This value is immutable and set during contract construction.
     */
    function stakeRegistry() external view returns (IStakeRegistry);

    /*
     * @notice Returns the address of the BLS APK registry contract.
     * @return The address of the BLS APK registry.
     * @dev This value is immutable and set during contract construction.
     */
    function blsApkRegistry() external view returns (IBLSApkRegistry);

    /*
     * @notice Returns the address of the delegation manager contract.
     * @return The address of the delegation manager.
     * @dev This value is immutable and set during contract construction.
     */
    function delegation() external view returns (IDelegationManager);

    /* VIEW */

    /*
     * @notice This function is called by disperser when it has aggregated all the signatures of the operators
     * that are part of the quorum for a particular taskNumber and is asserting them into onchain. The function
     * checks that the claim for aggregated signatures are valid.
     *
     * The thesis of this procedure entails:
     * 1. Getting the aggregated pubkey of all registered nodes at the time of pre-commit by the
     * disperser (represented by apk in the parameters)
     * 2. Subtracting the pubkeys of all non-signers (nonSignerPubkeys) and storing
     * the output in apk to get aggregated pubkey of all operators that are part of quorum
     * 3. Using this aggregated pubkey to verify the aggregated signature under BLS scheme
     *
     * @param msgHash The hash of the message that was signed. NOTE: Be careful to ensure msgHash is
     * collision-resistant! This method does not hash msgHash in any way, so if an attacker is able
     * to pass in an arbitrary value, they may be able to tamper with signature verification.
     * @param quorumNumbers The quorum numbers to verify signatures for, where each byte is an 8-bit integer.
     * @param referenceBlockNumber The block number at which the stake information is being verified
     * @param nonSignerStakesAndSignature Contains non-signer information and aggregated signature data.
     * @return quorumStakeTotals The struct containing the total and signed stake for each quorum
     * @return signatoryRecordHash The hash of the signatory record, which is used for fraud proofs
     * @dev Before signature verification, the function verifies operator stake information. This includes
     * ensuring that the provided referenceBlockNumber is valid and recent enough, and that the stake is
     * either the most recent update for the total stake (of the operator) or latest before the referenceBlockNumber.
     */
    function checkSignatures(
        bytes32 msgHash,
        bytes calldata quorumNumbers,
        uint32 referenceBlockNumber,
        NonSignerStakesAndSignature memory nonSignerStakesAndSignature
    ) external view returns (QuorumStakeTotals memory, bytes32);

    /*
     * @notice Attempts to verify signature `sigma` against message hash `msgHash` using aggregate public keys `apk` and `apkG2`.
     * @param msgHash The hash of the message that was signed.
     * @param apk The aggregate public key in G1.
     * @param apkG2 The aggregate public key in G2.
     * @param sigma The signature to verify.
     * @return pairingSuccessful True if the pairing check succeeded.
     * @return siganatureIsValid True if the signature is valid.
     */
    function trySignatureAndApkVerification(
        bytes32 msgHash,
        BN254.G1Point memory apk,
        BN254.G2Point memory apkG2,
        BN254.G1Point memory sigma
    ) external view returns (bool pairingSuccessful, bool siganatureIsValid);
}

// src/interface/IGasKillerSDK.sol

/**
 * @title IGasKillerSDK
 * @notice Interface for GasKillerSDK contracts
 * @dev This interface defines the core functionality that GasKillerSDK implementations must provide
 */
interface IGasKillerSDK is IERC165 {
    // Custom errors
    error InvalidTransitionIndex();
    error InvalidSignature();
    error InvalidStorageUpdates();
    error InvalidOperation();
    error InsufficientQuorumThreshold();
    error StaleBlockNumber();
    error FutureBlockNumber();

    /**
     * @notice Function to verify if a signature is valid and contains correct storage updates
     * @param msgHash The hash of the message to verify
     * @param quorumNumbers The quorum numbers to check signatures for
     * @param referenceBlockNumber The block number to use as reference for operator set
     * @param storageUpdates The storage updates to verify
     * @param transitionIndex The transition index
     * @param targetFunction The target function selector
     * @param nonSignerStakesAndSignature The non-signer stakes and signature data computed off-chain
     */
    function verifyAndUpdate(
        bytes32 msgHash,
        bytes calldata quorumNumbers,
        uint32 referenceBlockNumber,
        bytes calldata storageUpdates,
        uint256 transitionIndex,
        bytes4 targetFunction,
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature calldata nonSignerStakesAndSignature
    ) external;
}

// src/GasKillerSDK.sol

/**
 * @title GasKillerSDK
 * @notice Base SDK for implementing Gas Killer functionality in contracts
 * @dev Inherit from this contract to add Gas Killer capabilities to your contract
 */
abstract contract GasKillerSDK is StateTracker, IGasKillerSDK {
    /// @custom:storage-location erc7201:gaskiller.GasKillerSDK.storage
    struct GasKillerSDKStorage {
        bytes namespace; // Namespace for the contract
        address avsAddress; // The AVS service manager address
        IBLSSignatureChecker blsSignatureChecker; // The BLS signature checker contract
        uint256 blockStaleMeasure; // Max block age for reference block validity
    }

    // keccak256(abi.encode(uint256(keccak256("gaskiller.GasKillerSDK.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant GAS_KILLER_SDK_STORAGE_LOCATION =
        0x321ebf629ed2e1e368f0890e8fdd95cf9a2ae5961b66a1805f0b2ec84e21d000;

    // Constants for stake threshold checking
    uint8 public constant THRESHOLD_DENOMINATOR = 100;
    uint8 public constant QUORUM_THRESHOLD = 66; // 66% quorum threshold

    // Default values for the storage
    uint256 private constant DEFAULT_BLOCK_STALE_MEASURE = 300;

    /**
     * @notice Function to verify if a signature is valid and contains correct storage updates
     * @param msgHash The hash of the message to verify
     * @param quorumNumbers The quorum numbers to check signatures for
     * @param referenceBlockNumber The block number to use as reference for operator set
     * @param storageUpdates The storage updates to verify
     * @param transitionIndex The transition index
     * @param targetFunction The target function selector
     * @param nonSignerStakesAndSignature The non-signer stakes and signature data computed off-chain
     */
    function verifyAndUpdate(
        bytes32 msgHash,
        bytes calldata quorumNumbers,
        uint32 referenceBlockNumber,
        bytes calldata storageUpdates,
        uint256 transitionIndex,
        bytes4 targetFunction,
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature calldata nonSignerStakesAndSignature
    ) external trackState {
        GasKillerSDKStorage storage $ = _getGasKillerSDKStorage();

        // Check block number validity
        require(referenceBlockNumber < block.number, FutureBlockNumber());
        require((uint256(referenceBlockNumber) + _getBlockStaleMeasure()) >= block.number, StaleBlockNumber());

        // Verify transition index and message hash
        require(transitionIndex + 1 == stateTransitionCount(), InvalidTransitionIndex());
        bytes32 expectedHash = sha256(abi.encode(transitionIndex, address(this), targetFunction, storageUpdates));
        require(expectedHash == msgHash, InvalidSignature());

        // Verify the signatures using checkSignatures
        (IBLSSignatureCheckerTypes.QuorumStakeTotals memory stakeTotals,) = $.blsSignatureChecker
            .checkSignatures(msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature);

        // Check that signatories own at least 66% of each quorum
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            require(
                stakeTotals.signedStakeForQuorum[i] * THRESHOLD_DENOMINATOR
                    >= stakeTotals.totalStakeForQuorum[i] * QUORUM_THRESHOLD,
                InsufficientQuorumThreshold()
            );
        }

        // Apply the state changes
        _stateChangeHandler(storageUpdates);
    }

    /**
     * @notice Query if a contract implements an interface
     * @param interfaceId The interface identifier, as specified in ERC-165
     * @return `true` if the contract implements `interfaceId` and `false` otherwise
     * @dev This implementation supports ERC165 and IGasKillerSDK interface detection
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IGasKillerSDK).interfaceId;
    }

    /**
     * @notice Function to get the expected hash for a given transition index, target function, and storage updates
     * @param transitionIndex The transition index
     * @param targetFunction The target function selector
     * @param storageUpdates The storage updates
     * @return bytes32 The expected hash
     */
    function getMessageHash(uint256 transitionIndex, bytes4 targetFunction, bytes calldata storageUpdates)
        external
        view
        returns (bytes32)
    {
        return sha256(abi.encode(transitionIndex, address(this), targetFunction, storageUpdates));
    }

    /**
     * @notice Function to get the AVS address
     * @return address The AVS address
     */
    function avsAddress() external view returns (address) {
        return _getGasKillerSDKStorage().avsAddress;
    }

    /**
     * @notice Function to get the BLS signature checker address
     * @return address The BLS signature checker address
     */
    function blsSignatureChecker() external view returns (address) {
        return address(_getGasKillerSDKStorage().blsSignatureChecker);
    }

    /**
     * @notice Function to get the namespace
     * @return bytes The namespace
     */
    function namespace() external view returns (bytes memory) {
        return _getGasKillerSDKStorage().namespace;
    }

    /**
     * @notice Function to get the block stale measure
     * @return uint256 The block stale measure
     */
    function blockStaleMeasure() external view returns (uint256) {
        return _getBlockStaleMeasure();
    }

    /**
     * @notice Function to apply storage updates
     * @param storageUpdates The storage updates to apply
     */
    function _stateChangeHandler(bytes calldata storageUpdates) internal {
        (StateUpdateType[] memory types, bytes[] memory args) = abi.decode(storageUpdates, (StateUpdateType[], bytes[]));
        StateChangeHandlerLib._runStateUpdates(types, args);
    }

    /**
     * @notice Internal function to set the AVS address
     * @dev Namespace is used to identify the contract in the AVS service manager
     * @param _avsAddress The new AVS address
     */
    function _setAvsAddress(address _avsAddress) internal {
        GasKillerSDKStorage storage $ = _getGasKillerSDKStorage();
        $.avsAddress = _avsAddress;
        $.namespace = abi.encodePacked($.avsAddress, "gaskiller");
    }

    /**
     * @notice Internal function to set the BLS signature checker address
     * @param _blsSignatureChecker The new BLS signature checker address
     */
    function _setBlsSignatureChecker(address _blsSignatureChecker) internal {
        GasKillerSDKStorage storage $ = _getGasKillerSDKStorage();
        $.blsSignatureChecker = IBLSSignatureChecker(_blsSignatureChecker);
    }

    /**
     * @notice Internal function to set the block stale measure
     * @param _blockStaleMeasure The new block stale measure value
     */
    function _setBlockStaleMeasure(uint256 _blockStaleMeasure) internal {
        _getGasKillerSDKStorage().blockStaleMeasure = _blockStaleMeasure;
    }

    /**
     * @notice Internal function to get the block stale measure
     * @return uint256 The block stale measure
     */
    function _getBlockStaleMeasure() internal view returns (uint256) {
        uint256 value = _getGasKillerSDKStorage().blockStaleMeasure;
        return value == 0 ? DEFAULT_BLOCK_STALE_MEASURE : value;
    }

    /**
     * @notice Internal function to get the GasKillerSDK storage
     * @return $ The GasKillerSDK storage struct
     */
    function _getGasKillerSDKStorage() private pure returns (GasKillerSDKStorage storage $) {
        assembly {
            $.slot := GAS_KILLER_SDK_STORAGE_LOCATION
        }
    }
}

// lib/bread-token-v2/src/interfaces/IBread.sol

interface IBread_0{
    function claimYield(uint256 amount, address receiver) external ;
    function yieldAccrued() external view  returns (uint256);
    function setYieldClaimer(address _yieldClaimer) external ;

}

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20_1 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// src/interfaces/multipliers/IMultiplier.sol

interface IMultiplier {
    /// @notice Updates the multiplying factor for a specific user
    /// @param _user The address of the user to update the multiplying factor for
    function updateMultiplyingFactor(address _user) external;

    /// @notice Returns the multiplying factor for `_user`.
    function getMultiplyingFactor(address _user) external view returns (uint256);

    /// @notice Returns the validity period of the multiplier for `_user`.
    function validUntil(address _user) external view returns (uint256);
}

// src/interfaces/IYieldDistributor.sol

/**
 * @title `YieldDistributor` interface
 */
interface IYieldDistributor {
    /// @notice The error emitted when attempting to add a project that is already in the `projects` array
    error AlreadyMemberProject();
    /// @notice The error emitted when attempting to calculate voting power for a period that has not yet ended
    error EndAfterCurrentBlock();
    /// @notice The error emitted when attempting to vote with a point value greater than `pointsMax`
    error ExceedsMaxPoints();
    /// @notice The error emitted when attempting to vote with an incorrect number of projects
    error IncorrectNumberOfProjects();
    /// @notice The error emitted when attempting to instantiate a variable with a zero value
    error MustBeGreaterThanZero();
    /// @notice The error emitted when attempting to add or remove a project that is already queued for addition or removal
    error ProjectAlreadyQueued();
    /// @notice The error emitted when attempting to remove a project that is not in the `projects` array
    error ProjectNotFound();
    /// @notice The error emitted when attempting to calculate voting power for a period with a start block greater than the end block
    error StartMustBeBeforeEnd();
    /// @notice The error emitted when a transfer fails
    error TransferFailed();
    /// @notice The error emitted when a voter has not voted this cycle
    error VoterHasNotVotedThisCycle();
    /// @notice The error emitted when attempting to distribute yield when access conditions are not met
    error YieldNotResolved();
    /// @notice The error emitted if a user with zero points attempts to cast votes
    error ZeroVotePoints();

    /// @notice The event emitted when an account casts a vote
    event BreadHolderVoted(address indexed account, uint256[] points, address[] projects);
    /// @notice The event emitted when a project is added as eligibile for yield distribution
    event ProjectAdded(address project);
    /// @notice The event emitted when a project is removed as eligibile for yield distribution
    event ProjectRemoved(address project);
    /// @notice The event emitted when yield is distributed
    event YieldDistributed(uint256 yield, uint256 totalVotes, uint256[] projectDistributions);
}

// lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol

// OpenZeppelin Contracts (last updated v5.3.0) (proxy/utils/Initializable.sol)

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Storage of the initializable contract.
     *
     * It's implemented on a custom ERC-7201 namespace to reduce the risk of storage collisions
     * when using with upgradeable contracts.
     *
     * @custom:storage-location erc7201:openzeppelin.storage.Initializable
     */
    struct InitializableStorage {
        /**
         * @dev Indicates that the contract has been initialized.
         */
        uint64 _initialized;
        /**
         * @dev Indicates that the contract is in the process of being initialized.
         */
        bool _initializing;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /**
     * @dev The contract is already initialized.
     */
    error InvalidInitialization();

    /**
     * @dev The contract is not initializing.
     */
    error NotInitializing();

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint64 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that in the context of a constructor an `initializer` may be invoked any
     * number of times. This behavior in the constructor can be useful during testing and is not expected to be used in
     * production.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        // Cache values to avoid duplicated sloads
        bool isTopLevelCall = !$._initializing;
        uint64 initialized = $._initialized;

        // Allowed calls:
        // - initialSetup: the contract is not in the initializing state and no previous version was
        //                 initialized
        // - construction: the contract is initialized at version 1 (no reinitialization) and the
        //                 current contract is just being deployed
        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        $._initialized = 1;
        if (isTopLevelCall) {
            $._initializing = true;
        }
        _;
        if (isTopLevelCall) {
            $._initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: Setting the version to 2**64 - 1 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint64 version) {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing || $._initialized >= version) {
            revert InvalidInitialization();
        }
        $._initialized = version;
        $._initializing = true;
        _;
        $._initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    /**
     * @dev Reverts if the contract is not in an initializing state. See {onlyInitializing}.
     */
    function _checkInitializing() internal view virtual {
        if (!_isInitializing()) {
            revert NotInitializing();
        }
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing) {
            revert InvalidInitialization();
        }
        if ($._initialized != type(uint64).max) {
            $._initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint64) {
        return _getInitializableStorage()._initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _getInitializableStorage()._initializing;
    }

    /**
     * @dev Pointer to storage slot. Allows integrators to override it with a custom storage location.
     *
     * NOTE: Consider following the ERC-7201 formula to derive storage locations.
     */
    function _initializableStorageSlot() internal pure virtual returns (bytes32) {
        return INITIALIZABLE_STORAGE;
    }

    /**
     * @dev Returns a pointer to the storage namespace.
     */
    // solhint-disable-next-line var-name-mixedcase
    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        bytes32 slot = _initializableStorageSlot();
        assembly {
            $.slot := slot
        }
    }
}

// src/libraries/MultiplierConstants.sol

library MultiplierConstants {
    /// @notice The base multiplier value (100% in fixed-point representation)
    uint256 public constant BASE_MULTIPLIER = 1e18;
}

// lib/openzeppelin-contracts/contracts/utils/Panic.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/Panic.sol)

/**
 * @dev Helper library for emitting standardized panic codes.
 *
 * ```solidity
 * contract Example {
 *      using Panic for uint256;
 *
 *      // Use any of the declared internal constants
 *      function foo() { Panic.GENERIC.panic(); }
 *
 *      // Alternatively
 *      function foo() { Panic.panic(Panic.GENERIC); }
 * }
 * ```
 *
 * Follows the list from https://github.com/ethereum/solidity/blob/v0.8.24/libsolutil/ErrorCodes.h[libsolutil].
 *
 * _Available since v5.1._
 */
// slither-disable-next-line unused-state
library Panic {
    /// @dev generic / unspecified error
    uint256 internal constant GENERIC = 0x00;
    /// @dev used by the assert() builtin
    uint256 internal constant ASSERT = 0x01;
    /// @dev arithmetic underflow or overflow
    uint256 internal constant UNDER_OVERFLOW = 0x11;
    /// @dev division or modulo by zero
    uint256 internal constant DIVISION_BY_ZERO = 0x12;
    /// @dev enum conversion error
    uint256 internal constant ENUM_CONVERSION_ERROR = 0x21;
    /// @dev invalid encoding in storage
    uint256 internal constant STORAGE_ENCODING_ERROR = 0x22;
    /// @dev empty array pop
    uint256 internal constant EMPTY_ARRAY_POP = 0x31;
    /// @dev array out of bounds access
    uint256 internal constant ARRAY_OUT_OF_BOUNDS = 0x32;
    /// @dev resource error (too large allocation or too large array)
    uint256 internal constant RESOURCE_ERROR = 0x41;
    /// @dev calling invalid internal function
    uint256 internal constant INVALID_INTERNAL_FUNCTION = 0x51;

    /// @dev Reverts with a panic code. Recommended to use with
    /// the internal constants with predefined codes.
    function panic(uint256 code) internal pure {
        assembly ("memory-safe") {
            mstore(0x00, 0x4e487b71)
            mstore(0x20, code)
            revert(0x1c, 0x24)
        }
    }
}

// lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/math/SafeCast.sol)
// This file was procedurally generated from scripts/generate/templates/SafeCast.js.

/**
 * @dev Wrappers over Solidity's uintXX/intXX/bool casting operators with added overflow
 * checks.
 *
 * Downcasting from uint256/int256 in Solidity does not revert on overflow. This can
 * easily result in undesired exploitation or bugs, since developers usually
 * assume that overflows raise errors. `SafeCast` restores this intuition by
 * reverting the transaction when such an operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeCast {
    /**
     * @dev Value doesn't fit in an uint of `bits` size.
     */
    error SafeCastOverflowedUintDowncast(uint8 bits, uint256 value);

    /**
     * @dev An int value doesn't fit in an uint of `bits` size.
     */
    error SafeCastOverflowedIntToUint(int256 value);

    /**
     * @dev Value doesn't fit in an int of `bits` size.
     */
    error SafeCastOverflowedIntDowncast(uint8 bits, int256 value);

    /**
     * @dev An uint value doesn't fit in an int of `bits` size.
     */
    error SafeCastOverflowedUintToInt(uint256 value);

    /**
     * @dev Returns the downcasted uint248 from uint256, reverting on
     * overflow (when the input is greater than largest uint248).
     *
     * Counterpart to Solidity's `uint248` operator.
     *
     * Requirements:
     *
     * - input must fit into 248 bits
     */
    function toUint248(uint256 value) internal pure returns (uint248) {
        if (value > type(uint248).max) {
            revert SafeCastOverflowedUintDowncast(248, value);
        }
        return uint248(value);
    }

    /**
     * @dev Returns the downcasted uint240 from uint256, reverting on
     * overflow (when the input is greater than largest uint240).
     *
     * Counterpart to Solidity's `uint240` operator.
     *
     * Requirements:
     *
     * - input must fit into 240 bits
     */
    function toUint240(uint256 value) internal pure returns (uint240) {
        if (value > type(uint240).max) {
            revert SafeCastOverflowedUintDowncast(240, value);
        }
        return uint240(value);
    }

    /**
     * @dev Returns the downcasted uint232 from uint256, reverting on
     * overflow (when the input is greater than largest uint232).
     *
     * Counterpart to Solidity's `uint232` operator.
     *
     * Requirements:
     *
     * - input must fit into 232 bits
     */
    function toUint232(uint256 value) internal pure returns (uint232) {
        if (value > type(uint232).max) {
            revert SafeCastOverflowedUintDowncast(232, value);
        }
        return uint232(value);
    }

    /**
     * @dev Returns the downcasted uint224 from uint256, reverting on
     * overflow (when the input is greater than largest uint224).
     *
     * Counterpart to Solidity's `uint224` operator.
     *
     * Requirements:
     *
     * - input must fit into 224 bits
     */
    function toUint224(uint256 value) internal pure returns (uint224) {
        if (value > type(uint224).max) {
            revert SafeCastOverflowedUintDowncast(224, value);
        }
        return uint224(value);
    }

    /**
     * @dev Returns the downcasted uint216 from uint256, reverting on
     * overflow (when the input is greater than largest uint216).
     *
     * Counterpart to Solidity's `uint216` operator.
     *
     * Requirements:
     *
     * - input must fit into 216 bits
     */
    function toUint216(uint256 value) internal pure returns (uint216) {
        if (value > type(uint216).max) {
            revert SafeCastOverflowedUintDowncast(216, value);
        }
        return uint216(value);
    }

    /**
     * @dev Returns the downcasted uint208 from uint256, reverting on
     * overflow (when the input is greater than largest uint208).
     *
     * Counterpart to Solidity's `uint208` operator.
     *
     * Requirements:
     *
     * - input must fit into 208 bits
     */
    function toUint208(uint256 value) internal pure returns (uint208) {
        if (value > type(uint208).max) {
            revert SafeCastOverflowedUintDowncast(208, value);
        }
        return uint208(value);
    }

    /**
     * @dev Returns the downcasted uint200 from uint256, reverting on
     * overflow (when the input is greater than largest uint200).
     *
     * Counterpart to Solidity's `uint200` operator.
     *
     * Requirements:
     *
     * - input must fit into 200 bits
     */
    function toUint200(uint256 value) internal pure returns (uint200) {
        if (value > type(uint200).max) {
            revert SafeCastOverflowedUintDowncast(200, value);
        }
        return uint200(value);
    }

    /**
     * @dev Returns the downcasted uint192 from uint256, reverting on
     * overflow (when the input is greater than largest uint192).
     *
     * Counterpart to Solidity's `uint192` operator.
     *
     * Requirements:
     *
     * - input must fit into 192 bits
     */
    function toUint192(uint256 value) internal pure returns (uint192) {
        if (value > type(uint192).max) {
            revert SafeCastOverflowedUintDowncast(192, value);
        }
        return uint192(value);
    }

    /**
     * @dev Returns the downcasted uint184 from uint256, reverting on
     * overflow (when the input is greater than largest uint184).
     *
     * Counterpart to Solidity's `uint184` operator.
     *
     * Requirements:
     *
     * - input must fit into 184 bits
     */
    function toUint184(uint256 value) internal pure returns (uint184) {
        if (value > type(uint184).max) {
            revert SafeCastOverflowedUintDowncast(184, value);
        }
        return uint184(value);
    }

    /**
     * @dev Returns the downcasted uint176 from uint256, reverting on
     * overflow (when the input is greater than largest uint176).
     *
     * Counterpart to Solidity's `uint176` operator.
     *
     * Requirements:
     *
     * - input must fit into 176 bits
     */
    function toUint176(uint256 value) internal pure returns (uint176) {
        if (value > type(uint176).max) {
            revert SafeCastOverflowedUintDowncast(176, value);
        }
        return uint176(value);
    }

    /**
     * @dev Returns the downcasted uint168 from uint256, reverting on
     * overflow (when the input is greater than largest uint168).
     *
     * Counterpart to Solidity's `uint168` operator.
     *
     * Requirements:
     *
     * - input must fit into 168 bits
     */
    function toUint168(uint256 value) internal pure returns (uint168) {
        if (value > type(uint168).max) {
            revert SafeCastOverflowedUintDowncast(168, value);
        }
        return uint168(value);
    }

    /**
     * @dev Returns the downcasted uint160 from uint256, reverting on
     * overflow (when the input is greater than largest uint160).
     *
     * Counterpart to Solidity's `uint160` operator.
     *
     * Requirements:
     *
     * - input must fit into 160 bits
     */
    function toUint160(uint256 value) internal pure returns (uint160) {
        if (value > type(uint160).max) {
            revert SafeCastOverflowedUintDowncast(160, value);
        }
        return uint160(value);
    }

    /**
     * @dev Returns the downcasted uint152 from uint256, reverting on
     * overflow (when the input is greater than largest uint152).
     *
     * Counterpart to Solidity's `uint152` operator.
     *
     * Requirements:
     *
     * - input must fit into 152 bits
     */
    function toUint152(uint256 value) internal pure returns (uint152) {
        if (value > type(uint152).max) {
            revert SafeCastOverflowedUintDowncast(152, value);
        }
        return uint152(value);
    }

    /**
     * @dev Returns the downcasted uint144 from uint256, reverting on
     * overflow (when the input is greater than largest uint144).
     *
     * Counterpart to Solidity's `uint144` operator.
     *
     * Requirements:
     *
     * - input must fit into 144 bits
     */
    function toUint144(uint256 value) internal pure returns (uint144) {
        if (value > type(uint144).max) {
            revert SafeCastOverflowedUintDowncast(144, value);
        }
        return uint144(value);
    }

    /**
     * @dev Returns the downcasted uint136 from uint256, reverting on
     * overflow (when the input is greater than largest uint136).
     *
     * Counterpart to Solidity's `uint136` operator.
     *
     * Requirements:
     *
     * - input must fit into 136 bits
     */
    function toUint136(uint256 value) internal pure returns (uint136) {
        if (value > type(uint136).max) {
            revert SafeCastOverflowedUintDowncast(136, value);
        }
        return uint136(value);
    }

    /**
     * @dev Returns the downcasted uint128 from uint256, reverting on
     * overflow (when the input is greater than largest uint128).
     *
     * Counterpart to Solidity's `uint128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     */
    function toUint128(uint256 value) internal pure returns (uint128) {
        if (value > type(uint128).max) {
            revert SafeCastOverflowedUintDowncast(128, value);
        }
        return uint128(value);
    }

    /**
     * @dev Returns the downcasted uint120 from uint256, reverting on
     * overflow (when the input is greater than largest uint120).
     *
     * Counterpart to Solidity's `uint120` operator.
     *
     * Requirements:
     *
     * - input must fit into 120 bits
     */
    function toUint120(uint256 value) internal pure returns (uint120) {
        if (value > type(uint120).max) {
            revert SafeCastOverflowedUintDowncast(120, value);
        }
        return uint120(value);
    }

    /**
     * @dev Returns the downcasted uint112 from uint256, reverting on
     * overflow (when the input is greater than largest uint112).
     *
     * Counterpart to Solidity's `uint112` operator.
     *
     * Requirements:
     *
     * - input must fit into 112 bits
     */
    function toUint112(uint256 value) internal pure returns (uint112) {
        if (value > type(uint112).max) {
            revert SafeCastOverflowedUintDowncast(112, value);
        }
        return uint112(value);
    }

    /**
     * @dev Returns the downcasted uint104 from uint256, reverting on
     * overflow (when the input is greater than largest uint104).
     *
     * Counterpart to Solidity's `uint104` operator.
     *
     * Requirements:
     *
     * - input must fit into 104 bits
     */
    function toUint104(uint256 value) internal pure returns (uint104) {
        if (value > type(uint104).max) {
            revert SafeCastOverflowedUintDowncast(104, value);
        }
        return uint104(value);
    }

    /**
     * @dev Returns the downcasted uint96 from uint256, reverting on
     * overflow (when the input is greater than largest uint96).
     *
     * Counterpart to Solidity's `uint96` operator.
     *
     * Requirements:
     *
     * - input must fit into 96 bits
     */
    function toUint96(uint256 value) internal pure returns (uint96) {
        if (value > type(uint96).max) {
            revert SafeCastOverflowedUintDowncast(96, value);
        }
        return uint96(value);
    }

    /**
     * @dev Returns the downcasted uint88 from uint256, reverting on
     * overflow (when the input is greater than largest uint88).
     *
     * Counterpart to Solidity's `uint88` operator.
     *
     * Requirements:
     *
     * - input must fit into 88 bits
     */
    function toUint88(uint256 value) internal pure returns (uint88) {
        if (value > type(uint88).max) {
            revert SafeCastOverflowedUintDowncast(88, value);
        }
        return uint88(value);
    }

    /**
     * @dev Returns the downcasted uint80 from uint256, reverting on
     * overflow (when the input is greater than largest uint80).
     *
     * Counterpart to Solidity's `uint80` operator.
     *
     * Requirements:
     *
     * - input must fit into 80 bits
     */
    function toUint80(uint256 value) internal pure returns (uint80) {
        if (value > type(uint80).max) {
            revert SafeCastOverflowedUintDowncast(80, value);
        }
        return uint80(value);
    }

    /**
     * @dev Returns the downcasted uint72 from uint256, reverting on
     * overflow (when the input is greater than largest uint72).
     *
     * Counterpart to Solidity's `uint72` operator.
     *
     * Requirements:
     *
     * - input must fit into 72 bits
     */
    function toUint72(uint256 value) internal pure returns (uint72) {
        if (value > type(uint72).max) {
            revert SafeCastOverflowedUintDowncast(72, value);
        }
        return uint72(value);
    }

    /**
     * @dev Returns the downcasted uint64 from uint256, reverting on
     * overflow (when the input is greater than largest uint64).
     *
     * Counterpart to Solidity's `uint64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     */
    function toUint64(uint256 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert SafeCastOverflowedUintDowncast(64, value);
        }
        return uint64(value);
    }

    /**
     * @dev Returns the downcasted uint56 from uint256, reverting on
     * overflow (when the input is greater than largest uint56).
     *
     * Counterpart to Solidity's `uint56` operator.
     *
     * Requirements:
     *
     * - input must fit into 56 bits
     */
    function toUint56(uint256 value) internal pure returns (uint56) {
        if (value > type(uint56).max) {
            revert SafeCastOverflowedUintDowncast(56, value);
        }
        return uint56(value);
    }

    /**
     * @dev Returns the downcasted uint48 from uint256, reverting on
     * overflow (when the input is greater than largest uint48).
     *
     * Counterpart to Solidity's `uint48` operator.
     *
     * Requirements:
     *
     * - input must fit into 48 bits
     */
    function toUint48(uint256 value) internal pure returns (uint48) {
        if (value > type(uint48).max) {
            revert SafeCastOverflowedUintDowncast(48, value);
        }
        return uint48(value);
    }

    /**
     * @dev Returns the downcasted uint40 from uint256, reverting on
     * overflow (when the input is greater than largest uint40).
     *
     * Counterpart to Solidity's `uint40` operator.
     *
     * Requirements:
     *
     * - input must fit into 40 bits
     */
    function toUint40(uint256 value) internal pure returns (uint40) {
        if (value > type(uint40).max) {
            revert SafeCastOverflowedUintDowncast(40, value);
        }
        return uint40(value);
    }

    /**
     * @dev Returns the downcasted uint32 from uint256, reverting on
     * overflow (when the input is greater than largest uint32).
     *
     * Counterpart to Solidity's `uint32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     */
    function toUint32(uint256 value) internal pure returns (uint32) {
        if (value > type(uint32).max) {
            revert SafeCastOverflowedUintDowncast(32, value);
        }
        return uint32(value);
    }

    /**
     * @dev Returns the downcasted uint24 from uint256, reverting on
     * overflow (when the input is greater than largest uint24).
     *
     * Counterpart to Solidity's `uint24` operator.
     *
     * Requirements:
     *
     * - input must fit into 24 bits
     */
    function toUint24(uint256 value) internal pure returns (uint24) {
        if (value > type(uint24).max) {
            revert SafeCastOverflowedUintDowncast(24, value);
        }
        return uint24(value);
    }

    /**
     * @dev Returns the downcasted uint16 from uint256, reverting on
     * overflow (when the input is greater than largest uint16).
     *
     * Counterpart to Solidity's `uint16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     */
    function toUint16(uint256 value) internal pure returns (uint16) {
        if (value > type(uint16).max) {
            revert SafeCastOverflowedUintDowncast(16, value);
        }
        return uint16(value);
    }

    /**
     * @dev Returns the downcasted uint8 from uint256, reverting on
     * overflow (when the input is greater than largest uint8).
     *
     * Counterpart to Solidity's `uint8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits
     */
    function toUint8(uint256 value) internal pure returns (uint8) {
        if (value > type(uint8).max) {
            revert SafeCastOverflowedUintDowncast(8, value);
        }
        return uint8(value);
    }

    /**
     * @dev Converts a signed int256 into an unsigned uint256.
     *
     * Requirements:
     *
     * - input must be greater than or equal to 0.
     */
    function toUint256(int256 value) internal pure returns (uint256) {
        if (value < 0) {
            revert SafeCastOverflowedIntToUint(value);
        }
        return uint256(value);
    }

    /**
     * @dev Returns the downcasted int248 from int256, reverting on
     * overflow (when the input is less than smallest int248 or
     * greater than largest int248).
     *
     * Counterpart to Solidity's `int248` operator.
     *
     * Requirements:
     *
     * - input must fit into 248 bits
     */
    function toInt248(int256 value) internal pure returns (int248 downcasted) {
        downcasted = int248(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(248, value);
        }
    }

    /**
     * @dev Returns the downcasted int240 from int256, reverting on
     * overflow (when the input is less than smallest int240 or
     * greater than largest int240).
     *
     * Counterpart to Solidity's `int240` operator.
     *
     * Requirements:
     *
     * - input must fit into 240 bits
     */
    function toInt240(int256 value) internal pure returns (int240 downcasted) {
        downcasted = int240(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(240, value);
        }
    }

    /**
     * @dev Returns the downcasted int232 from int256, reverting on
     * overflow (when the input is less than smallest int232 or
     * greater than largest int232).
     *
     * Counterpart to Solidity's `int232` operator.
     *
     * Requirements:
     *
     * - input must fit into 232 bits
     */
    function toInt232(int256 value) internal pure returns (int232 downcasted) {
        downcasted = int232(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(232, value);
        }
    }

    /**
     * @dev Returns the downcasted int224 from int256, reverting on
     * overflow (when the input is less than smallest int224 or
     * greater than largest int224).
     *
     * Counterpart to Solidity's `int224` operator.
     *
     * Requirements:
     *
     * - input must fit into 224 bits
     */
    function toInt224(int256 value) internal pure returns (int224 downcasted) {
        downcasted = int224(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(224, value);
        }
    }

    /**
     * @dev Returns the downcasted int216 from int256, reverting on
     * overflow (when the input is less than smallest int216 or
     * greater than largest int216).
     *
     * Counterpart to Solidity's `int216` operator.
     *
     * Requirements:
     *
     * - input must fit into 216 bits
     */
    function toInt216(int256 value) internal pure returns (int216 downcasted) {
        downcasted = int216(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(216, value);
        }
    }

    /**
     * @dev Returns the downcasted int208 from int256, reverting on
     * overflow (when the input is less than smallest int208 or
     * greater than largest int208).
     *
     * Counterpart to Solidity's `int208` operator.
     *
     * Requirements:
     *
     * - input must fit into 208 bits
     */
    function toInt208(int256 value) internal pure returns (int208 downcasted) {
        downcasted = int208(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(208, value);
        }
    }

    /**
     * @dev Returns the downcasted int200 from int256, reverting on
     * overflow (when the input is less than smallest int200 or
     * greater than largest int200).
     *
     * Counterpart to Solidity's `int200` operator.
     *
     * Requirements:
     *
     * - input must fit into 200 bits
     */
    function toInt200(int256 value) internal pure returns (int200 downcasted) {
        downcasted = int200(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(200, value);
        }
    }

    /**
     * @dev Returns the downcasted int192 from int256, reverting on
     * overflow (when the input is less than smallest int192 or
     * greater than largest int192).
     *
     * Counterpart to Solidity's `int192` operator.
     *
     * Requirements:
     *
     * - input must fit into 192 bits
     */
    function toInt192(int256 value) internal pure returns (int192 downcasted) {
        downcasted = int192(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(192, value);
        }
    }

    /**
     * @dev Returns the downcasted int184 from int256, reverting on
     * overflow (when the input is less than smallest int184 or
     * greater than largest int184).
     *
     * Counterpart to Solidity's `int184` operator.
     *
     * Requirements:
     *
     * - input must fit into 184 bits
     */
    function toInt184(int256 value) internal pure returns (int184 downcasted) {
        downcasted = int184(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(184, value);
        }
    }

    /**
     * @dev Returns the downcasted int176 from int256, reverting on
     * overflow (when the input is less than smallest int176 or
     * greater than largest int176).
     *
     * Counterpart to Solidity's `int176` operator.
     *
     * Requirements:
     *
     * - input must fit into 176 bits
     */
    function toInt176(int256 value) internal pure returns (int176 downcasted) {
        downcasted = int176(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(176, value);
        }
    }

    /**
     * @dev Returns the downcasted int168 from int256, reverting on
     * overflow (when the input is less than smallest int168 or
     * greater than largest int168).
     *
     * Counterpart to Solidity's `int168` operator.
     *
     * Requirements:
     *
     * - input must fit into 168 bits
     */
    function toInt168(int256 value) internal pure returns (int168 downcasted) {
        downcasted = int168(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(168, value);
        }
    }

    /**
     * @dev Returns the downcasted int160 from int256, reverting on
     * overflow (when the input is less than smallest int160 or
     * greater than largest int160).
     *
     * Counterpart to Solidity's `int160` operator.
     *
     * Requirements:
     *
     * - input must fit into 160 bits
     */
    function toInt160(int256 value) internal pure returns (int160 downcasted) {
        downcasted = int160(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(160, value);
        }
    }

    /**
     * @dev Returns the downcasted int152 from int256, reverting on
     * overflow (when the input is less than smallest int152 or
     * greater than largest int152).
     *
     * Counterpart to Solidity's `int152` operator.
     *
     * Requirements:
     *
     * - input must fit into 152 bits
     */
    function toInt152(int256 value) internal pure returns (int152 downcasted) {
        downcasted = int152(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(152, value);
        }
    }

    /**
     * @dev Returns the downcasted int144 from int256, reverting on
     * overflow (when the input is less than smallest int144 or
     * greater than largest int144).
     *
     * Counterpart to Solidity's `int144` operator.
     *
     * Requirements:
     *
     * - input must fit into 144 bits
     */
    function toInt144(int256 value) internal pure returns (int144 downcasted) {
        downcasted = int144(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(144, value);
        }
    }

    /**
     * @dev Returns the downcasted int136 from int256, reverting on
     * overflow (when the input is less than smallest int136 or
     * greater than largest int136).
     *
     * Counterpart to Solidity's `int136` operator.
     *
     * Requirements:
     *
     * - input must fit into 136 bits
     */
    function toInt136(int256 value) internal pure returns (int136 downcasted) {
        downcasted = int136(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(136, value);
        }
    }

    /**
     * @dev Returns the downcasted int128 from int256, reverting on
     * overflow (when the input is less than smallest int128 or
     * greater than largest int128).
     *
     * Counterpart to Solidity's `int128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     */
    function toInt128(int256 value) internal pure returns (int128 downcasted) {
        downcasted = int128(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(128, value);
        }
    }

    /**
     * @dev Returns the downcasted int120 from int256, reverting on
     * overflow (when the input is less than smallest int120 or
     * greater than largest int120).
     *
     * Counterpart to Solidity's `int120` operator.
     *
     * Requirements:
     *
     * - input must fit into 120 bits
     */
    function toInt120(int256 value) internal pure returns (int120 downcasted) {
        downcasted = int120(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(120, value);
        }
    }

    /**
     * @dev Returns the downcasted int112 from int256, reverting on
     * overflow (when the input is less than smallest int112 or
     * greater than largest int112).
     *
     * Counterpart to Solidity's `int112` operator.
     *
     * Requirements:
     *
     * - input must fit into 112 bits
     */
    function toInt112(int256 value) internal pure returns (int112 downcasted) {
        downcasted = int112(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(112, value);
        }
    }

    /**
     * @dev Returns the downcasted int104 from int256, reverting on
     * overflow (when the input is less than smallest int104 or
     * greater than largest int104).
     *
     * Counterpart to Solidity's `int104` operator.
     *
     * Requirements:
     *
     * - input must fit into 104 bits
     */
    function toInt104(int256 value) internal pure returns (int104 downcasted) {
        downcasted = int104(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(104, value);
        }
    }

    /**
     * @dev Returns the downcasted int96 from int256, reverting on
     * overflow (when the input is less than smallest int96 or
     * greater than largest int96).
     *
     * Counterpart to Solidity's `int96` operator.
     *
     * Requirements:
     *
     * - input must fit into 96 bits
     */
    function toInt96(int256 value) internal pure returns (int96 downcasted) {
        downcasted = int96(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(96, value);
        }
    }

    /**
     * @dev Returns the downcasted int88 from int256, reverting on
     * overflow (when the input is less than smallest int88 or
     * greater than largest int88).
     *
     * Counterpart to Solidity's `int88` operator.
     *
     * Requirements:
     *
     * - input must fit into 88 bits
     */
    function toInt88(int256 value) internal pure returns (int88 downcasted) {
        downcasted = int88(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(88, value);
        }
    }

    /**
     * @dev Returns the downcasted int80 from int256, reverting on
     * overflow (when the input is less than smallest int80 or
     * greater than largest int80).
     *
     * Counterpart to Solidity's `int80` operator.
     *
     * Requirements:
     *
     * - input must fit into 80 bits
     */
    function toInt80(int256 value) internal pure returns (int80 downcasted) {
        downcasted = int80(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(80, value);
        }
    }

    /**
     * @dev Returns the downcasted int72 from int256, reverting on
     * overflow (when the input is less than smallest int72 or
     * greater than largest int72).
     *
     * Counterpart to Solidity's `int72` operator.
     *
     * Requirements:
     *
     * - input must fit into 72 bits
     */
    function toInt72(int256 value) internal pure returns (int72 downcasted) {
        downcasted = int72(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(72, value);
        }
    }

    /**
     * @dev Returns the downcasted int64 from int256, reverting on
     * overflow (when the input is less than smallest int64 or
     * greater than largest int64).
     *
     * Counterpart to Solidity's `int64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     */
    function toInt64(int256 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(64, value);
        }
    }

    /**
     * @dev Returns the downcasted int56 from int256, reverting on
     * overflow (when the input is less than smallest int56 or
     * greater than largest int56).
     *
     * Counterpart to Solidity's `int56` operator.
     *
     * Requirements:
     *
     * - input must fit into 56 bits
     */
    function toInt56(int256 value) internal pure returns (int56 downcasted) {
        downcasted = int56(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(56, value);
        }
    }

    /**
     * @dev Returns the downcasted int48 from int256, reverting on
     * overflow (when the input is less than smallest int48 or
     * greater than largest int48).
     *
     * Counterpart to Solidity's `int48` operator.
     *
     * Requirements:
     *
     * - input must fit into 48 bits
     */
    function toInt48(int256 value) internal pure returns (int48 downcasted) {
        downcasted = int48(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(48, value);
        }
    }

    /**
     * @dev Returns the downcasted int40 from int256, reverting on
     * overflow (when the input is less than smallest int40 or
     * greater than largest int40).
     *
     * Counterpart to Solidity's `int40` operator.
     *
     * Requirements:
     *
     * - input must fit into 40 bits
     */
    function toInt40(int256 value) internal pure returns (int40 downcasted) {
        downcasted = int40(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(40, value);
        }
    }

    /**
     * @dev Returns the downcasted int32 from int256, reverting on
     * overflow (when the input is less than smallest int32 or
     * greater than largest int32).
     *
     * Counterpart to Solidity's `int32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     */
    function toInt32(int256 value) internal pure returns (int32 downcasted) {
        downcasted = int32(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(32, value);
        }
    }

    /**
     * @dev Returns the downcasted int24 from int256, reverting on
     * overflow (when the input is less than smallest int24 or
     * greater than largest int24).
     *
     * Counterpart to Solidity's `int24` operator.
     *
     * Requirements:
     *
     * - input must fit into 24 bits
     */
    function toInt24(int256 value) internal pure returns (int24 downcasted) {
        downcasted = int24(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(24, value);
        }
    }

    /**
     * @dev Returns the downcasted int16 from int256, reverting on
     * overflow (when the input is less than smallest int16 or
     * greater than largest int16).
     *
     * Counterpart to Solidity's `int16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     */
    function toInt16(int256 value) internal pure returns (int16 downcasted) {
        downcasted = int16(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(16, value);
        }
    }

    /**
     * @dev Returns the downcasted int8 from int256, reverting on
     * overflow (when the input is less than smallest int8 or
     * greater than largest int8).
     *
     * Counterpart to Solidity's `int8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits
     */
    function toInt8(int256 value) internal pure returns (int8 downcasted) {
        downcasted = int8(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(8, value);
        }
    }

    /**
     * @dev Converts an unsigned uint256 into a signed int256.
     *
     * Requirements:
     *
     * - input must be less than or equal to maxInt256.
     */
    function toInt256(uint256 value) internal pure returns (int256) {
        // Note: Unsafe cast below is okay because `type(int256).max` is guaranteed to be positive
        if (value > uint256(type(int256).max)) {
            revert SafeCastOverflowedUintToInt(value);
        }
        return int256(value);
    }

    /**
     * @dev Cast a boolean (false or true) to a uint256 (0 or 1) with no jump.
     */
    function toUint(bool b) internal pure returns (uint256 u) {
        assembly ("memory-safe") {
            u := iszero(iszero(b))
        }
    }
}

// lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// src/interfaces/IVotingMultipliers.sol

/// @title IVotingMultipliers
/// @notice Interface for the VotingMultipliers contract
/// @dev This interface defines the structure and functions for managing voting multipliers
interface IVotingMultipliers {
    /// @notice Thrown when attempting to add a multiplier that is already allowlisted
    error MultiplierAlreadyAllowlisted();
    /// @notice Thrown when attempting to remove a multiplier that is not allowlisted
    error MultiplierNotAllowlisted();
    /// @notice Thrown when an invalid multiplier index is provided
    error InvalidMultiplierIndex();

    /// @notice Emitted when a new multiplier is added to the allowlist
    /// @param multiplier The address of the added multiplier
    event MultiplierAdded(IMultiplier indexed multiplier);
    /// @notice Emitted when a multiplier is removed from the allowlist
    /// @param multiplier The address of the removed multiplier
    event MultiplierRemoved(IMultiplier indexed multiplier);

    /// @notice Returns the multiplier at the specified index in the allowlist
    /// @param index The index of the multiplier in the allowlist
    /// @return The multiplier contract at the specified index
    function allowlistedMultipliers(uint256 index) external view returns (IMultiplier);
    /// @notice Returns the array of allowlisted multipliers
    /// @return IMultiplier[] The array of allowlisted multiplier contracts
    function allowlistedMultipliers() external view returns (IMultiplier[] memory);
    /// @notice Calculates the total multiplier for a given _user
    /// @param __user The address of the _user
    /// @return The total multiplier value for the _user
    function getTotalMultipliers(address __user) external view returns (uint256);
    /// @notice Adds a multiplier to the allowlist
    /// @param _multiplier The multiplier contract to be added
    function addMultiplier(IMultiplier _multiplier) external;
    /// @notice Removes a multiplier from the allowlist
    /// @param _multiplier The multiplier contract to be removed
    function removeMultiplier(IMultiplier _multiplier) external;
}

// lib/openzeppelin-contracts/contracts/utils/math/Math.sol

// OpenZeppelin Contracts (last updated v5.5.0) (utils/math/Math.sol)

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math_1 {
    enum Rounding {
        Floor, // Toward negative infinity
        Ceil, // Toward positive infinity
        Trunc, // Toward zero
        Expand // Away from zero
    }

    /**
     * @dev Return the 512-bit addition of two uint256.
     *
     * The result is stored in two 256 variables such that sum = high * 2²⁵⁶ + low.
     */
    function add512(uint256 a, uint256 b) internal pure returns (uint256 high, uint256 low) {
        assembly ("memory-safe") {
            low := add(a, b)
            high := lt(low, a)
        }
    }

    /**
     * @dev Return the 512-bit multiplication of two uint256.
     *
     * The result is stored in two 256 variables such that product = high * 2²⁵⁶ + low.
     */
    function mul512(uint256 a, uint256 b) internal pure returns (uint256 high, uint256 low) {
        // 512-bit multiply [high low] = x * y. Compute the product mod 2²⁵⁶ and mod 2²⁵⁶ - 1, then use
        // the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
        // variables such that product = high * 2²⁵⁶ + low.
        assembly ("memory-safe") {
            let mm := mulmod(a, b, not(0))
            low := mul(a, b)
            high := sub(sub(mm, low), lt(mm, low))
        }
    }

    /**
     * @dev Returns the addition of two unsigned integers, with a success flag (no overflow).
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            uint256 c = a + b;
            success = c >= a;
            result = c * SafeCast.toUint(success);
        }
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with a success flag (no overflow).
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            uint256 c = a - b;
            success = c <= a;
            result = c * SafeCast.toUint(success);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with a success flag (no overflow).
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            uint256 c = a * b;
            assembly ("memory-safe") {
                // Only true when the multiplication doesn't overflow
                // (c / a == b) || (a == 0)
                success := or(eq(div(c, a), b), iszero(a))
            }
            // equivalent to: success ? c : 0
            result = c * SafeCast.toUint(success);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a success flag (no division by zero).
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            success = b > 0;
            assembly ("memory-safe") {
                // The `DIV` opcode returns zero when the denominator is 0.
                result := div(a, b)
            }
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a success flag (no division by zero).
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            success = b > 0;
            assembly ("memory-safe") {
                // The `MOD` opcode returns zero when the denominator is 0.
                result := mod(a, b)
            }
        }
    }

    /**
     * @dev Unsigned saturating addition, bounds to `2²⁵⁶ - 1` instead of overflowing.
     */
    function saturatingAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        (bool success, uint256 result) = tryAdd(a, b);
        return ternary(success, result, type(uint256).max);
    }

    /**
     * @dev Unsigned saturating subtraction, bounds to zero instead of overflowing.
     */
    function saturatingSub(uint256 a, uint256 b) internal pure returns (uint256) {
        (, uint256 result) = trySub(a, b);
        return result;
    }

    /**
     * @dev Unsigned saturating multiplication, bounds to `2²⁵⁶ - 1` instead of overflowing.
     */
    function saturatingMul(uint256 a, uint256 b) internal pure returns (uint256) {
        (bool success, uint256 result) = tryMul(a, b);
        return ternary(success, result, type(uint256).max);
    }

    /**
     * @dev Branchless ternary evaluation for `condition ? a : b`. Gas costs are constant.
     *
     * IMPORTANT: This function may reduce bytecode size and consume less gas when used standalone.
     * However, the compiler may optimize Solidity ternary operations (i.e. `condition ? a : b`) to only compute
     * one branch when needed, making this function more expensive.
     */
    function ternary(bool condition, uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            // branchless ternary works because:
            // b ^ (a ^ b) == a
            // b ^ 0 == b
            return b ^ ((a ^ b) * SafeCast.toUint(condition));
        }
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return ternary(a > b, a, b);
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return ternary(a < b, a, b);
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds towards infinity instead
     * of rounding towards zero.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            // Guarantee the same behavior as in a regular Solidity division.
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }

        // The following calculation ensures accurate ceiling division without overflow.
        // Since a is non-zero, (a - 1) / b will not overflow.
        // The largest possible result occurs when (a - 1) / b is type(uint256).max,
        // but the largest value we can obtain is type(uint256).max - 1, which happens
        // when a = type(uint256).max and b = 1.
        unchecked {
            return SafeCast.toUint(a > 0) * ((a - 1) / b + 1);
        }
    }

    /**
     * @dev Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or
     * denominator == 0.
     *
     * Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv) with further edits by
     * Uniswap Labs also under MIT license.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            (uint256 high, uint256 low) = mul512(x, y);

            // Handle non-overflow cases, 256 by 256 division.
            if (high == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return low / denominator;
            }

            // Make sure the result is less than 2²⁵⁶. Also prevents denominator == 0.
            if (denominator <= high) {
                Panic.panic(ternary(denominator == 0, Panic.DIVISION_BY_ZERO, Panic.UNDER_OVERFLOW));
            }

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [high low].
            uint256 remainder;
            assembly ("memory-safe") {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                high := sub(high, gt(remainder, low))
                low := sub(low, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator.
            // Always >= 1. See https://cs.stackexchange.com/q/138556/92363.

            uint256 twos = denominator & (0 - denominator);
            assembly ("memory-safe") {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [high low] by twos.
                low := div(low, twos)

                // Flip twos such that it is 2²⁵⁶ / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from high into low.
            low |= high * twos;

            // Invert denominator mod 2²⁵⁶. Now that denominator is an odd number, it has an inverse modulo 2²⁵⁶ such
            // that denominator * inv ≡ 1 mod 2²⁵⁶. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv ≡ 1 mod 2⁴.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also
            // works in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2⁸
            inverse *= 2 - denominator * inverse; // inverse mod 2¹⁶
            inverse *= 2 - denominator * inverse; // inverse mod 2³²
            inverse *= 2 - denominator * inverse; // inverse mod 2⁶⁴
            inverse *= 2 - denominator * inverse; // inverse mod 2¹²⁸
            inverse *= 2 - denominator * inverse; // inverse mod 2²⁵⁶

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2²⁵⁶. Since the preconditions guarantee that the outcome is
            // less than 2²⁵⁶, this is the final result. We don't need to compute the high bits of the result and high
            // is no longer required.
            result = low * inverse;
            return result;
        }
    }

    /**
     * @dev Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        return mulDiv(x, y, denominator) + SafeCast.toUint(unsignedRoundsUp(rounding) && mulmod(x, y, denominator) > 0);
    }

    /**
     * @dev Calculates floor(x * y >> n) with full precision. Throws if result overflows a uint256.
     */
    function mulShr(uint256 x, uint256 y, uint8 n) internal pure returns (uint256 result) {
        unchecked {
            (uint256 high, uint256 low) = mul512(x, y);
            if (high >= 1 << n) {
                Panic.panic(Panic.UNDER_OVERFLOW);
            }
            return (high << (256 - n)) | (low >> n);
        }
    }

    /**
     * @dev Calculates x * y >> n with full precision, following the selected rounding direction.
     */
    function mulShr(uint256 x, uint256 y, uint8 n, Rounding rounding) internal pure returns (uint256) {
        return mulShr(x, y, n) + SafeCast.toUint(unsignedRoundsUp(rounding) && mulmod(x, y, 1 << n) > 0);
    }

    /**
     * @dev Calculate the modular multiplicative inverse of a number in Z/nZ.
     *
     * If n is a prime, then Z/nZ is a field. In that case all elements are inversible, except 0.
     * If n is not a prime, then Z/nZ is not a field, and some elements might not be inversible.
     *
     * If the input value is not inversible, 0 is returned.
     *
     * NOTE: If you know for sure that n is (big) a prime, it may be cheaper to use Fermat's little theorem and get the
     * inverse using `Math.modExp(a, n - 2, n)`. See {invModPrime}.
     */
    function invMod(uint256 a, uint256 n) internal pure returns (uint256) {
        unchecked {
            if (n == 0) return 0;

            // The inverse modulo is calculated using the Extended Euclidean Algorithm (iterative version)
            // Used to compute integers x and y such that: ax + ny = gcd(a, n).
            // When the gcd is 1, then the inverse of a modulo n exists and it's x.
            // ax + ny = 1
            // ax = 1 + (-y)n
            // ax ≡ 1 (mod n) # x is the inverse of a modulo n

            // If the remainder is 0 the gcd is n right away.
            uint256 remainder = a % n;
            uint256 gcd = n;

            // Therefore the initial coefficients are:
            // ax + ny = gcd(a, n) = n
            // 0a + 1n = n
            int256 x = 0;
            int256 y = 1;

            while (remainder != 0) {
                uint256 quotient = gcd / remainder;

                (gcd, remainder) = (
                    // The old remainder is the next gcd to try.
                    remainder,
                    // Compute the next remainder.
                    // Can't overflow given that (a % gcd) * (gcd // (a % gcd)) <= gcd
                    // where gcd is at most n (capped to type(uint256).max)
                    gcd - remainder * quotient
                );

                (x, y) = (
                    // Increment the coefficient of a.
                    y,
                    // Decrement the coefficient of n.
                    // Can overflow, but the result is casted to uint256 so that the
                    // next value of y is "wrapped around" to a value between 0 and n - 1.
                    x - y * int256(quotient)
                );
            }

            if (gcd != 1) return 0; // No inverse exists.
            return ternary(x < 0, n - uint256(-x), uint256(x)); // Wrap the result if it's negative.
        }
    }

    /**
     * @dev Variant of {invMod}. More efficient, but only works if `p` is known to be a prime greater than `2`.
     *
     * From https://en.wikipedia.org/wiki/Fermat%27s_little_theorem[Fermat's little theorem], we know that if p is
     * prime, then `a**(p-1) ≡ 1 mod p`. As a consequence, we have `a * a**(p-2) ≡ 1 mod p`, which means that
     * `a**(p-2)` is the modular multiplicative inverse of a in Fp.
     *
     * NOTE: this function does NOT check that `p` is a prime greater than `2`.
     */
    function invModPrime(uint256 a, uint256 p) internal view returns (uint256) {
        unchecked {
            return Math_1.modExp(a, p - 2, p);
        }
    }

    /**
     * @dev Returns the modular exponentiation of the specified base, exponent and modulus (b ** e % m)
     *
     * Requirements:
     * - modulus can't be zero
     * - underlying staticcall to precompile must succeed
     *
     * IMPORTANT: The result is only valid if the underlying call succeeds. When using this function, make
     * sure the chain you're using it on supports the precompiled contract for modular exponentiation
     * at address 0x05 as specified in https://eips.ethereum.org/EIPS/eip-198[EIP-198]. Otherwise,
     * the underlying function will succeed given the lack of a revert, but the result may be incorrectly
     * interpreted as 0.
     */
    function modExp(uint256 b, uint256 e, uint256 m) internal view returns (uint256) {
        (bool success, uint256 result) = tryModExp(b, e, m);
        if (!success) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }
        return result;
    }

    /**
     * @dev Returns the modular exponentiation of the specified base, exponent and modulus (b ** e % m).
     * It includes a success flag indicating if the operation succeeded. Operation will be marked as failed if trying
     * to operate modulo 0 or if the underlying precompile reverted.
     *
     * IMPORTANT: The result is only valid if the success flag is true. When using this function, make sure the chain
     * you're using it on supports the precompiled contract for modular exponentiation at address 0x05 as specified in
     * https://eips.ethereum.org/EIPS/eip-198[EIP-198]. Otherwise, the underlying function will succeed given the lack
     * of a revert, but the result may be incorrectly interpreted as 0.
     */
    function tryModExp(uint256 b, uint256 e, uint256 m) internal view returns (bool success, uint256 result) {
        if (m == 0) return (false, 0);
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            // | Offset    | Content    | Content (Hex)                                                      |
            // |-----------|------------|--------------------------------------------------------------------|
            // | 0x00:0x1f | size of b  | 0x0000000000000000000000000000000000000000000000000000000000000020 |
            // | 0x20:0x3f | size of e  | 0x0000000000000000000000000000000000000000000000000000000000000020 |
            // | 0x40:0x5f | size of m  | 0x0000000000000000000000000000000000000000000000000000000000000020 |
            // | 0x60:0x7f | value of b | 0x<.............................................................b> |
            // | 0x80:0x9f | value of e | 0x<.............................................................e> |
            // | 0xa0:0xbf | value of m | 0x<.............................................................m> |
            mstore(ptr, 0x20)
            mstore(add(ptr, 0x20), 0x20)
            mstore(add(ptr, 0x40), 0x20)
            mstore(add(ptr, 0x60), b)
            mstore(add(ptr, 0x80), e)
            mstore(add(ptr, 0xa0), m)

            // Given the result < m, it's guaranteed to fit in 32 bytes,
            // so we can use the memory scratch space located at offset 0.
            success := staticcall(gas(), 0x05, ptr, 0xc0, 0x00, 0x20)
            result := mload(0x00)
        }
    }

    /**
     * @dev Variant of {modExp} that supports inputs of arbitrary length.
     */
    function modExp(bytes memory b, bytes memory e, bytes memory m) internal view returns (bytes memory) {
        (bool success, bytes memory result) = tryModExp(b, e, m);
        if (!success) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }
        return result;
    }

    /**
     * @dev Variant of {tryModExp} that supports inputs of arbitrary length.
     */
    function tryModExp(
        bytes memory b,
        bytes memory e,
        bytes memory m
    ) internal view returns (bool success, bytes memory result) {
        if (_zeroBytes(m)) return (false, new bytes(0));

        uint256 mLen = m.length;

        // Encode call args in result and move the free memory pointer
        result = abi.encodePacked(b.length, e.length, mLen, b, e, m);

        assembly ("memory-safe") {
            let dataPtr := add(result, 0x20)
            // Write result on top of args to avoid allocating extra memory.
            success := staticcall(gas(), 0x05, dataPtr, mload(result), dataPtr, mLen)
            // Overwrite the length.
            // result.length > returndatasize() is guaranteed because returndatasize() == m.length
            mstore(result, mLen)
            // Set the memory pointer after the returned data.
            mstore(0x40, add(dataPtr, mLen))
        }
    }

    /**
     * @dev Returns whether the provided byte array is zero.
     */
    function _zeroBytes(bytes memory byteArray) private pure returns (bool) {
        for (uint256 i = 0; i < byteArray.length; ++i) {
            if (byteArray[i] != 0) {
                return false;
            }
        }
        return true;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded
     * towards zero.
     *
     * This method is based on Newton's method for computing square roots; the algorithm is restricted to only
     * using integer operations.
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        unchecked {
            // Take care of easy edge cases when a == 0 or a == 1
            if (a <= 1) {
                return a;
            }

            // In this function, we use Newton's method to get a root of `f(x) := x² - a`. It involves building a
            // sequence x_n that converges toward sqrt(a). For each iteration x_n, we also define the error between
            // the current value as `ε_n = | x_n - sqrt(a) |`.
            //
            // For our first estimation, we consider `e` the smallest power of 2 which is bigger than the square root
            // of the target. (i.e. `2**(e-1) ≤ sqrt(a) < 2**e`). We know that `e ≤ 128` because `(2¹²⁸)² = 2²⁵⁶` is
            // bigger than any uint256.
            //
            // By noticing that
            // `2**(e-1) ≤ sqrt(a) < 2**e → (2**(e-1))² ≤ a < (2**e)² → 2**(2*e-2) ≤ a < 2**(2*e)`
            // we can deduce that `e - 1` is `log2(a) / 2`. We can thus compute `x_n = 2**(e-1)` using a method similar
            // to the msb function.
            uint256 aa = a;
            uint256 xn = 1;

            if (aa >= (1 << 128)) {
                aa >>= 128;
                xn <<= 64;
            }
            if (aa >= (1 << 64)) {
                aa >>= 64;
                xn <<= 32;
            }
            if (aa >= (1 << 32)) {
                aa >>= 32;
                xn <<= 16;
            }
            if (aa >= (1 << 16)) {
                aa >>= 16;
                xn <<= 8;
            }
            if (aa >= (1 << 8)) {
                aa >>= 8;
                xn <<= 4;
            }
            if (aa >= (1 << 4)) {
                aa >>= 4;
                xn <<= 2;
            }
            if (aa >= (1 << 2)) {
                xn <<= 1;
            }

            // We now have x_n such that `x_n = 2**(e-1) ≤ sqrt(a) < 2**e = 2 * x_n`. This implies ε_n ≤ 2**(e-1).
            //
            // We can refine our estimation by noticing that the middle of that interval minimizes the error.
            // If we move x_n to equal 2**(e-1) + 2**(e-2), then we reduce the error to ε_n ≤ 2**(e-2).
            // This is going to be our x_0 (and ε_0)
            xn = (3 * xn) >> 1; // ε_0 := | x_0 - sqrt(a) | ≤ 2**(e-2)

            // From here, Newton's method give us:
            // x_{n+1} = (x_n + a / x_n) / 2
            //
            // One should note that:
            // x_{n+1}² - a = ((x_n + a / x_n) / 2)² - a
            //              = ((x_n² + a) / (2 * x_n))² - a
            //              = (x_n⁴ + 2 * a * x_n² + a²) / (4 * x_n²) - a
            //              = (x_n⁴ + 2 * a * x_n² + a² - 4 * a * x_n²) / (4 * x_n²)
            //              = (x_n⁴ - 2 * a * x_n² + a²) / (4 * x_n²)
            //              = (x_n² - a)² / (2 * x_n)²
            //              = ((x_n² - a) / (2 * x_n))²
            //              ≥ 0
            // Which proves that for all n ≥ 1, sqrt(a) ≤ x_n
            //
            // This gives us the proof of quadratic convergence of the sequence:
            // ε_{n+1} = | x_{n+1} - sqrt(a) |
            //         = | (x_n + a / x_n) / 2 - sqrt(a) |
            //         = | (x_n² + a - 2*x_n*sqrt(a)) / (2 * x_n) |
            //         = | (x_n - sqrt(a))² / (2 * x_n) |
            //         = | ε_n² / (2 * x_n) |
            //         = ε_n² / | (2 * x_n) |
            //
            // For the first iteration, we have a special case where x_0 is known:
            // ε_1 = ε_0² / | (2 * x_0) |
            //     ≤ (2**(e-2))² / (2 * (2**(e-1) + 2**(e-2)))
            //     ≤ 2**(2*e-4) / (3 * 2**(e-1))
            //     ≤ 2**(e-3) / 3
            //     ≤ 2**(e-3-log2(3))
            //     ≤ 2**(e-4.5)
            //
            // For the following iterations, we use the fact that, 2**(e-1) ≤ sqrt(a) ≤ x_n:
            // ε_{n+1} = ε_n² / | (2 * x_n) |
            //         ≤ (2**(e-k))² / (2 * 2**(e-1))
            //         ≤ 2**(2*e-2*k) / 2**e
            //         ≤ 2**(e-2*k)
            xn = (xn + a / xn) >> 1; // ε_1 := | x_1 - sqrt(a) | ≤ 2**(e-4.5)  -- special case, see above
            xn = (xn + a / xn) >> 1; // ε_2 := | x_2 - sqrt(a) | ≤ 2**(e-9)    -- general case with k = 4.5
            xn = (xn + a / xn) >> 1; // ε_3 := | x_3 - sqrt(a) | ≤ 2**(e-18)   -- general case with k = 9
            xn = (xn + a / xn) >> 1; // ε_4 := | x_4 - sqrt(a) | ≤ 2**(e-36)   -- general case with k = 18
            xn = (xn + a / xn) >> 1; // ε_5 := | x_5 - sqrt(a) | ≤ 2**(e-72)   -- general case with k = 36
            xn = (xn + a / xn) >> 1; // ε_6 := | x_6 - sqrt(a) | ≤ 2**(e-144)  -- general case with k = 72

            // Because e ≤ 128 (as discussed during the first estimation phase), we know have reached a precision
            // ε_6 ≤ 2**(e-144) < 1. Given we're operating on integers, then we can ensure that xn is now either
            // sqrt(a) or sqrt(a) + 1.
            return xn - SafeCast.toUint(xn > a / xn);
        }
    }

    /**
     * @dev Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + SafeCast.toUint(unsignedRoundsUp(rounding) && result * result < a);
        }
    }

    /**
     * @dev Return the log in base 2 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log2(uint256 x) internal pure returns (uint256 r) {
        // If value has upper 128 bits set, log2 result is at least 128
        r = SafeCast.toUint(x > 0xffffffffffffffffffffffffffffffff) << 7;
        // If upper 64 bits of 128-bit half set, add 64 to result
        r |= SafeCast.toUint((x >> r) > 0xffffffffffffffff) << 6;
        // If upper 32 bits of 64-bit half set, add 32 to result
        r |= SafeCast.toUint((x >> r) > 0xffffffff) << 5;
        // If upper 16 bits of 32-bit half set, add 16 to result
        r |= SafeCast.toUint((x >> r) > 0xffff) << 4;
        // If upper 8 bits of 16-bit half set, add 8 to result
        r |= SafeCast.toUint((x >> r) > 0xff) << 3;
        // If upper 4 bits of 8-bit half set, add 4 to result
        r |= SafeCast.toUint((x >> r) > 0xf) << 2;

        // Shifts value right by the current result and use it as an index into this lookup table:
        //
        // | x (4 bits) |  index  | table[index] = MSB position |
        // |------------|---------|-----------------------------|
        // |    0000    |    0    |        table[0] = 0         |
        // |    0001    |    1    |        table[1] = 0         |
        // |    0010    |    2    |        table[2] = 1         |
        // |    0011    |    3    |        table[3] = 1         |
        // |    0100    |    4    |        table[4] = 2         |
        // |    0101    |    5    |        table[5] = 2         |
        // |    0110    |    6    |        table[6] = 2         |
        // |    0111    |    7    |        table[7] = 2         |
        // |    1000    |    8    |        table[8] = 3         |
        // |    1001    |    9    |        table[9] = 3         |
        // |    1010    |   10    |        table[10] = 3        |
        // |    1011    |   11    |        table[11] = 3        |
        // |    1100    |   12    |        table[12] = 3        |
        // |    1101    |   13    |        table[13] = 3        |
        // |    1110    |   14    |        table[14] = 3        |
        // |    1111    |   15    |        table[15] = 3        |
        //
        // The lookup table is represented as a 32-byte value with the MSB positions for 0-15 in the last 16 bytes.
        assembly ("memory-safe") {
            r := or(r, byte(shr(r, x), 0x0000010102020202030303030303030300000000000000000000000000000000))
        }
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + SafeCast.toUint(unsignedRoundsUp(rounding) && 1 << result < value);
        }
    }

    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + SafeCast.toUint(unsignedRoundsUp(rounding) && 10 ** result < value);
        }
    }

    /**
     * @dev Return the log in base 256 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint256 x) internal pure returns (uint256 r) {
        // If value has upper 128 bits set, log2 result is at least 128
        r = SafeCast.toUint(x > 0xffffffffffffffffffffffffffffffff) << 7;
        // If upper 64 bits of 128-bit half set, add 64 to result
        r |= SafeCast.toUint((x >> r) > 0xffffffffffffffff) << 6;
        // If upper 32 bits of 64-bit half set, add 32 to result
        r |= SafeCast.toUint((x >> r) > 0xffffffff) << 5;
        // If upper 16 bits of 32-bit half set, add 16 to result
        r |= SafeCast.toUint((x >> r) > 0xffff) << 4;
        // Add 1 if upper 8 bits of 16-bit half set, and divide accumulated result by 8
        return (r >> 3) | SafeCast.toUint((x >> r) > 0xff);
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + SafeCast.toUint(unsignedRoundsUp(rounding) && 1 << (result << 3) < value);
        }
    }

    /**
     * @dev Returns whether a provided rounding mode is considered rounding up for unsigned integers.
     */
    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }

    /**
     * @dev Counts the number of leading zero bits in a uint256.
     */
    function clz(uint256 x) internal pure returns (uint256) {
        return ternary(x == 0, 256, 255 - log2(x));
    }
}

// lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.Ownable
    struct OwnableStorage {
        address _owner;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Ownable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OwnableStorageLocation = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;

    function _getOwnableStorage() private pure returns (OwnableStorage storage $) {
        assembly {
            $.slot := OwnableStorageLocation
        }
    }

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    function __Ownable_init(address initialOwner) internal onlyInitializing {
        __Ownable_init_unchained(initialOwner);
    }

    function __Ownable_init_unchained(address initialOwner) internal onlyInitializing {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        OwnableStorage storage $ = _getOwnableStorage();
        address oldOwner = $._owner;
        $._owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// lib/openzeppelin-contracts/contracts/utils/structs/Checkpoints.sol

// OpenZeppelin Contracts (last updated v5.5.0) (utils/structs/Checkpoints.sol)
// This file was procedurally generated from scripts/generate/templates/Checkpoints.js.

/**
 * @dev This library defines the `Trace*` struct, for checkpointing values as they change at different points in
 * time, and later looking up past values by block number. See {Votes} as an example.
 *
 * To create a history of checkpoints define a variable type `Checkpoints.Trace*` in your contract, and store a new
 * checkpoint for the current transaction block using the {push} function.
 */
library Checkpoints {
    /**
     * @dev A value was attempted to be inserted on a past checkpoint.
     */
    error CheckpointUnorderedInsertion();

    struct Trace256 {
        Checkpoint256[] _checkpoints;
    }

    struct Checkpoint256 {
        uint256 _key;
        uint256 _value;
    }

    /**
     * @dev Pushes a (`key`, `value`) pair into a Trace256 so that it is stored as the checkpoint.
     *
     * Returns previous value and new value.
     *
     * IMPORTANT: Never accept `key` as a user input, since an arbitrary `type(uint256).max` key set will disable the
     * library.
     */
    function push(
        Trace256 storage self,
        uint256 key,
        uint256 value
    ) internal returns (uint256 oldValue, uint256 newValue) {
        return _insert(self._checkpoints, key, value);
    }

    /**
     * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
     * there is none.
     */
    function lowerLookup(Trace256 storage self, uint256 key) internal view returns (uint256) {
        uint256 len = self._checkpoints.length;
        uint256 pos = _lowerBinaryLookup(self._checkpoints, key, 0, len);
        return pos == len ? 0 : _unsafeAccess(self._checkpoints, pos)._value;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     */
    function upperLookup(Trace256 storage self, uint256 key) internal view returns (uint256) {
        uint256 len = self._checkpoints.length;
        uint256 pos = _upperBinaryLookup(self._checkpoints, key, 0, len);
        return pos == 0 ? 0 : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     *
     * NOTE: This is a variant of {upperLookup} that is optimized to find "recent" checkpoint (checkpoints with high
     * keys).
     */
    function upperLookupRecent(Trace256 storage self, uint256 key) internal view returns (uint256) {
        uint256 len = self._checkpoints.length;

        uint256 low = 0;
        uint256 high = len;

        if (len > 5) {
            uint256 mid = len - Math_1.sqrt(len);
            if (key < _unsafeAccess(self._checkpoints, mid)._key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        uint256 pos = _upperBinaryLookup(self._checkpoints, key, low, high);

        return pos == 0 ? 0 : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function latest(Trace256 storage self) internal view returns (uint256) {
        uint256 pos = self._checkpoints.length;
        return pos == 0 ? 0 : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
     * in the most recent checkpoint.
     */
    function latestCheckpoint(Trace256 storage self) internal view returns (bool exists, uint256 _key, uint256 _value) {
        uint256 pos = self._checkpoints.length;
        if (pos == 0) {
            return (false, 0, 0);
        } else {
            Checkpoint256 storage ckpt = _unsafeAccess(self._checkpoints, pos - 1);
            return (true, ckpt._key, ckpt._value);
        }
    }

    /**
     * @dev Returns the number of checkpoints.
     */
    function length(Trace256 storage self) internal view returns (uint256) {
        return self._checkpoints.length;
    }

    /**
     * @dev Returns checkpoint at given position.
     */
    function at(Trace256 storage self, uint32 pos) internal view returns (Checkpoint256 memory) {
        return self._checkpoints[pos];
    }

    /**
     * @dev Pushes a (`key`, `value`) pair into an ordered list of checkpoints, either by inserting a new checkpoint,
     * or by updating the last one.
     */
    function _insert(
        Checkpoint256[] storage self,
        uint256 key,
        uint256 value
    ) private returns (uint256 oldValue, uint256 newValue) {
        uint256 pos = self.length;

        if (pos > 0) {
            Checkpoint256 storage last = _unsafeAccess(self, pos - 1);
            uint256 lastKey = last._key;
            uint256 lastValue = last._value;

            // Checkpoint keys must be non-decreasing.
            if (lastKey > key) {
                revert CheckpointUnorderedInsertion();
            }

            // Update or push new checkpoint
            if (lastKey == key) {
                last._value = value;
            } else {
                self.push(Checkpoint256({_key: key, _value: value}));
            }
            return (lastValue, value);
        } else {
            self.push(Checkpoint256({_key: key, _value: value}));
            return (0, value);
        }
    }

    /**
     * @dev Return the index of the first (oldest) checkpoint with key strictly bigger than the search key, or `high`
     * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
     * `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */
    function _upperBinaryLookup(
        Checkpoint256[] storage self,
        uint256 key,
        uint256 low,
        uint256 high
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math_1.average(low, high);
            if (_unsafeAccess(self, mid)._key > key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return high;
    }

    /**
     * @dev Return the index of the first (oldest) checkpoint with key greater or equal than the search key, or `high`
     * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
     * `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */
    function _lowerBinaryLookup(
        Checkpoint256[] storage self,
        uint256 key,
        uint256 low,
        uint256 high
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math_1.average(low, high);
            if (_unsafeAccess(self, mid)._key < key) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return high;
    }

    /**
     * @dev Access an element of the array without performing bounds check. The position is assumed to be within bounds.
     */
    function _unsafeAccess(
        Checkpoint256[] storage self,
        uint256 pos
    ) private pure returns (Checkpoint256 storage result) {
        assembly {
            mstore(0x00, self.slot)
            result.slot := add(keccak256(0x00, 0x20), mul(pos, 2))
        }
    }

    struct Trace224 {
        Checkpoint224[] _checkpoints;
    }

    struct Checkpoint224 {
        uint32 _key;
        uint224 _value;
    }

    /**
     * @dev Pushes a (`key`, `value`) pair into a Trace224 so that it is stored as the checkpoint.
     *
     * Returns previous value and new value.
     *
     * IMPORTANT: Never accept `key` as a user input, since an arbitrary `type(uint32).max` key set will disable the
     * library.
     */
    function push(
        Trace224 storage self,
        uint32 key,
        uint224 value
    ) internal returns (uint224 oldValue, uint224 newValue) {
        return _insert(self._checkpoints, key, value);
    }

    /**
     * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
     * there is none.
     */
    function lowerLookup(Trace224 storage self, uint32 key) internal view returns (uint224) {
        uint256 len = self._checkpoints.length;
        uint256 pos = _lowerBinaryLookup(self._checkpoints, key, 0, len);
        return pos == len ? 0 : _unsafeAccess(self._checkpoints, pos)._value;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     */
    function upperLookup(Trace224 storage self, uint32 key) internal view returns (uint224) {
        uint256 len = self._checkpoints.length;
        uint256 pos = _upperBinaryLookup(self._checkpoints, key, 0, len);
        return pos == 0 ? 0 : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     *
     * NOTE: This is a variant of {upperLookup} that is optimized to find "recent" checkpoint (checkpoints with high
     * keys).
     */
    function upperLookupRecent(Trace224 storage self, uint32 key) internal view returns (uint224) {
        uint256 len = self._checkpoints.length;

        uint256 low = 0;
        uint256 high = len;

        if (len > 5) {
            uint256 mid = len - Math_1.sqrt(len);
            if (key < _unsafeAccess(self._checkpoints, mid)._key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        uint256 pos = _upperBinaryLookup(self._checkpoints, key, low, high);

        return pos == 0 ? 0 : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function latest(Trace224 storage self) internal view returns (uint224) {
        uint256 pos = self._checkpoints.length;
        return pos == 0 ? 0 : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
     * in the most recent checkpoint.
     */
    function latestCheckpoint(Trace224 storage self) internal view returns (bool exists, uint32 _key, uint224 _value) {
        uint256 pos = self._checkpoints.length;
        if (pos == 0) {
            return (false, 0, 0);
        } else {
            Checkpoint224 storage ckpt = _unsafeAccess(self._checkpoints, pos - 1);
            return (true, ckpt._key, ckpt._value);
        }
    }

    /**
     * @dev Returns the number of checkpoints.
     */
    function length(Trace224 storage self) internal view returns (uint256) {
        return self._checkpoints.length;
    }

    /**
     * @dev Returns checkpoint at given position.
     */
    function at(Trace224 storage self, uint32 pos) internal view returns (Checkpoint224 memory) {
        return self._checkpoints[pos];
    }

    /**
     * @dev Pushes a (`key`, `value`) pair into an ordered list of checkpoints, either by inserting a new checkpoint,
     * or by updating the last one.
     */
    function _insert(
        Checkpoint224[] storage self,
        uint32 key,
        uint224 value
    ) private returns (uint224 oldValue, uint224 newValue) {
        uint256 pos = self.length;

        if (pos > 0) {
            Checkpoint224 storage last = _unsafeAccess(self, pos - 1);
            uint32 lastKey = last._key;
            uint224 lastValue = last._value;

            // Checkpoint keys must be non-decreasing.
            if (lastKey > key) {
                revert CheckpointUnorderedInsertion();
            }

            // Update or push new checkpoint
            if (lastKey == key) {
                last._value = value;
            } else {
                self.push(Checkpoint224({_key: key, _value: value}));
            }
            return (lastValue, value);
        } else {
            self.push(Checkpoint224({_key: key, _value: value}));
            return (0, value);
        }
    }

    /**
     * @dev Return the index of the first (oldest) checkpoint with key strictly bigger than the search key, or `high`
     * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
     * `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */
    function _upperBinaryLookup(
        Checkpoint224[] storage self,
        uint32 key,
        uint256 low,
        uint256 high
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math_1.average(low, high);
            if (_unsafeAccess(self, mid)._key > key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return high;
    }

    /**
     * @dev Return the index of the first (oldest) checkpoint with key greater or equal than the search key, or `high`
     * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
     * `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */
    function _lowerBinaryLookup(
        Checkpoint224[] storage self,
        uint32 key,
        uint256 low,
        uint256 high
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math_1.average(low, high);
            if (_unsafeAccess(self, mid)._key < key) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return high;
    }

    /**
     * @dev Access an element of the array without performing bounds check. The position is assumed to be within bounds.
     */
    function _unsafeAccess(
        Checkpoint224[] storage self,
        uint256 pos
    ) private pure returns (Checkpoint224 storage result) {
        assembly {
            mstore(0x00, self.slot)
            result.slot := add(keccak256(0x00, 0x20), pos)
        }
    }

    struct Trace208 {
        Checkpoint208[] _checkpoints;
    }

    struct Checkpoint208 {
        uint48 _key;
        uint208 _value;
    }

    /**
     * @dev Pushes a (`key`, `value`) pair into a Trace208 so that it is stored as the checkpoint.
     *
     * Returns previous value and new value.
     *
     * IMPORTANT: Never accept `key` as a user input, since an arbitrary `type(uint48).max` key set will disable the
     * library.
     */
    function push(
        Trace208 storage self,
        uint48 key,
        uint208 value
    ) internal returns (uint208 oldValue, uint208 newValue) {
        return _insert(self._checkpoints, key, value);
    }

    /**
     * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
     * there is none.
     */
    function lowerLookup(Trace208 storage self, uint48 key) internal view returns (uint208) {
        uint256 len = self._checkpoints.length;
        uint256 pos = _lowerBinaryLookup(self._checkpoints, key, 0, len);
        return pos == len ? 0 : _unsafeAccess(self._checkpoints, pos)._value;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     */
    function upperLookup(Trace208 storage self, uint48 key) internal view returns (uint208) {
        uint256 len = self._checkpoints.length;
        uint256 pos = _upperBinaryLookup(self._checkpoints, key, 0, len);
        return pos == 0 ? 0 : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     *
     * NOTE: This is a variant of {upperLookup} that is optimized to find "recent" checkpoint (checkpoints with high
     * keys).
     */
    function upperLookupRecent(Trace208 storage self, uint48 key) internal view returns (uint208) {
        uint256 len = self._checkpoints.length;

        uint256 low = 0;
        uint256 high = len;

        if (len > 5) {
            uint256 mid = len - Math_1.sqrt(len);
            if (key < _unsafeAccess(self._checkpoints, mid)._key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        uint256 pos = _upperBinaryLookup(self._checkpoints, key, low, high);

        return pos == 0 ? 0 : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function latest(Trace208 storage self) internal view returns (uint208) {
        uint256 pos = self._checkpoints.length;
        return pos == 0 ? 0 : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
     * in the most recent checkpoint.
     */
    function latestCheckpoint(Trace208 storage self) internal view returns (bool exists, uint48 _key, uint208 _value) {
        uint256 pos = self._checkpoints.length;
        if (pos == 0) {
            return (false, 0, 0);
        } else {
            Checkpoint208 storage ckpt = _unsafeAccess(self._checkpoints, pos - 1);
            return (true, ckpt._key, ckpt._value);
        }
    }

    /**
     * @dev Returns the number of checkpoints.
     */
    function length(Trace208 storage self) internal view returns (uint256) {
        return self._checkpoints.length;
    }

    /**
     * @dev Returns checkpoint at given position.
     */
    function at(Trace208 storage self, uint32 pos) internal view returns (Checkpoint208 memory) {
        return self._checkpoints[pos];
    }

    /**
     * @dev Pushes a (`key`, `value`) pair into an ordered list of checkpoints, either by inserting a new checkpoint,
     * or by updating the last one.
     */
    function _insert(
        Checkpoint208[] storage self,
        uint48 key,
        uint208 value
    ) private returns (uint208 oldValue, uint208 newValue) {
        uint256 pos = self.length;

        if (pos > 0) {
            Checkpoint208 storage last = _unsafeAccess(self, pos - 1);
            uint48 lastKey = last._key;
            uint208 lastValue = last._value;

            // Checkpoint keys must be non-decreasing.
            if (lastKey > key) {
                revert CheckpointUnorderedInsertion();
            }

            // Update or push new checkpoint
            if (lastKey == key) {
                last._value = value;
            } else {
                self.push(Checkpoint208({_key: key, _value: value}));
            }
            return (lastValue, value);
        } else {
            self.push(Checkpoint208({_key: key, _value: value}));
            return (0, value);
        }
    }

    /**
     * @dev Return the index of the first (oldest) checkpoint with key strictly bigger than the search key, or `high`
     * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
     * `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */
    function _upperBinaryLookup(
        Checkpoint208[] storage self,
        uint48 key,
        uint256 low,
        uint256 high
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math_1.average(low, high);
            if (_unsafeAccess(self, mid)._key > key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return high;
    }

    /**
     * @dev Return the index of the first (oldest) checkpoint with key greater or equal than the search key, or `high`
     * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
     * `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */
    function _lowerBinaryLookup(
        Checkpoint208[] storage self,
        uint48 key,
        uint256 low,
        uint256 high
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math_1.average(low, high);
            if (_unsafeAccess(self, mid)._key < key) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return high;
    }

    /**
     * @dev Access an element of the array without performing bounds check. The position is assumed to be within bounds.
     */
    function _unsafeAccess(
        Checkpoint208[] storage self,
        uint256 pos
    ) private pure returns (Checkpoint208 storage result) {
        assembly {
            mstore(0x00, self.slot)
            result.slot := add(keccak256(0x00, 0x20), pos)
        }
    }

    struct Trace160 {
        Checkpoint160[] _checkpoints;
    }

    struct Checkpoint160 {
        uint96 _key;
        uint160 _value;
    }

    /**
     * @dev Pushes a (`key`, `value`) pair into a Trace160 so that it is stored as the checkpoint.
     *
     * Returns previous value and new value.
     *
     * IMPORTANT: Never accept `key` as a user input, since an arbitrary `type(uint96).max` key set will disable the
     * library.
     */
    function push(
        Trace160 storage self,
        uint96 key,
        uint160 value
    ) internal returns (uint160 oldValue, uint160 newValue) {
        return _insert(self._checkpoints, key, value);
    }

    /**
     * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
     * there is none.
     */
    function lowerLookup(Trace160 storage self, uint96 key) internal view returns (uint160) {
        uint256 len = self._checkpoints.length;
        uint256 pos = _lowerBinaryLookup(self._checkpoints, key, 0, len);
        return pos == len ? 0 : _unsafeAccess(self._checkpoints, pos)._value;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     */
    function upperLookup(Trace160 storage self, uint96 key) internal view returns (uint160) {
        uint256 len = self._checkpoints.length;
        uint256 pos = _upperBinaryLookup(self._checkpoints, key, 0, len);
        return pos == 0 ? 0 : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     *
     * NOTE: This is a variant of {upperLookup} that is optimized to find "recent" checkpoint (checkpoints with high
     * keys).
     */
    function upperLookupRecent(Trace160 storage self, uint96 key) internal view returns (uint160) {
        uint256 len = self._checkpoints.length;

        uint256 low = 0;
        uint256 high = len;

        if (len > 5) {
            uint256 mid = len - Math_1.sqrt(len);
            if (key < _unsafeAccess(self._checkpoints, mid)._key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        uint256 pos = _upperBinaryLookup(self._checkpoints, key, low, high);

        return pos == 0 ? 0 : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function latest(Trace160 storage self) internal view returns (uint160) {
        uint256 pos = self._checkpoints.length;
        return pos == 0 ? 0 : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
     * in the most recent checkpoint.
     */
    function latestCheckpoint(Trace160 storage self) internal view returns (bool exists, uint96 _key, uint160 _value) {
        uint256 pos = self._checkpoints.length;
        if (pos == 0) {
            return (false, 0, 0);
        } else {
            Checkpoint160 storage ckpt = _unsafeAccess(self._checkpoints, pos - 1);
            return (true, ckpt._key, ckpt._value);
        }
    }

    /**
     * @dev Returns the number of checkpoints.
     */
    function length(Trace160 storage self) internal view returns (uint256) {
        return self._checkpoints.length;
    }

    /**
     * @dev Returns checkpoint at given position.
     */
    function at(Trace160 storage self, uint32 pos) internal view returns (Checkpoint160 memory) {
        return self._checkpoints[pos];
    }

    /**
     * @dev Pushes a (`key`, `value`) pair into an ordered list of checkpoints, either by inserting a new checkpoint,
     * or by updating the last one.
     */
    function _insert(
        Checkpoint160[] storage self,
        uint96 key,
        uint160 value
    ) private returns (uint160 oldValue, uint160 newValue) {
        uint256 pos = self.length;

        if (pos > 0) {
            Checkpoint160 storage last = _unsafeAccess(self, pos - 1);
            uint96 lastKey = last._key;
            uint160 lastValue = last._value;

            // Checkpoint keys must be non-decreasing.
            if (lastKey > key) {
                revert CheckpointUnorderedInsertion();
            }

            // Update or push new checkpoint
            if (lastKey == key) {
                last._value = value;
            } else {
                self.push(Checkpoint160({_key: key, _value: value}));
            }
            return (lastValue, value);
        } else {
            self.push(Checkpoint160({_key: key, _value: value}));
            return (0, value);
        }
    }

    /**
     * @dev Return the index of the first (oldest) checkpoint with key strictly bigger than the search key, or `high`
     * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
     * `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */
    function _upperBinaryLookup(
        Checkpoint160[] storage self,
        uint96 key,
        uint256 low,
        uint256 high
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math_1.average(low, high);
            if (_unsafeAccess(self, mid)._key > key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return high;
    }

    /**
     * @dev Return the index of the first (oldest) checkpoint with key greater or equal than the search key, or `high`
     * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
     * `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */
    function _lowerBinaryLookup(
        Checkpoint160[] storage self,
        uint96 key,
        uint256 low,
        uint256 high
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math_1.average(low, high);
            if (_unsafeAccess(self, mid)._key < key) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return high;
    }

    /**
     * @dev Access an element of the array without performing bounds check. The position is assumed to be within bounds.
     */
    function _unsafeAccess(
        Checkpoint160[] storage self,
        uint256 pos
    ) private pure returns (Checkpoint160 storage result) {
        assembly {
            mstore(0x00, self.slot)
            result.slot := add(keccak256(0x00, 0x20), pos)
        }
    }
}

// lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.1.0) (access/Ownable2Step.sol)

/**
 * @dev Contract module which provides access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * This extension of the {Ownable} contract includes a two-step mechanism to transfer
 * ownership, where the new owner must call {acceptOwnership} in order to replace the
 * old one. This can help prevent common mistakes, such as transfers of ownership to
 * incorrect accounts, or to contracts that are unable to interact with the
 * permission system.
 *
 * The initial owner is specified at deployment time in the constructor for `Ownable`. This
 * can later be changed with {transferOwnership} and {acceptOwnership}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (Ownable).
 */
abstract contract Ownable2StepUpgradeable is Initializable, OwnableUpgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.Ownable2Step
    struct Ownable2StepStorage {
        address _pendingOwner;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Ownable2Step")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant Ownable2StepStorageLocation = 0x237e158222e3e6968b72b9db0d8043aacf074ad9f650f0d1606b4d82ee432c00;

    function _getOwnable2StepStorage() private pure returns (Ownable2StepStorage storage $) {
        assembly {
            $.slot := Ownable2StepStorageLocation
        }
    }

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    function __Ownable2Step_init() internal onlyInitializing {
    }

    function __Ownable2Step_init_unchained() internal onlyInitializing {
    }
    /**
     * @dev Returns the address of the pending owner.
     */
    function pendingOwner() public view virtual returns (address) {
        Ownable2StepStorage storage $ = _getOwnable2StepStorage();
        return $._pendingOwner;
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     *
     * Setting `newOwner` to the zero address is allowed; this can be used to cancel an initiated ownership transfer.
     */
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        Ownable2StepStorage storage $ = _getOwnable2StepStorage();
        $._pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual override {
        Ownable2StepStorage storage $ = _getOwnable2StepStorage();
        delete $._pendingOwner;
        super._transferOwnership(newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership() public virtual {
        address sender = _msgSender();
        if (pendingOwner() != sender) {
            revert OwnableUnauthorizedAccount(sender);
        }
        _transferOwnership(sender);
    }
}

// src/interfaces/IERC20Votes.sol

interface IERC20Votes is IERC20_1 {
    /**
     * @dev Clock used for flagging checkpoints. Can be overridden to implement timestamp based
     * checkpoints (and voting), in which case {CLOCK_MODE} should be overridden as well to match.
     */
    function clock() external returns (uint48);

    /**
     * @dev Returns the delegate that `account` has chosen.
     */
    function delegates(address account) external view returns (address);

    /**
     * @dev Delegates votes from the sender to `delegatee`.
     */
    function delegate(address delegatee) external;

    /**
     * @dev Delegates votes from signer to `delegatee`.
     */
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @dev Returns the current amount of votes that `account` has.
     */
    function getVotes(address account) external returns (uint256);

    /**
     * @dev Returns the amount of votes that `account` had at a specific moment in the past. If the `clock()` is
     * configured to use block numbers, this will return the value at the end of the corresponding block.
     */
    function getPastVotes(address account, uint256 timepoint) external returns (uint256);

    /**
     * @dev Returns the total supply of votes available at a specific moment in the past. If the `clock()` is
     * configured to use block numbers, this will return the value at the end of the corresponding block.
     */
    function getPastTotalSupply(uint256 timepoint) external returns (uint256);

    /**
     * @dev Get number of checkpoints for `account`.
     */
    function numCheckpoints(address account) external view returns (uint32);

    /**
     * @dev Get the `pos`-th checkpoint for `account`.
     */
    function checkpoints(address account, uint32 pos) external view returns (Checkpoints.Checkpoint208 memory);
}

// src/interfaces/IBread.sol

interface IBread_1 is IBread_0, IERC20Votes {}

// src/VotingMultipliers.sol

/// @title VotingMultipliers
/// @notice A contract for managing voting multipliers
/// @dev Implements IVotingMultipliers interface
contract VotingMultipliers is Ownable2StepUpgradeable, IVotingMultipliers {
    /// @custom:storage-location erc7201:breadchain.VotingMultipliers.storage
    struct VotingMultipliersStorage {
        IMultiplier[] allowlistedMultipliers;
    }

    // keccak256(abi.encode(uint256(keccak256("breadchain.VotingMultipliers.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant VOTING_MULTIPLIERS_STORAGE_LOCATION =
        0xf8ea84bd4d45550952f40e913fd59ad03bae30b4f3dc5a09695fefe1d0465d00;

    /// @notice Initializes the contract
    /// @param _initialOwner The address of the initial owner
    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    function __VotingMultipliers_init(address _initialOwner) internal onlyInitializing {
        if (owner() == address(0)) {
            __Ownable_init(_initialOwner);
        }
    }

    /// @notice Returns the multiplier at the given index
    /// @param index The index of the multiplier
    /// @return multiplier The multiplier at the given index
    function allowlistedMultipliers(uint256 index) external view returns (IMultiplier multiplier) {
        VotingMultipliersStorage storage $ = _getVotingMultipliersStorage();
        return $.allowlistedMultipliers[index];
    }

    /// @notice Returns the array of allowlisted multipliers
    /// @return IMultiplier[] The array of allowlisted multipliers
    function allowlistedMultipliers() external view returns (IMultiplier[] memory) {
        VotingMultipliersStorage storage $ = _getVotingMultipliersStorage();
        return $.allowlistedMultipliers;
    }

    /// @notice Adds a multiplier to the allowlist
    /// @param _multiplier The multiplier contract to be added
    function addMultiplier(IMultiplier _multiplier) external onlyOwner {
        VotingMultipliersStorage storage $ = _getVotingMultipliersStorage();

        // Check if the multiplier is already allowlisted
        for (uint256 i = 0; i < $.allowlistedMultipliers.length; i++) {
            if ($.allowlistedMultipliers[i] == _multiplier) {
                revert MultiplierAlreadyAllowlisted();
            }
        }
        $.allowlistedMultipliers.push(_multiplier);
        emit MultiplierAdded(_multiplier);
    }

    /// @notice Removes a multiplier from the allowlist
    /// @param _multiplier The multiplier contract to be removed
    function removeMultiplier(IMultiplier _multiplier) external onlyOwner {
        VotingMultipliersStorage storage $ = _getVotingMultipliersStorage();

        bool isallowlisted = false;
        for (uint256 i = 0; i < $.allowlistedMultipliers.length; i++) {
            if ($.allowlistedMultipliers[i] == _multiplier) {
                $.allowlistedMultipliers[i] = $.allowlistedMultipliers[$.allowlistedMultipliers.length - 1];
                $.allowlistedMultipliers.pop();
                isallowlisted = true;
                emit MultiplierRemoved(_multiplier);
                break;
            }
        }
        if (!isallowlisted) {
            revert MultiplierNotAllowlisted();
        }
    }

    /// @notice Gets the indexes of valid multipliers for a user
    /// @param _user The address of the user
    /// @return uint256[] Array of valid multiplier indexes
    function getValidMultiplierIndexes(address _user) public view returns (uint256[] memory) {
        VotingMultipliersStorage storage $ = _getVotingMultipliersStorage();

        uint256[] memory validIndexes = new uint256[]($.allowlistedMultipliers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < $.allowlistedMultipliers.length; i++) {
            if (
                block.number <= $.allowlistedMultipliers[i].validUntil(_user)
                    && $.allowlistedMultipliers[i].getMultiplyingFactor(_user) > 0
            ) {
                validIndexes[count] = i;
                count++;
            }
        }

        // Create correctly sized array
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = validIndexes[i];
        }
        return result;
    }

    /// @notice Calculates the total multiplier for a given user using specific multiplier indexes
    /// @notice Performs the updateMultiplyingFactor function for each multiplier to ensure the multiplier is up to date
    /// @param _user The address of the user
    /// @param _multiplierIndexes Array of multiplier indexes to use
    /// @return The total multiplier value for the user
    function calculateTotalMultipliers(address _user, uint256[] calldata _multiplierIndexes) public returns (uint256) {
        VotingMultipliersStorage storage $ = _getVotingMultipliersStorage();

        uint256 _totalMultiplier = MultiplierConstants.BASE_MULTIPLIER;

        for (uint256 i = 0; i < _multiplierIndexes.length; i++) {
            uint256 index = _multiplierIndexes[i];
            if (index >= $.allowlistedMultipliers.length) {
                revert InvalidMultiplierIndex();
            }

            IMultiplier multiplier = $.allowlistedMultipliers[index];
            multiplier.updateMultiplyingFactor(_user);
            if (block.number <= multiplier.validUntil(_user)) {
                uint256 factor = multiplier.getMultiplyingFactor(_user);
                if (factor > MultiplierConstants.BASE_MULTIPLIER) {
                    // Add only the bonus amount to the total
                    _totalMultiplier += (factor - MultiplierConstants.BASE_MULTIPLIER);
                }
            }
        }
        return Math_1.max(_totalMultiplier, MultiplierConstants.BASE_MULTIPLIER);
    }

    /// @notice Calculates the total multiplier for a given user
    /// @param _user The address of the _user
    /// @return The total multiplier value for the _user
    /// @dev This function is intended for frontend and testing purposes
    function getTotalMultipliers(address _user) public view returns (uint256) {
        VotingMultipliersStorage storage $ = _getVotingMultipliersStorage();

        uint256 _totalMultiplier = MultiplierConstants.BASE_MULTIPLIER;
        for (uint256 i = 0; i < $.allowlistedMultipliers.length; i++) {
            IMultiplier multiplier = $.allowlistedMultipliers[i];
            if (block.number <= multiplier.validUntil(_user)) {
                uint256 factor = multiplier.getMultiplyingFactor(_user);
                if (factor > MultiplierConstants.BASE_MULTIPLIER) {
                    // Add only the bonus amount to the total
                    _totalMultiplier += (factor - MultiplierConstants.BASE_MULTIPLIER);
                }
            }
        }
        return Math_1.max(_totalMultiplier, MultiplierConstants.BASE_MULTIPLIER);
    }

    /**
     * @notice Returns a storage pointer to the VotingMultipliers storage struct
     * @dev Internal/private pure helper to retrieve the VotingMultipliersStorage storage location
     * @return $ VotingMultipliersStorage storage pointer
     */
    function _getVotingMultipliersStorage() private pure returns (VotingMultipliersStorage storage $) {
        assembly {
            $.slot := VOTING_MULTIPLIERS_STORAGE_LOCATION
        }
    }
}

// src/YieldDistributor.sol

/**
 * @title Breadchain Yield Distributor
 * @notice Distribute $BREAD yield to eligible member projects based on a voted distribution
 * @author Breadchain Collective
 * @custom:coauthor postcapitalistcrypto.eth
 * @custom:coauthor bagelface.eth
 * @custom:coauthor prosalads.eth
 * @custom:coauthor kassandra.eth
 * @custom:coauthor theblockchainsocialist.eth
 * @custom:coauthor github.com/daopunk
 * @custom:coauthor github.com/secbajor
 * @custom:coauthor github.com/hudsonhrh
 * @custom:coauthor github.com/Tranquil-Flow
 */
contract YieldDistributor is IYieldDistributor, Ownable2StepUpgradeable, VotingMultipliers, GasKillerSDK {
    /// @notice The address of the $BREAD token contract
    IBread_1 public BREAD;
    /// @notice The precision to use for calculations
    uint256 public PRECISION;
    /// @notice The minimum number of blocks between yield distributions
    uint256 public cycleLength;
    /// @notice The maximum number of points a voter can allocate to a project
    uint256 public maxPoints;
    /// @notice The minimum required voting power participants must have to cast a vote
    /// @dev DEPRECATED: Kept for storage layout compatibility.
    /// @custom:oz-renamed-from minRequiredVotingPower
    uint256 internal _deprecated_minRequiredVotingPower;
    /// @notice The block number of the last yield distribution
    uint256 public lastClaimedBlockNumber;
    /// @notice The total voting power accumulated in the current cycle
    uint256 public currentVotes;
    /// @notice Array of projects eligible for yield distribution
    address[] public projects;
    /// @notice Array of projects queued for addition to the next cycle
    address[] public queuedProjectsForAddition;
    /// @notice Array of projects queued for removal from the next cycle
    address[] public queuedProjectsForRemoval;
    /// @notice The voting power allocated to each project by voters in the current cycle
    uint256[] public projectDistributions;
    /// @notice The last block number in which a specified account cast a vote
    mapping(address => uint256) public accountLastVoted;
    /// @notice The voting power allocated to each project by a specific voter in the current cycle
    mapping(address => uint256[]) voterDistributions;
    /// @notice How much of the yield is divided equally among projects
    uint256 public yieldFixedSplitDivisor;
    /// @notice The address of the `ButteredBread` token contract
    IERC20Votes public BUTTERED_BREAD;
    /// @notice The block number before the last yield distribution
    uint256 public previousCycleStartingBlock;
    /// @notice Array of voters who have cast votes in the current cycle
    /// @dev DEPRECATED: Kept for storage layout compatibility. Use `voterAtIndex` and `votersCount` instead.
    /// @custom:oz-renamed-from voters
    address[] internal _deprecated_voters;
    /// @notice The mapping of holders to their vote distributions
    /// @custom:oz-renamed-from holderToDistribution
    mapping(address => uint256[]) internal _holderToDistribution;
    /// @notice The mapping of holders to their total vote distribution
    /// @custom:oz-renamed-from holderToDistributionTotal
    mapping(address => uint256) internal _holderToDistributionTotal;
    /// @notice The current voting cycle number (incremented each distribution)
    uint256 public votingCycle;
    /// @notice The number of voters in the current cycle
    uint256 public votersCount;
    /// @notice Mapping from index to voter address for current cycle
    mapping(uint256 => address) public voterAtIndex;
    /// @notice Mapping from voter address to the cycle they last voted in
    mapping(address => uint256) public voterVotedCycle;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    function initialize(
        address _bread,
        address _butteredBread,
        uint256 _precision,
        uint256 _maxPoints,
        uint256 _cycleLength,
        uint256 _yieldFixedSplitDivisor,
        uint256 _lastClaimedBlockNumber,
        address[] memory _projects,
        address _initialOwner
    ) public initializer {
        if (
            _bread == address(0) || _butteredBread == address(0) || _precision == 0 || _maxPoints == 0
                || _cycleLength == 0 || _yieldFixedSplitDivisor == 0 || _lastClaimedBlockNumber == 0
                || _projects.length == 0 || _initialOwner == address(0)
        ) {
            revert MustBeGreaterThanZero();
        }

        __Ownable_init(_initialOwner);

        BREAD = IBread_1(_bread);
        BUTTERED_BREAD = IERC20Votes(_butteredBread);
        PRECISION = _precision;
        maxPoints = _maxPoints;
        cycleLength = _cycleLength;
        yieldFixedSplitDivisor = _yieldFixedSplitDivisor;
        lastClaimedBlockNumber = _lastClaimedBlockNumber;

        projectDistributions = new uint256[](_projects.length);
        projects = new address[](_projects.length);
        for (uint256 i; i < _projects.length; ++i) {
            projects[i] = _projects[i];
        }

        _initializeVotingCycle(1);
    }

    /**
     * @notice Initializes the VotingMultipliers contract
     * @param _initialOwner The address of the initial owner
     * @custom:oz-upgrades-validate-as-initializer
     * @custom:oz-upgrades-unsafe-allow missing-initializer-call
     * @custom:oz-upgrades-unsafe-allow incorrect-initializer-order
     */
    function initializeVotingMultipliers(address _initialOwner) public reinitializer(1) {
        __VotingMultipliers_init(_initialOwner);
    }

    /**
     * @notice Initializes the GasKiller SDK
     * @param _avsAddress The address of the AVS service manager
     * @param _blsSignatureChecker The address of the BLS signature checker
     * @custom:oz-upgrades-validate-as-initializer
     * @custom:oz-upgrades-unsafe-allow missing-initializer-call
     */
    function initializeGasKiller(address _avsAddress, address _blsSignatureChecker) public reinitializer(2) onlyOwner {
        _setAvsAddress(_avsAddress);
        _setBlsSignatureChecker(_blsSignatureChecker);
    }

    /**
     * @notice Initializes the voting cycle
     * @param _votingCycle The voting cycle number to initialize
     * @custom:oz-upgrades-validate-as-initializer
     * @custom:oz-upgrades-unsafe-allow missing-initializer-call
     */
    function initializeVotingCycle(uint256 _votingCycle) public reinitializer(3) onlyOwner {
        if (_votingCycle == 0) revert MustBeGreaterThanZero();

        if (votingCycle == 0) {
            // Only initialize if voting cycle is not already initialized
            _initializeVotingCycle(_votingCycle);
        }
    }

    /**
     * @notice Returns the distribution of voting power for a specific account
     * @param _account Address of the account to return the distribution for
     * @return uint256[] The distribution of voting power for the account
     */
    function getHolderToDistribution(address _account) public view returns (uint256[] memory) {
        if (voterVotedCycle[_account] != votingCycle) revert VoterHasNotVotedThisCycle();

        return _holderToDistribution[_account];
    }

    /**
     * @notice Returns the total distribution of voting power for a specific account
     * @param _account Address of the account to return the total distribution for
     * @return uint256 The total distribution of voting power for the account
     */
    function getHolderToDistributionTotal(address _account) public view returns (uint256) {
        if (voterVotedCycle[_account] != votingCycle) revert VoterHasNotVotedThisCycle();

        return _holderToDistributionTotal[_account];
    }

    /**
     * @notice Returns the current distribution of voting power for projects
     * @return address[] The current eligible member projects
     * @return uint256[] The current distribution of voting power for projects
     */
    function getCurrentVotingDistribution() public view returns (address[] memory, uint256[] memory) {
        return (projects, projectDistributions);
    }

    /**
     * @notice Returns the list of voters in the current cycle
     * @return address[] Array of voter addresses who have voted in the current cycle
     */
    function getCurrentCycleVoters() public view returns (address[] memory) {
        address[] memory _voters = new address[](votersCount);
        for (uint256 i; i < votersCount; ++i) {
            _voters[i] = voterAtIndex[i];
        }
        return _voters;
    }

    /**
     * @notice Return the current voting power of a user
     * @param _account Address of the user to return the voting power for
     * @return uint256 The voting power of the user
     */
    function getCurrentVotingPower(address _account) public view returns (uint256) {
        return this.getVotingPowerForPeriod(BREAD, previousCycleStartingBlock, lastClaimedBlockNumber, _account)
            + this.getVotingPowerForPeriod(BUTTERED_BREAD, previousCycleStartingBlock, lastClaimedBlockNumber, _account);
    }

    /// @notice Get the current accumulated voting power for a user
    /// @dev This is the voting power that has been accumulated since the last yield distribution
    /// @param _account Address of the user to get the current accumulated voting power for
    /// @return uint256 The current accumulated voting power for the user
    function getCurrentAccumulatedVotingPower(address _account) public view returns (uint256) {
        return this.getVotingPowerForPeriod(BUTTERED_BREAD, lastClaimedBlockNumber, block.number, _account)
            + this.getVotingPowerForPeriod(BREAD, lastClaimedBlockNumber, block.number, _account);
    }

    /**
     * @notice Return the voting power for a specified user during a specified period of time
     * @param _start Start time of the period to return the voting power for
     * @param _end End time of the period to return the voting power for
     * @param _account Address of user to return the voting power for
     * @return uint256 Voting power of the specified user at the specified period of time
     */
    function getVotingPowerForPeriod(IERC20Votes _sourceContract, uint256 _start, uint256 _end, address _account)
        public
        view
        returns (uint256)
    {
        if (_start >= _end) revert StartMustBeBeforeEnd();
        if (_end > block.number) revert EndAfterCurrentBlock();

        /// Initialized as the checkpoint count, but later used to track checkpoint index
        uint32 _numCheckpoints = _sourceContract.numCheckpoints(_account);
        if (_numCheckpoints == 0) return 0;

        /// No voting power if the first checkpoint is after the end of the interval
        Checkpoints.Checkpoint208 memory _currentCheckpoint = _sourceContract.checkpoints(_account, 0);
        if (_currentCheckpoint._key > _end) return 0;

        uint256 _totalVotingPower;

        for (uint32 i = _numCheckpoints; i > 0;) {
            _currentCheckpoint = _sourceContract.checkpoints(_account, --i);

            if (_currentCheckpoint._key <= _end) {
                uint48 _effectiveStart = _currentCheckpoint._key < _start ? uint48(_start) : _currentCheckpoint._key;
                _totalVotingPower += _currentCheckpoint._value * (_end - _effectiveStart);

                if (_effectiveStart == _start) break;
                _end = _currentCheckpoint._key;
            }
        }

        return _totalVotingPower;
    }

    /**
     * @notice Determine if the yield distribution is available
     * @dev Resolver function required for Powerpool job registration. For more details, see the Powerpool documentation:
     * @dev https://docs.powerpool.finance/powerpool-and-poweragent-network/power-agent/user-guides-and-instructions/i-want-to-automate-my-tasks/job-registration-guide#resolver-job
     * @return bool Flag indicating if the yield is able to be distributed
     * @return bytes Calldata used by the resolver to distribute the yield
     */
    function resolveYieldDistribution() public view returns (bool, bytes memory) {
        uint256 _available_yield = BREAD.balanceOf(address(this)) + BREAD.yieldAccrued();
        if (
            /// No votes were cast
            /// OR already claimed this cycle
            /// OR yield is insufficient
            currentVotes == 0 || block.number < lastClaimedBlockNumber + cycleLength
                || _available_yield / yieldFixedSplitDivisor < projects.length
        ) {
            return (false, new bytes(0));
        } else {
            return (true, abi.encodePacked(this.distributeYield.selector));
        }
    }

    /**
     * @notice Claims yield and prepares amounts for distribution
     * @return _balance Total balance available for distribution
     * @return _baseSplit Fixed split amount per project
     * @return _votedYield Amount available for voted distribution
     */
    function _claimAndPrepareYield() internal returns (uint256 _balance, uint256 _baseSplit, uint256 _votedYield) {
        (bool _resolved,) = resolveYieldDistribution();
        if (!_resolved) revert YieldNotResolved();

        BREAD.claimYield(BREAD.yieldAccrued(), address(this));
        previousCycleStartingBlock = lastClaimedBlockNumber;
        lastClaimedBlockNumber = block.number;

        _balance = BREAD.balanceOf(address(this));
        uint256 _fixedYield = _balance / yieldFixedSplitDivisor;
        _baseSplit = _fixedYield / projects.length;
        _votedYield = _balance - _fixedYield;
    }

    /**
     * @notice Execute distribution to projects and finalize with cleanup
     * @param distributions Array of voting power distributions per project
     * @param totalVotes Total voting power
     * @param balance Total balance being distributed
     * @param _baseSplit Fixed split amount per project
     * @param _votedYield Amount available for voted distribution
     */
    function _executeAndFinalizeDistribution(
        uint256[] memory distributions,
        uint256 totalVotes,
        uint256 balance,
        uint256 _baseSplit,
        uint256 _votedYield
    ) internal {
        // Execute transfers to projects
        for (uint256 i; i < projects.length; ++i) {
            uint256 _votedSplit = ((distributions[i] * _votedYield * PRECISION) / totalVotes) / PRECISION;
            bool _success = BREAD.transfer(projects[i], _votedSplit + _baseSplit);
            if (!_success) revert TransferFailed();
        }

        // Finalize with cleanup
        _updateBreadchainProjects();
        emit YieldDistributed(balance, totalVotes, distributions);

        // Gas-efficient reset: increment cycle and reset counter instead of deleting arrays
        votingCycle++;
        votersCount = 0;
        currentVotes = 0;
        projectDistributions = new uint256[](projects.length);
    }

    /**
     * @notice Distribute $BREAD yield to projects using GasKiller voting system
     */
    function distributeYieldGK() public trackState {
        (uint256 _balance, uint256 _baseSplit, uint256 _votedYield) = _claimAndPrepareYield();
        (uint256[] memory _currentProjectDistributions, uint256 _totalVotes) = _computeVotedDistribution();

        _executeAndFinalizeDistribution(_currentProjectDistributions, _totalVotes, _balance, _baseSplit, _votedYield);
    }

    /**
     * @notice Distribute $BREAD yield to projects using gas efficient voting system to avoid OOG errors
     */
    function distributeYield() public trackState {
        (uint256 balance, uint256 _baseSplit, uint256 _votedYield) = _claimAndPrepareYield();

        _executeAndFinalizeDistribution(projectDistributions, currentVotes, balance, _baseSplit, _votedYield);
    }

    /**
     * @notice Cast votes for the distribution of $BREAD yield
     * @param _points List of points as integers for each project
     */
    function castVote(uint256[] calldata _points) public trackState {
        uint256 _currentVotingPower = getCurrentVotingPower(msg.sender);

        _castVote(msg.sender, _points, _currentVotingPower);
    }

    /**
     * @notice Cast votes for the distribution of $BREAD yield with multipliers
     * @param _points List of points as integers for each project
     * @param _multiplierIndices List of indices of multipliers to use for each project
     */
    function castVoteWithMultipliers(uint256[] calldata _points, uint256[] calldata _multiplierIndices)
        public
        trackState
    {
        uint256 _currentVotingPower = getCurrentVotingPower(msg.sender);
        uint256 _multiplier = calculateTotalMultipliers(msg.sender, _multiplierIndices);
        _currentVotingPower = _multiplier == 0 ? _currentVotingPower : (_currentVotingPower * _multiplier) / PRECISION;

        _castVote(msg.sender, _points, _currentVotingPower);
    }

    /**
     * @notice Internal function for casting votes for a specified user
     * @param _account Address of user to cast votes for
     * @param _points Basis points for calculating the amount of votes cast
     * @param _votingPower Amount of voting power being cast
     */
    function _castVote(address _account, uint256[] calldata _points, uint256 _votingPower) internal {
        uint256 _projectsLength = projects.length;
        if (_points.length != _projectsLength) revert IncorrectNumberOfProjects();

        /// Check if voter has voted in current cycle using cycle counter
        bool _hasVotedInCycle = voterVotedCycle[_account] == votingCycle;

        /// Add voter to list if they have not voted this cycle
        if (!_hasVotedInCycle) {
            voterAtIndex[votersCount++] = _account;
            voterVotedCycle[_account] = votingCycle;
        }
        _holderToDistribution[_account] = _points;

        /// Calculate total points
        uint256 _totalPoints;
        for (uint256 i; i < _projectsLength; ++i) {
            if (_points[i] > maxPoints) revert ExceedsMaxPoints();
            _totalPoints += _points[i];
        }
        if (_totalPoints == 0) revert ZeroVotePoints();
        _holderToDistributionTotal[_account] = _totalPoints;
        uint256[] storage _voterDistributions = voterDistributions[_account];
        if (!_hasVotedInCycle) {
            delete voterDistributions[_account];
            currentVotes += _votingPower;
        } else {
            // When recasting, we need to subtract the old voting power and add the new one
            uint256 _previousVotingPower;
            for (uint256 i; i < _projectsLength; ++i) {
                _previousVotingPower += _voterDistributions[i];
            }
            currentVotes = currentVotes - _previousVotingPower + _votingPower;
        }

        for (uint256 i; i < _projectsLength; ++i) {
            uint256 _currentProjectDistribution = ((_points[i] * _votingPower * PRECISION) / _totalPoints) / PRECISION;
            if (!_hasVotedInCycle) {
                projectDistributions[i] += _currentProjectDistribution;
                _voterDistributions.push(_currentProjectDistribution);
            } else {
                // Update projectDistributions with the delta between new and old distributions
                projectDistributions[i] = projectDistributions[i] - _voterDistributions[i] + _currentProjectDistribution;
                _voterDistributions[i] = _currentProjectDistribution;
            }
        }

        accountLastVoted[_account] = block.number;

        emit BreadHolderVoted(_account, _points, projects);
    }

    /**
     * @notice Internal function for computing the voted distributions for projects
     * @return _newProjectDistributions Distribution of votes for projects
     * @return _totalVotes Total number of votes cast
     */
    function _computeVotedDistribution()
        internal
        view
        returns (uint256[] memory _newProjectDistributions, uint256 _totalVotes)
    {
        _newProjectDistributions = new uint256[](projects.length);

        for (uint256 i; i < votersCount; ++i) {
            address _voter = voterAtIndex[i];
            uint256 _voterPower = getCurrentVotingPower(_voter);
            uint256[] memory _voterDistribution = _holderToDistribution[_voter];
            uint256 _vote;
            for (uint256 j; j < projects.length; ++j) {
                _vote =
                    (_voterPower * _voterDistribution[j] * PRECISION / _holderToDistributionTotal[_voter]) / PRECISION;
                _newProjectDistributions[j] += _vote;
                _totalVotes += _vote;
            }
        }
    }

    /**
     * @notice Internal function for updating the project list
     * @dev Bypasses update if there are no additions or removals queued.
     */
    function _updateBreadchainProjects() internal {
        if (queuedProjectsForAddition.length == 0 && queuedProjectsForRemoval.length == 0) {
            // Bypass if nothing to update
            return;
        }

        for (uint256 i; i < queuedProjectsForAddition.length; ++i) {
            address _project = queuedProjectsForAddition[i];
            projects.push(_project);
            emit ProjectAdded(_project);
        }

        address[] memory _oldProjects = projects;
        delete projects;

        for (uint256 i; i < _oldProjects.length; ++i) {
            address _project = _oldProjects[i];
            bool _remove;

            for (uint256 j; j < queuedProjectsForRemoval.length; ++j) {
                if (_project == queuedProjectsForRemoval[j]) {
                    _remove = true;
                    emit ProjectRemoved(_project);
                    break;
                }
            }

            if (!_remove) {
                projects.push(_project);
            }
        }

        delete queuedProjectsForAddition;
        delete queuedProjectsForRemoval;
    }

    /**
     * @notice Internal function to initialize the voting cycle
     * @dev Initialize voting cycle so that uninitialized voterVotedCycle mappings (default 0)
     * @dev are correctly identified as "not voted in current cycle".
     * @dev Resets all in-progress vote state (currentVotes, projectDistributions, votersCount)
     * @dev to prevent double-counting if called mid-cycle during an upgrade.
     */
    function _initializeVotingCycle(uint256 _votingCycle) internal {
        votingCycle = _votingCycle;
        votersCount = 0;
        currentVotes = 0;
        projectDistributions = new uint256[](projects.length);
    }

    /**
     * @notice Queue a new project to be added to the project list
     * @param _project Project to be added to the project list
     */
    function queueProjectAddition(address _project) public onlyOwner trackState {
        for (uint256 i; i < projects.length; ++i) {
            if (projects[i] == _project) {
                revert AlreadyMemberProject();
            }
        }

        for (uint256 i; i < queuedProjectsForAddition.length; ++i) {
            if (queuedProjectsForAddition[i] == _project) {
                revert ProjectAlreadyQueued();
            }
        }

        queuedProjectsForAddition.push(_project);
    }

    /**
     * @notice Queue an existing project to be removed from the project list
     * @param _project Project to be removed from the project list
     */
    function queueProjectRemoval(address _project) public onlyOwner trackState {
        bool _found = false;
        for (uint256 i; i < projects.length; ++i) {
            if (projects[i] == _project) {
                _found = true;
            }
        }

        if (!_found) revert ProjectNotFound();

        for (uint256 i; i < queuedProjectsForRemoval.length; ++i) {
            if (queuedProjectsForRemoval[i] == _project) {
                revert ProjectAlreadyQueued();
            }
        }

        queuedProjectsForRemoval.push(_project);
    }

    /**
     * @notice Set a new maximum number of points a user can allocate to a project
     * @param _maxPoints New maximum number of points a user can allocate to a project
     */
    function setMaxPoints(uint256 _maxPoints) public onlyOwner trackState {
        if (_maxPoints == 0) revert MustBeGreaterThanZero();

        maxPoints = _maxPoints;
    }

    /**
     * @notice Set a new cycle length in blocks
     * @param _cycleLength New cycle length in blocks
     */
    function setCycleLength(uint256 _cycleLength) public onlyOwner trackState {
        if (_cycleLength == 0) revert MustBeGreaterThanZero();

        cycleLength = _cycleLength;
    }

    /**
     * @notice Set a new fixed split for the yield distribution
     * @param _yieldFixedSplitDivisor New fixed split for the yield distribution
     */
    function setYieldFixedSplitDivisor(uint256 _yieldFixedSplitDivisor) public onlyOwner trackState {
        if (_yieldFixedSplitDivisor == 0) revert MustBeGreaterThanZero();

        yieldFixedSplitDivisor = _yieldFixedSplitDivisor;
    }

    /**
     * @notice Set the ButteredBread token contract
     * @param _butteredBread Address of the ButteredBread token contract
     */
    function setButteredBread(address _butteredBread) public onlyOwner trackState {
        BUTTERED_BREAD = IERC20Votes(_butteredBread);
    }

    /**
     * @notice Allows the owner to set the AVS address
     * @param newAvsAddress The new AVS address
     * @dev Also updates the namespace for the contract
     */
    function setAvsAddress(address newAvsAddress) external onlyOwner trackState {
        _setAvsAddress(newAvsAddress);
    }

    /**
     * @notice Allows the owner to set the BLS signature checker address
     * @param newBlsSignatureChecker The new BLS signature checker address
     */
    function setBlsSignatureChecker(address newBlsSignatureChecker) external onlyOwner trackState {
        _setBlsSignatureChecker(newBlsSignatureChecker);
    }

    /**
     * @notice Allows the owner to set the block stale measure
     * @param _blockStaleMeasure The new block stale measure
     */
    function setBlockStaleMeasure(uint256 _blockStaleMeasure) external onlyOwner trackState {
        _setBlockStaleMeasure(_blockStaleMeasure);
    }
}

