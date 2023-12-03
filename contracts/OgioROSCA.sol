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

    function grantUserRole(string memory _groupName, address _userAddress) public {
    require(hasRole(ADMIN_ROLE, msg.sender), "Unauthorized action");

    // Check if the group exists
    require(groupExists(_groupName), "Group does not exist");

    // Access the group object
    ROSCAGroup storage group = groupsByName[_groupName];

    // Add user to the group and grant user role
    group.members.push(_userAddress);
    _grantRole(USER_ROLE, _userAddress);
}

    function hasRole(UserRole role, string memory _groupName, address _userAddress) public view returns (bool) {
    if (role == UserRole.Member) {
        // Access the group object
        ROSCAGroup storage group = groupsByName[_groupName];

        // Check if the user is a member of the group
        address[] storage members = group.members;
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == msg.sender) {
                return true;
            }
        }
        return false;
    } else {
        // Check for admin role using OpenZeppelin method
        return hasRole(ADMIN_ROLE, msg.sender);
    }
    }

    // Function to create a new ROSCA group
    function createROSCAGroup(
        string memory _groupName,
        string memory _description,
        uint256 _contributionAmount,
        uint256 _contributionFrequency,
        uint256 _numberOfMembers,
        uint256 _startDate,
        uint256 _endDate,
        address[] memory _initialMembers // Pass the actual addresses when creating the group
    ) public {
        // Check if the group name already exists
        require(!groupExists(_groupName), "Group name already exists");

        // Create a new ROSCA group struct
        ROSCAGroup memory newGroup;

        // Set the struct properties
        newGroup.groupName = _groupName;
        newGroup.description = _description;
        newGroup.contributionAmount = _contributionAmount;
        newGroup.contributionFrequency = _contributionFrequency;
        newGroup.numberOfMembers = _numberOfMembers;
        newGroup.startDate = _startDate;
        newGroup.endDate = _endDate;

        // Add the group to the list of active groups
        activeGroupNames.push(_groupName);

        // Initialize the roles mapping and members array
        for (uint256 i = 0; i < _numberOfMembers; i++) {
            address member = _initialMembers[i]; // Use actual addresses passed to the function
            newGroup.members.push(member);
            newGroup.roles[member] = UserRole.Member;
        }

        // Add the struct to the activeGroups mapping
        activeGroups[_groupName] = newGroup;

        // Emit the ROSCAGroupCreated event
        emit ROSCAGroupCreated(_groupName);
    }

    // Function to list all active groups
    function listActiveGroups() public view returns (ROSCAGroup[] memory) {
        // Create an empty array to store group information
        ROSCAGroup[] memory activeGroupsList = new ROSCAGroup[](activeGroups.length);

        // Iterate through the activeGroups array and populate the array
        for (uint256 index = 0; index < activeGroups.length; index++) {
            string memory groupName = activeGroups[index];

            // Check if the group is active
            if (isGroupActive(groupName)) {
                ROSCAGroup storage group = activeGroups[groupName];
                activeGroupsList[index] = group;
            }
        }

        // Return the array of group information
        return activeGroupsList;
    }

    // Function to join a ROSCA group and grant the USER role
    function joinROSCAGroup(string memory _groupName) public {
        require(groupExists(_groupName), "Group does not exist");

        // Check if the group is active
        require(isGroupActive(_groupName), "Group is inactive");

        // Check if the group is full
        require(activeGroups[_groupName].members.length < activeGroups[_groupName].numberOfMembers, "Group is full");

        // Add the user to the group's members list
        activeGroups[_groupName].members.push(msg.sender);

        // Grant the USER role to the joined user
        _grantRole(USER_ROLE, msg.sender);

        // Emit an event to notify other parts of the application that a user has joined the ROSCA group
        emit UserJoinedROSCAGroup(_groupName, msg.sender);
    }

     // Implement the ContributeFunds function
    function contributeFunds(string memory _groupName) public payable {
        // Check if the group exists
        require(groupExists(_groupName), "Group does not exist");

        // Check if the group is active
        require(isGroupActive(_groupName), "Group is inactive");

        // Check if the user is a member of the group
        require(activeGroups[_groupName].members.contains(msg.sender), "User is not a member of the group");

        // Check if the contribution amount is valid
        require(msg.value == activeGroups[_groupName].contributionAmount, "Invalid contribution amount");

        // Update the user's contribution amount
        activeGroups[_groupName].contributions[msg.sender] += msg.value;

        // Emit an event to notify other parts of the application that a user has contributed funds to the ROSCA group
        emit UserContributedFunds(_groupName, msg.sender, msg.value);
    }

     // Implement the RandomizeRecipient function
    function randomizeRecipient(string memory _groupName) public {
    // Check if the group exists
    require(groupExists(_groupName), "Group does not exist");

    // Get the list of group members
    address[] memory members = activeGroups[_groupName].members;

    // Generate a random index between 0 and the number of members - 1
    uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp))) % members.length;

    // Select the recipient at the random index
    address recipient = members[randomIndex];

    // Set the current recipient to the selected recipient
    activeGroups[_groupName].currentRecipient = recipient;

    // Emit an event to notify other parts of the application that a recipient has been randomly selected
    emit RecipientSelected(_groupName, recipient);
    }

     // Implement the ReleaseFunds function
    function releaseFunds(string memory _groupName) public {
    // Check if the group exists
    require(groupExists(_groupName), "Group does not exist");

    // Check if the current recipient is valid
    address recipient = activeGroups[_groupName].currentRecipient;
    require(recipient != address(0), "No recipient selected");

    // Call the escrow contract to release funds
    bool success = OgioExcrow(escrowContract).releaseFunds(_groupName, recipient);

    if (success) {
        // Emit event on successful release
        emit FundsReleased(_groupName, recipient, activeGroups[_groupName].contributionAmount);
    } else {
        // Emit event on release failure
        emit ReleaseFailed(_groupName, "Escrow release failed");
    }
    }

    
}