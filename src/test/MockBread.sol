pragma solidity ^0.8.22;

import {Checkpoints} from
    "openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/structs/Checkpoints.sol";
import {ERC20} from "openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockBread is ERC20 {
    uint256 public _yieldAccrued;
    uint256 private cpnum;
    mapping(address => Checkpoints.Checkpoint208[]) public accountCheckpoints;

    constructor() ERC20("Bread", "BRD") {
        _yieldAccrued = 100 * 10 ** 18;
        cpnum = 3;
    }

    function claimYield(uint256, /*amount */ address receiver) external  {
        _mint(receiver, _yieldAccrued);
    }

    function yieldAccrued() external view  returns (uint256) {
        return _yieldAccrued;
    }

    function numCheckpoints(address /*account*/ ) external view  returns (uint32) {
        return uint32(cpnum);
    }

    function checkpoints(address, /*account*/ uint32 pos)
        external
        view
        returns (Checkpoints.Checkpoint208 memory)
    {
        Checkpoints.Checkpoint208 memory cp1 = Checkpoints.Checkpoint208(uint48(block.number - 3000), 100);
        Checkpoints.Checkpoint208 memory cp2 = Checkpoints.Checkpoint208(uint48(block.number - 1000), 120);
        Checkpoints.Checkpoint208 memory cp3 = Checkpoints.Checkpoint208(uint48(block.number - 500), 30);
        return pos == 0 ? cp1 : pos == 1 ? cp2 : cp3;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        return super.approve(spender, amount);
    }

    function totalSupply() public view override returns (uint256) {
        return super.totalSupply();
    }

    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account);
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return super.allowance(owner, spender);
    }
}
