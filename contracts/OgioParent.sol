// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

abstract contract OgioService {

    function getHotPayment(uint256 contribution, uint256 memberCount)
        public
        pure
        returns (uint256)
    {
        return (contribution * memberCount) / 2;
    }

    function getColdPayment(uint256 contribution, uint256 memberCount)
        public
        pure
        returns (uint256)
    {
        return (getHotPayment(contribution, memberCount) / (memberCount - 1));
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

    enum ContributionFrequency {
        Weekly,
        Bi_weely,
        Monthly
    }

    // Define the ROSCAGroup struct
    struct ROSCAGroup {
        string groupId;
        string groupName;
        address[] members;
        mapping(address => UserRole) roles;
        uint256 startDate;
        uint256 endDate;
    }

    bytes32 constant USER_ROLE = keccak256("USER");
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN");
    uint256 constant MINIMUM_MEMBERS = 3;

    event Deposited(address indexed _payee, uint256 _weiAmount);
    event Withdrawn(address indexed _payee, uint256 _weiAmount);
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
