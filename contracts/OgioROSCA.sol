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

     // Declare the activeGroups variable as a state variable
   // string[] public activeGroups;
     // Mapping of group names to ROSCAGroup instances
    mapping(string => ROSCAGroup) public activeGroups;

    // Escrow contract address
    address public escrowContract;
    mapping(string => ROSCAGroup) private groupsByName;
    mapping(string => mapping(address => UserRole)) private groupMemberRoles;
    string[] public activeGroupNames;

    // Declare the ROSCAGroupCreated event
    event ROSCAGroupCreated(string _groupName);
    event UserContributedFunds(string _groupName, address _userAddress, uint256 _amount);
    event RecipientSelected(string _groupName, address _recipientAddress);
    // Events for ReleaseFunds function
    event FundsReleased(string _groupName, address _recipientAddress, uint256 _amount);
    event ReleaseFailed(string _groupName, string _reason);
    // Events for RepayFunds function
    event FundsRepaid(string _groupName, address _userAddress, uint256 _amount);
    event RepayFailed(string _groupName, string _reason);
    // Events for ManageEscrow function
    event EscrowManaged(string _action, string _groupName, address _userAddress);
    // Events for TrackHistory function
    event TransactionTracked(string _groupName, string _type, string _details);
    // Events for VerifyDocumentation function
    event DocumentationVerified(string _groupName, bool _isValid);
    event VerificationFailed(string _groupName, string _reason);
    // Event to notify of updated group details
    event GroupUpdated(string _groupName, string _newDescription, uint256 _newContributionAmount);
    // Event to notify when a user joins a ROSCA group
    event UserJoinedROSCAGroup(string _groupName, address _userAddress);
    // Event to notify when a user is removed from a ROSCA group
    event UserRemoved(string _groupName, address _userAddress);

}