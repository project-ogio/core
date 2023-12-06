// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../OgioParent.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

contract Escrow is OgioService, VRFV2WrapperConsumerBase, ConfirmedOwner {
    enum State {
        Deposit,
        Release,
        Refund,
        Closed
    }
    struct SeedRequestStatus {
        uint256 paid; // amount paid in link
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256[] randomWords;
    }

    struct EscrowDetails {
        address escrowAddress;
        uint256 contribution;
        ContributionFrequency frequency;
        address[] contributors;
        address[] potentialBeneficiaries;
        address currentBeneficiary;
        State state;
        uint256 ethTotalReleased;
        mapping(address => uint256) ethReleased;
        mapping(IERC20 => uint256) erc20TotalReleased;
        mapping(IERC20 => mapping(address => uint256)) erc20Released;
        mapping(address => uint256) depositUnits;
    }

    // past requests Id.
    uint256[] public seedRequestIds;
    uint256 public lastSeedRequestId;

    uint256 private immutable seed;
    uint256 private contribution;
    ContributionFrequency private frequency;
    State private _state;

    mapping(address => address) private contributors; // List declaration to avoid duplicates
    mapping(address => address) private hotPaymentCandidates;

    uint256 private _ethTotalReleased;
    mapping(address => uint256) private _ethReleased;
    mapping(IERC20 => uint256) private _erc20TotalReleased;
    mapping(IERC20 => mapping(address => uint256)) private _erc20Released;
    mapping(address => uint256) private depositUnits;

    event SeedRequestSent(uint256 requestId, uint32 numWords);
    event SeedRequestFulfilled(
        uint256 requestId,
        uint256[] randomWords,
        uint256 payment
    );
    event ContributorAdded(address account);
    event PaymentReceived(address from, uint256 amount);
    event PaymentReleased(address to, uint256 amount);
    event ERC20PaymentReleased(
        IERC20 indexed token,
        address to,
        uint256 amount
    );
    event RefundsClosed();
    event RefundsEnabled();

    /**
     * @dev Constructor.
     * @param group The beneficiary of the deposits.
     */
    constructor(
        ROSCAGroup memory group,
        uint256 _contribution,
        ContributionFrequency _frequency,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(contribution > 0, "Escrow: Contribution cannot be zero");
        require(
            group.members.length > MINIMUM_MEMBERS,
            "Escrow: Not enough members"
        );

        contribution = _contribution;
        frequency = _frequency;
        _state = State.Deposit;
        for (uint256 i = 0; i < group.members.length; i++) {
            _addContributor(group.members[i]);
        }
    }

    receive() external payable virtual {
        requireContributorExists();
        require(
            msg.value == contribution,
            "Escrow: Contribution does not match this contract"
        );
        require(
            _state == State.AcceptingDeposits,
            "This escrow service is not accepting deposits"
        );

        depositUnits[msg.sender] += 1;
        emit PaymentReceived(msg.sender, msg.value);
    }

    receive() external payable virtual {
        requireContributorExists();
        uint256 amount = token.balanceOf(msg.value);
        require(
            amount == contribution,
            "Escrow: Contribution does not match this contract"
        );
        require(
            _state == State.AcceptingDeposits,
            "This escrow service is not accepting deposits"
        );

        depositUnits[msg.sender] += 1;
        emit PaymentReceived(msg.sender, amount);
    }

    /**
     * @return the current state of the escrow.
     */
    function details() public view returns (EscrowDetails) {
        requireContributorExists();
        return _state;
    }

    /**
     * @dev Getter for the amount of shares held by the sender.
     */
    function deposits() public view returns (uint256) {
        return (_depositUnits[msg.sender] * contribution);
    }

    /**
     * @dev Getter for the amount of shares held by an account.
     */
    function deposits(IERC20 token) public view returns (uint256) {
        return (_depositUnits[msg.sender] * token.balanceOf(contribution));
    }

    /**
     * @dev Getter for the amount of Ether already released to a payee.
     */
    function released() public view returns (uint256) {
        return _ethReleased[msg.sender];
    }

    /**
     * @dev Getter for the amount of `token` tokens already released to a payee. `token` should be the address of an
     * IERC20 contract.
     */
    function released(IERC20 token) public view returns (uint256) {
        return _erc20Released[token][msg.sender];
    }

    /**
     * @dev Getter for the total amount of Ether already released.
     */
    function totalReleased() public view returns (uint256) {
        return _ethTotalReleased;
    }

    /**
     * @dev Getter for the total amount of `token` already released. `token` should be the address of an IERC20
     * contract.
     */
    function totalReleased(IERC20 token) public view returns (uint256) {
        return _erc20TotalReleased[token];
    }

    /**
     * @dev Getter for the amount of payee's releasable Ether.
     */
    function releasable() public view returns (uint256) {
        _releasable();
        uint256 totalReceived = address(this).balance + totalReleased();
        return _pendingPayment(msg.sender, totalReceived, released(msg.sender));
    }

    /**
     * @dev Getter for the amount of payee's releasable `token` tokens. `token` should be the address of an
     * IERC20 contract.
     */
    function releasable(IERC20 token) public view returns (uint256) {
        _releasable();
        uint256 totalReceived = token.balanceOf(address(this)) +
            totalReleased(token);
        return
            _pendingPayment(
                msg.sender,
                totalReceived,
                released(msg.sender, account)
            );
    }

    /**
     * @dev Add a new contributor to the contract.
     * @param account The address of the contributor to add.
     */
    function _addContributor(address account) internal onlyOwner {
        require(account != address(0), "Escrow: Account is the zero address");
        require(
            !addressExists(contributors, account),
            "Escrow: Duplicate address detected"
        );

        contributors[account] = account;
        hotPaymentCandidates[account] = account;
        emit ContributorAdded(account);
    }

    /**
     * @dev Triggers a transfer to `account` of the amount of Ether they are owed, according to their percentage of the
     * total shares and their previous withdrawals.
     */
    function release() public {
        require(
            _state == State.Release || _state == State.Refund,
            "Escrow: Releasing funds has been disabled"
        );
        uint256 payment = releasable();

        require(payment != 0, "Escrow: account is not due payment");

        // _totalEthReleased is the sum of all values in _ethReleased.
        // If "_totalEthReleased += payment" does not overflow, then "_ethReleased[account] += payment" cannot overflow.
        _totalEthReleased += payment;
        unchecked {
            _ethReleased[account] += payment;
        }

        Address.sendValue(account, payment);
        emit PaymentReleased(account, payment);
    }

    /**
     * @dev Triggers a transfer to `account` of the amount of `token` tokens they are owed, according to their
     * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
     * contract.
     */
    function release(IERC20 token, address account) public {
        require(
            _state == State.Release || _state == State.Refund,
            "Escrow: Releasing funds has been disabled"
        );
        uint256 payment = releasable(token, account);

        require(payment != 0, "Escrow: account is not due payment");

        // _erc20TotalReleased[token] is the sum of all values in _erc20Released[token].
        // If "_erc20TotalReleased[token] += payment" does not overflow, then "_erc20Released[token][account] += payment"
        // cannot overflow.
        _erc20TotalReleased[token] += payment;
        unchecked {
            _erc20Released[token][account] += payment;
        }

        SafeERC20.safeTransfer(token, account, payment);
        emit ERC20PaymentReleased(token, account, payment);
    }

    /**
     * @dev internal logic for computing the pending payment of an `account` given the token historical balances and
     * already released amounts.
     */
    function _pendingPayment(address account) private view returns (uint256) {}

    function _releasable() internal view {
        requireContributorExists();
        require(
            _depositUnits[msg.sender] > 0,
            "Escrow: Member has made no deposits"
        );
    }

    function requireContributorExists() internal view {
        require(contributors[msg.sender] > 0, "You are not a contributor");
    }
}
