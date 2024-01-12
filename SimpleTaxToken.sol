// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

//Reference
//https://github.com/onmychain/smart-contracts/blob/main/contracts

contract SimpleTaxToken is ERC20 , Ownable2Step {

    address private _treasuryAddress;
    address[] private _lpPairAddresses;

    address private _configAuthorityAddress;

    /*0-100%*/
    uint256 private _taxRate = 0;
    uint256 private _maxSupply = 0;
    bool private _tax_enabled = false;
   
    bool private _fair_mode_enabled = false;
    uint256 private _fair_max_per_wallet = 0;

    error ConfigUnauthorizedAccount(address account);

    event TaxPaid(address indexed from, address indexed to, uint256 value);

    constructor(string memory name_, string memory symbol_,uint256 maxSupply_) ERC20(name_, symbol_) Ownable(msg.sender) {
        _maxSupply = maxSupply_;
        _fair_max_per_wallet = _maxSupply;
    }
    function lp_pairs() public view returns (address[] memory){
        return _lpPairAddresses;
    }
    function maxSupply() public view virtual returns (uint256) {
        return _maxSupply;
    }
    function taxRate() public view virtual returns (uint256){
        return _taxRate;
    }
    function treasuryAddress() public view virtual returns (address) {
        return _treasuryAddress;
    }
    function tax_enabled() public view returns(bool){
        return _tax_enabled;
    }
    function fair_mode_enabled() public view returns (bool){
        return _fair_mode_enabled;
    }
    function fair_max_per_wallet() public view returns(uint256){
        return _fair_max_per_wallet;   
    }
    function config_authority() public view returns (address) {
        return _configAuthorityAddress;   
    }
    function update_fair_mode_enabled(bool enabled,uint256 limit_per_wallet_) external onlyConfigAuthority {
       require(limit_per_wallet_ <= _maxSupply,"Fair mode limit overflow");
       _fair_mode_enabled = enabled;
       _fair_max_per_wallet = limit_per_wallet_;
    }
    function update_tax_enabled(bool enabled,uint256 taxRate_) external onlyConfigAuthority {
        require(taxRate_ <= 10,"Tax rate overflow");
        _tax_enabled = enabled;
        _taxRate = taxRate_;
    }
    function update_max_supply(uint256 newMaxSupply) external onlyOwner{
        require(newMaxSupply >= totalSupply(),"Max Supply Underflow");
        _maxSupply = newMaxSupply;
    }
    function mint(uint256 amount) external onlyOwner{
        require(_can_mint_amount(amount),"Over supply");
        _mint(msg.sender,amount);
    }
    function mint_to(address to,uint256 amount) external onlyOwner{
        require(_can_mint_amount(amount),"Over supply");
        _mint(to,amount);
    }
    function set_config_authority(address addr_) external onlyOwner{
        require(addr_ != address(0),"Config Authority can't be null");
        _configAuthorityAddress = addr_;
    }
    function update_treasury_addres(address treasure) external onlyConfigAuthority {
        require(treasure != address(0),"Spender can't be null");
        _treasuryAddress = treasure;
    }
    function add_lp_pair(address lp_pair) external onlyConfigAuthority {
        require(lp_pair != address(0),"Spender can't be null");
        _lpPairAddresses.push(lp_pair);
    }
    function cleanup_lp_pairs() external onlyConfigAuthority {
       delete _lpPairAddresses;
    }
    function _can_mint_amount(uint256 amount) internal view returns (bool){
        uint256 _total = totalSupply();
        return (_total <= _maxSupply) && ((_maxSupply - _total) >= amount);
    }
    
    // checks whether the transfer is a swap
    function _is_trade_action(address from, address to) internal view returns (bool) {
        if(from == address(0) || to == address(0))
            return false;
        for (uint i = 0; i < _lpPairAddresses.length; i++) 
        {
            if (from == _lpPairAddresses[i] || to == _lpPairAddresses[i]) {
               return true;
            }
        }
        return false;
    }
    function _is_lp_pair(address addr) internal view returns (bool) {
        for (uint i = 0; i < _lpPairAddresses.length; i++) {
            if (addr == _lpPairAddresses[i]) 
               return true;
        }
        return false;
    }
    function _can_tax_chargable(address from, address to) internal view returns (bool){
        return _tax_enabled && (_treasuryAddress != address(0)) && _is_trade_action(from, to);
    }
    function _is_overflow_limit_per_wallet(address to,uint256 value) internal view returns (bool){
        if(_fair_mode_enabled && (to != address(0)) && (to != _treasuryAddress) && !_is_lp_pair(to))
            return ((balanceOf(to) + value) > _fair_max_per_wallet);
        return false;
    }
    function _update(address from, address to, uint256 value) internal virtual override {
        bool is_fair_mode_overflow =  _is_overflow_limit_per_wallet(to,value);
        require(!is_fair_mode_overflow,"Fair mode overflow");
        bool tax_charged = _can_tax_chargable(from,to);
        if(tax_charged)
        {
            uint256 tax = calculate_tax(value);
            super._update(from,to,value-tax);
            super._update(from,_treasuryAddress,tax);
            emit TaxPaid(from,to,tax);
        }
        else
           super._update(from,to,value);
    }
    function calculate_tax(uint256 amount) internal view virtual returns (uint256) {
       return (amount / 100) * _taxRate;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyConfigAuthority() {
        _checkConfigAuthority();
        _;
    }
    function _checkConfigAuthority() internal view virtual {
        address _sender = _msgSender();
        if ((owner() != _sender) && (_configAuthorityAddress != _sender)) {
            revert ConfigUnauthorizedAccount(_sender);
        }
    }

}