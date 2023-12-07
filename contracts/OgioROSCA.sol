// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
//import "./OgioExcrow.sol";
import {OgioService} from "./OgioParent.sol";

contract OgioROSCA is OgioService, VRFV2WrapperConsumerBase, ConfirmedOwner {

    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(
        uint256 requestId,
        uint256[] randomWords,
        uint256 payment
    );

    struct RequestStatus {
        uint256 paid; // amount paid in link
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256[] randomWords;
    }
    mapping(uint256 => RequestStatus)
    public s_requests; /* requestId --> requestStatus */

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    uint32 callbackGasLimit = 100000;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations = 3;

    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFV2Wrapper.getConfig().maxNumWords.
    uint32 numWords = 2;

    // Address LINK - hardcoded for Sepolia
    address linkAddress = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    // address WRAPPER - hardcoded for Sepolia
    address wrapperAddress = 0xab18414CD93297B0d12ac29E63Ca20f515b3DB46;
    
    // Mapping of group names to ROSCAGroup instances
    mapping(string => ROSCAGroup) private activeGroups;
    string[] private activeGroupNames;

    // Escrow contract address
    address public escrowContract;

    constructor() ConfirmedOwner(msg.sender) VRFV2WrapperConsumerBase(linkAddress, wrapperAddress)
    {
        // Set deployer as the initial admin
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

    }

    function grantUserRole(string memory _groupName, address _userAddress)
        public
    {
        require(hasRole(ADMIN_ROLE, msg.sender), "Unauthorized action");
        require(groupExists(_groupName), "Group does not exist");

        ROSCAGroup storage group = activeGroups[_groupName];
        group.members.push(_userAddress);
        _grantRole(USER_ROLE, _userAddress);
    }

    function requestRandomWords()
        external
        onlyOwner
        returns (uint256 requestId)
    {
        requestId = requestRandomness(
            callbackGasLimit,
            requestConfirmations,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            paid: VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit),
            randomWords: new uint256[](0),
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].paid > 0, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        emit RequestFulfilled(
            _requestId,
            _randomWords,
            s_requests[_requestId].paid
        );
    }

    function getRequestStatus(
        uint256 _requestId
    )
        external
        view
        returns (uint256 paid, bool fulfilled, uint256[] memory randomWords)
    {
        require(s_requests[_requestId].paid > 0, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.paid, request.fulfilled, request.randomWords);
    }

    function hasRole(UserRole role, address _userAddress)
        public
        view
        returns (bool)
    {
        if (role == UserRole.Member) {
            string memory groupName = activeGroupNames[
                findGroupIndexByMember(_userAddress)
            ];
            return
                groupExists(groupName) &&
                activeGroups[groupName].roles[_userAddress] == UserRole.Member;
        } else {
            return hasRole(ADMIN_ROLE, msg.sender);
        }
    }

    function findGroupIndexByMember(address _userAddress)
        internal
        view
        returns (uint256)
    {
        for (uint256 i = 0; i < activeGroupNames.length; i++) {
            string memory groupName = activeGroupNames[i];
            if (
                activeGroups[groupName].roles[_userAddress] == UserRole.Member
            ) {
                return i;
            }
        }
        revert("Group not found for the user");
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

    function joinROSCAGroup(string memory _groupName) public {
        require(groupExists(_groupName), "Group does not exist");
        require(isGroupActive(_groupName), "Group is inactive");
        require(
            activeGroups[_groupName].members.length <
                activeGroups[_groupName].numberOfMembers,
            "Group is full"
        );

        activeGroups[_groupName].members.push(msg.sender);
        _grantRole(USER_ROLE, msg.sender);

        emit UserJoinedROSCAGroup(_groupName, msg.sender);
    }

    function contributeFunds(string memory _groupName) public payable {
        require(groupExists(_groupName), "Group does not exist");
        require(isGroupActive(_groupName), "Group is inactive");
        //require(activeGroups[_groupName].members.contains(msg.sender), "User is not a member of the group");
        require(
            addressExists(activeGroups[_groupName].members, msg.sender),
            "User is not a member of the group"
        );
        require(
            msg.value == activeGroups[_groupName].contributionAmount,
            "Invalid contribution amount"
        );

        activeGroups[_groupName].contributions[msg.sender] += msg.value;

        emit UserContributedFunds(_groupName, msg.sender, msg.value);
    }

    // function randomizeRecipient(string memory _groupName) public {
    //     require(groupExists(_groupName), "Group does not exist");
    //     address[] memory members = activeGroups[_groupName].members;
    //     uint256 randomIndex = uint256(
    //         keccak256(abi.encodePacked(block.timestamp))
    //     ) % members.length;
    //     address recipient = members[randomIndex];
    //     activeGroups[_groupName].currentRecipient = recipient;
    //     emit RecipientSelected(_groupName, recipient);
    // }

    // function releaseFunds(string memory _groupName) public {
    //     require(groupExists(_groupName), "Group does not exist");
    //     address recipient = activeGroups[_groupName].currentRecipient;
    //     require(recipient != address(0), "No recipient selected");

    //     bool success = OgioExcrow(escrowContract).releaseFunds(_groupName, recipient);

    //     if (success) {
    //         emit FundsReleased(_groupName, recipient, activeGroups[_groupName].contributionAmount);
    //     } else {
    //         emit ReleaseFailed(_groupName, "Escrow release failed");
    //     }
    // }

    function removeUser(string memory _groupName, address _userAddress) public {
        require(groupExists(_groupName), "Group does not exist");
        //require(hasRole(UserRole.Admin), "Unauthorized action");
        require(hasRole(UserRole.Admin, msg.sender), "Unauthorized action");
        require(
            activeGroups[_groupName].roles[_userAddress] != UserRole.None,
            "User not in group"
        );

        activeGroups[_groupName].roles[_userAddress] = UserRole.None;
        emit UserRemoved(_groupName, _userAddress);
    }

    function getGroupMembers(string memory _groupName)
        public
        view
        returns (address[] memory)
    {
        return activeGroups[_groupName].members;
    }

    function updateDetails(
        string memory _groupName,
        string memory _newDescription,
        uint256 _newContributionAmount
    ) public {
        require(groupExists(_groupName), "Group does not exist");
        //require(hasRole(UserRole.Admin) || hasRole(UserRole.Coordinator), "Unauthorized action");
        require(hasRole(UserRole.Admin, msg.sender), "Unauthorized action");

        activeGroups[_groupName].description = _newDescription;
        activeGroups[_groupName].contributionAmount = _newContributionAmount;

        emit GroupUpdated(_groupName, _newDescription, _newContributionAmount);
    }

    // function repayFunds(string memory _groupName, uint256 _amount) public {
    //     require(groupExists(_groupName), "Group does not exist");
    //     bool success = OgioExcrow(escrowContract).repayFunds(_groupName, msg.sender, _amount);

    //     if (success) {
    //         activeGroups[_groupName].contributions[msg.sender] -= _amount;
    //         emit FundsRepaid(_groupName, msg.sender, _amount);
    //     } else {
    //         emit RepayFailed(_groupName, "Escrow repay failed");
    //     }
    // }

    // function manageEscrow(string memory _action, string memory _groupName, address _userAddress) public {
    //     require(groupExists(_groupName), "Group does not exist");
    //     OgioExcrow(escrowContract).manageEscrow(_action, _groupName, _userAddress);
    //     emit EscrowManaged(_action, _groupName, _userAddress);
    // }

    // function trackHistory(string memory _groupName, string memory _type, string memory _details) public {
    //     OgioExcrow(escrowContract).trackHistory(_groupName, _type, _details);
    //     emit TransactionTracked(_groupName, _type, _details);
    // }

    // function verifyDocumentation(string memory _groupName, string memory _documentHash) public {
    //     require(groupExists(_groupName), "Group does not exist");
    //     bool isValid = OgioExcrow(escrowContract).verifyDocumentation(_groupName, _documentHash);

    //     if (isValid) {
    //         emit DocumentationVerified(_groupName, true);
    //     } else {
    //         emit VerificationFailed(_groupName, "Invalid documentation");
    //     }
    // }

    function isGroupActive(string memory _groupName)
        internal
        view
        returns (bool)
    {
        uint256 currentDate = block.timestamp;
        return (currentDate >= activeGroups[_groupName].startDate &&
            currentDate <= activeGroups[_groupName].endDate);
    }

    function groupExists(string memory _groupName)
        internal
        view
        returns (bool)
    {
        return
            keccak256(bytes(activeGroups[_groupName].groupName)) ==
            keccak256(bytes(_groupName));
    }

    function findGroupIndex(string memory _groupName)
        internal
        view
        returns (uint256)
    {
        for (uint256 i = 0; i < activeGroupNames.length; i++) {
            if (
                keccak256(bytes(activeGroupNames[i])) ==
                keccak256(bytes(_groupName))
            ) {
                return i;
            }
        }
        revert("Group not found");
    }

    /**
     * Allow withdraw of Link tokens from the contract
     */
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(linkAddress);
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }
}
