// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

abstract contract OgioService is AccessControl {
    function addressExists(address[] memory addresses, address addr)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == addr) {
                return true;
            }
        }
        return false;
    }

    enum UserRole {
        Member,
        Admin,
        None
    }

    enum EscrowState {
        Active,
        Refunding,
        Closed
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

    bytes32 constant USER_ROLE = keccak256("USER");
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN");

    event Deposited(address indexed payee, uint256 weiAmount);
    event Withdrawn(address indexed payee, uint256 weiAmount);
    event ROSCAGroupCreated(string _groupName);
    event UserContributedFunds(
        string _groupName,
        address _userAddress,
        uint256 _amount
    );
    event RecipientSelected(string _groupName, address _recipientAddress);
    event FundsReleased(
        string _groupName,
        address _recipientAddress,
        uint256 _amount
    );
    event ReleaseFailed(string _groupName, string _reason);
    event FundsRepaid(string _groupName, address _userAddress, uint256 _amount);
    event RepayFailed(string _groupName, string _reason);
    event EscrowManaged(
        string _action,
        string _groupName,
        address _userAddress
    );
    event TransactionTracked(string _groupName, string _type, string _details);
    event DocumentationVerified(string _groupName, bool _isValid);
    event VerificationFailed(string _groupName, string _reason);
    event GroupUpdated(
        string _groupName,
        string _newDescription,
        uint256 _newContributionAmount
    );
    event UserJoinedROSCAGroup(string _groupName, address _userAddress);
    event UserRemoved(string _groupName, address _userAddress);

    event RefundsClosed();
    event RefundsEnabled();
}
