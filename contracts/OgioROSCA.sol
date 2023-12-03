// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./OgioExcrow.sol";

contract OgioROSCA is AccessControl {
    // Define roles
    bytes32 public constant USER_ROLE = keccak256("USER");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

    enum UserRole {
        Member,
        Admin
    }

    constructor() {
        // Set deployer as the initial admin
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

     // Define the ROSCAGroup struct
    struct ROSCAGroup {
        string groupName;
        string description;
        uint256 contributionAmount;
        uint256 contributionFrequency;
        uint256 numberOfMembers;
        address[] members;
        mapping(address => uint256) contributions;
        address currentRecipient;
        mapping(address => UserRole) roles;
        uint256 startDate;
        uint256 endDate;
    }

    // Struct to represent a member in the ROSCA group
    struct Member {
        address memberAddress;
        uint256 contributionAmount;
        uint256 lastContributionDate;
        // Add any other member-related information you need
    }


}