// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Escrow is Ownable {
    enum State {
        Active,
        Refunding,
        Closed
    }

    event Deposited(address indexed payee, uint256 weiAmount);
    event Withdrawn(address indexed payee, uint256 weiAmount);
    event RefundsClosed();
    event RefundsEnabled();

    State private _state;
    address private _beneficiary;
    uint256 private _maturityDate;

    mapping(address => uint256) private _deposits;

    /**
     * @dev Constructor.
     * @param beneficiary The beneficiary of the deposits.
     */
    constructor(address beneficiary, uint256 maturityDate, address _initialOwner) Ownable(_initialOwner) {
        require(beneficiary != address(0));
        _beneficiary = beneficiary;
        _maturityDate = maturityDate;
        _state = State.Active;
    }

    /**
     * @return the current state of the escrow.
     */
    function state() public view returns (State) {
        return _state;
    }

    /**
     * @return the beneficiary of the escrow.
     */
    function beneficiary() public view returns (address) {
        return _beneficiary;
    }

    /**
     * @dev Stores the sent amount as credit to be withdrawn.
     * @param payee The destination address of the funds.
     */
    function deposit(address payee) internal onlyOwner{
        uint256 amount = msg.value;
        _deposits[payee] = amount;

        emit Deposited(payee, amount);
    }

    function withdrawalAllowed(address payee) public view returns (bool) {}

    /**
     * @dev Withdraw accumulated balance for a payee.
     * @param payee The address whose funds will be withdrawn and transferred to.
     */
    function withdraw(address payee) internal onlyOwner{
        require(withdrawalAllowed(payee));
        uint256 payment = _deposits[payee];

        _deposits[payee] = 0;

        //payee.transfer(payment);

        emit Withdrawn(payee, payment);
    }
}
