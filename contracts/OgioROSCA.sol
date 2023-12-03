// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./OgioExcrow.sol";

contract OgioROSCA is AccessControl {

    function addressExists(address[] memory addresses, address addr) internal pure returns (bool) {
    for (uint256 i = 0; i < addresses.length; i++) {
        if (addresses[i] == addr) {
            return true;
        }
    }
    return false;
}
    // Define roles
    bytes32 public constant USER_ROLE = keccak256("USER");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

    // Define user roles (adapt based on your needs)
    enum UserRole {
        Member,
        Admin,
        None
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

    // Mapping of group names to ROSCAGroup instances
    mapping(string => ROSCAGroup) private activeGroups;
    string[] private activeGroupNames;

    // Escrow contract address
    address public escrowContract;

    // Declare the ROSCAGroupCreated event
    event ROSCAGroupCreated(string _groupName);
    event UserContributedFunds(string _groupName, address _userAddress, uint256 _amount);
    event RecipientSelected(string _groupName, address _recipientAddress);
    event FundsReleased(string _groupName, address _recipientAddress, uint256 _amount);
    event ReleaseFailed(string _groupName, string _reason);
    event FundsRepaid(string _groupName, address _userAddress, uint256 _amount);
    event RepayFailed(string _groupName, string _reason);
    event EscrowManaged(string _action, string _groupName, address _userAddress);
    event TransactionTracked(string _groupName, string _type, string _details);
    event DocumentationVerified(string _groupName, bool _isValid);
    event VerificationFailed(string _groupName, string _reason);
    event GroupUpdated(string _groupName, string _newDescription, uint256 _newContributionAmount);
    event UserJoinedROSCAGroup(string _groupName, address _userAddress);
    event UserRemoved(string _groupName, address _userAddress);

    function grantUserRole(string memory _groupName, address _userAddress) public {
        require(hasRole(ADMIN_ROLE, msg.sender), "Unauthorized action");
        require(groupExists(_groupName), "Group does not exist");

        ROSCAGroup storage group = activeGroups[_groupName];
        group.members.push(_userAddress);
        _grantRole(USER_ROLE, _userAddress);
    }

    function hasRole(UserRole role, address _userAddress) public view returns (bool) {
        if (role == UserRole.Member) {
            string memory groupName = activeGroupNames[findGroupIndexByMember(_userAddress)];
            return groupExists(groupName) && activeGroups[groupName].roles[_userAddress] == UserRole.Member;
        } else {
            return hasRole(ADMIN_ROLE, msg.sender);
        }
    }

    function findGroupIndexByMember(address _userAddress) internal view returns (uint256) {
        for (uint256 i = 0; i < activeGroupNames.length; i++) {
            string memory groupName = activeGroupNames[i];
            if (activeGroups[groupName].roles[_userAddress] == UserRole.Member) {
                return i;
            }
        }
        revert("Group not found for the user");
    }

    function createROSCAGroup(
        string memory _groupName,
        string memory _description,
        uint256 _contributionAmount,
        uint256 _contributionFrequency,
        uint256 _numberOfMembers,
        uint256 _startDate,
        uint256 _endDate,
        address[] memory _initialMembers
    ) public {
        require(!groupExists(_groupName), "Group name already exists");

        ROSCAGroup storage newGroup = activeGroups[_groupName];

        newGroup.groupName = _groupName;
        newGroup.description = _description;
        newGroup.contributionAmount = _contributionAmount;
        newGroup.contributionFrequency = _contributionFrequency;
        newGroup.numberOfMembers = _numberOfMembers;
        newGroup.startDate = _startDate;
        newGroup.endDate = _endDate;

        activeGroupNames.push(_groupName);

        for (uint256 i = 0; i < _numberOfMembers; i++) {
            address member = _initialMembers[i];
            newGroup.members.push(member);
            newGroup.roles[member] = UserRole.Member;
        }
        
        emit ROSCAGroupCreated(_groupName);
    }

    function listActiveGroups() public view returns (string[] memory) {
    uint256 activeCount = 0;
    for (uint256 index = 0; index < activeGroupNames.length; index++) {
        string memory groupName = activeGroupNames[index];
        if (isGroupActive(groupName)) {
            activeCount++;
        }
    }
    string[] memory activeGroupsList = new string[](activeCount);
    uint256 activeIndex = 0;
    for (uint256 index = 0; index < activeGroupNames.length; index++) {
        string memory groupName = activeGroupNames[index];
        if (isGroupActive(groupName)) {
            activeGroupsList[activeIndex] = groupName;
            activeIndex++;
        }
    }

    return activeGroupsList;
}

    function joinROSCAGroup(string memory _groupName) public {
        require(groupExists(_groupName), "Group does not exist");
        require(isGroupActive(_groupName), "Group is inactive");
        require(activeGroups[_groupName].members.length < activeGroups[_groupName].numberOfMembers, "Group is full");
        
        activeGroups[_groupName].members.push(msg.sender);
        _grantRole(USER_ROLE, msg.sender);
        
        emit UserJoinedROSCAGroup(_groupName, msg.sender);
    }

    function contributeFunds(string memory _groupName) public payable {
        require(groupExists(_groupName), "Group does not exist");
        require(isGroupActive(_groupName), "Group is inactive");
        //require(activeGroups[_groupName].members.contains(msg.sender), "User is not a member of the group");
        require(addressExists(activeGroups[_groupName].members, msg.sender), "User is not a member of the group");
        require(msg.value == activeGroups[_groupName].contributionAmount, "Invalid contribution amount");

        activeGroups[_groupName].contributions[msg.sender] += msg.value;
        
        emit UserContributedFunds(_groupName, msg.sender, msg.value);
    }

    function randomizeRecipient(string memory _groupName) public {
        require(groupExists(_groupName), "Group does not exist");
        address[] memory members = activeGroups[_groupName].members;
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp))) % members.length;
        address recipient = members[randomIndex];
        activeGroups[_groupName].currentRecipient = recipient;
        emit RecipientSelected(_groupName, recipient);
    }

    function releaseFunds(string memory _groupName) public {
        require(groupExists(_groupName), "Group does not exist");
        address recipient = activeGroups[_groupName].currentRecipient;
        require(recipient != address(0), "No recipient selected");

        bool success = OgioExcrow(escrowContract).releaseFunds(_groupName, recipient);

        if (success) {
            emit FundsReleased(_groupName, recipient, activeGroups[_groupName].contributionAmount);
        } else {
            emit ReleaseFailed(_groupName, "Escrow release failed");
        }
    }

    function removeUser(string memory _groupName, address _userAddress) public {
        require(groupExists(_groupName), "Group does not exist");
        //require(hasRole(UserRole.Admin), "Unauthorized action");
        require(hasRole(UserRole.Admin, msg.sender), "Unauthorized action");
        require(activeGroups[_groupName].roles[_userAddress] != UserRole.None, "User not in group");
        
        activeGroups[_groupName].roles[_userAddress] = UserRole.None;
        emit UserRemoved(_groupName, _userAddress);
    }

    function getGroupMembers(string memory _groupName) public view returns (address[] memory) {
        return activeGroups[_groupName].members;
    }

    function updateDetails(string memory _groupName, string memory _newDescription, uint256 _newContributionAmount) public {
        require(groupExists(_groupName), "Group does not exist");
        //require(hasRole(UserRole.Admin) || hasRole(UserRole.Coordinator), "Unauthorized action");
        require(hasRole(UserRole.Admin, msg.sender), "Unauthorized action");

        activeGroups[_groupName].description = _newDescription;
        activeGroups[_groupName].contributionAmount = _newContributionAmount;

        emit GroupUpdated(_groupName, _newDescription, _newContributionAmount);
    }

    function repayFunds(string memory _groupName, uint256 _amount) public {
        require(groupExists(_groupName), "Group does not exist");
        bool success = OgioExcrow(escrowContract).repayFunds(_groupName, msg.sender, _amount);

        if (success) {
            activeGroups[_groupName].contributions[msg.sender] -= _amount;
            emit FundsRepaid(_groupName, msg.sender, _amount);
        } else {
            emit RepayFailed(_groupName, "Escrow repay failed");
        }
    }

    function manageEscrow(string memory _action, string memory _groupName, address _userAddress) public {
        require(groupExists(_groupName), "Group does not exist");
        OgioExcrow(escrowContract).manageEscrow(_action, _groupName, _userAddress);
        emit EscrowManaged(_action, _groupName, _userAddress);
    }

    function trackHistory(string memory _groupName, string memory _type, string memory _details) public {
        OgioExcrow(escrowContract).trackHistory(_groupName, _type, _details);
        emit TransactionTracked(_groupName, _type, _details);
    }

    function verifyDocumentation(string memory _groupName, string memory _documentHash) public {
        require(groupExists(_groupName), "Group does not exist");
        bool isValid = OgioExcrow(escrowContract).verifyDocumentation(_groupName, _documentHash);

        if (isValid) {
            emit DocumentationVerified(_groupName, true);
        } else {
            emit VerificationFailed(_groupName, "Invalid documentation");
        }
    }

    function isGroupActive(string memory _groupName) internal view returns (bool) {
        uint256 currentDate = block.timestamp;
        return (currentDate >= activeGroups[_groupName].startDate && currentDate <= activeGroups[_groupName].endDate);
    }

    function groupExists(string memory _groupName) internal view returns (bool) {
        return keccak256(bytes(activeGroups[_groupName].groupName)) == keccak256(bytes(_groupName));
    }

    function findGroupIndex(string memory _groupName) internal view returns (uint256) {
        for (uint256 i = 0; i < activeGroupNames.length; i++) {
            if (keccak256(bytes(activeGroupNames[i])) == keccak256(bytes(_groupName))) {
                return i;
            }
        }
        revert("Group not found");
    }
}