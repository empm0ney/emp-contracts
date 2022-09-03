// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-old/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-old/token/ERC20/SafeERC20.sol";
import "./utils/ContractGuard.sol";
import "./interfaces/IZapper.sol";

contract Strategy is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IZapper public zapper;
    IERC20 public emp;
    IERC20 public eshare;
    IERC20 public empPair;
    IERC20 public esharePair;
    address public operator;
    uint256 public minEshare;
    uint256 public minEmp;

    constructor(address _zapper, address _emp, address _eshare, address _empPair, address _esharePair) public {
        zapper = IZapper(_zapper);
        emp = IERC20(_emp);
        eshare = IERC20(_eshare);
        empPair = IERC20(_empPair);
        esharePair = IERC20(_esharePair);
        operator = msg.sender;
        minEshare = 0.0005 ether;
        minEmp = 1 ether;

        emp.approve(address(zapper), type(uint256).max);
        eshare.approve(address(zapper), type(uint256).max);
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "Strategy: caller is not the operator");
        _;
    }

    function setMins(uint256 _minEshare, uint256 _minEmp) external onlyOperator {
        minEshare = _minEshare;
        minEmp = _minEmp;
    }

    function approveZapper(address asset) external onlyOperator {
        IERC20(asset).approve(address(zapper), type(uint256).max);
    }

    function withdraw(address asset) external onlyOperator {
        if (asset != address(0))
            IERC20(asset).safeTransfer(msg.sender, IERC20(asset).balanceOf(address(this)));
        else
            payable(msg.sender).transfer(address(this).balance);
    }

    function _checkMin(address from, uint256 amount) internal view returns (bool) {
        return from == address(emp) ? amount >= minEmp : amount >= minEshare;
    }

    function zapStrategy(address from, uint256 amount, uint256 percentEmpLP, uint256 slippageBp) external returns (uint256, uint256) {
        require(percentEmpLP <= 100, "Invalid EMP-ETH-LP percent");
        require(IERC20(from).balanceOf(msg.sender) >= amount, "Insufficient balance");
        IERC20(from).safeTransferFrom(msg.sender, address(this), amount);

        uint256 amountEmpPair = percentEmpLP < 100 ? amount.mul(percentEmpLP).div(100) : amount;
        uint256 amountEsharePair = amount.sub(amountEmpPair);

        uint256 prevEmpLP = empPair.balanceOf(address(this));
        uint256 prevEshareLP = esharePair.balanceOf(address(this));
        
        if (_checkMin(from, amountEmpPair)) {
            zapper.zapTokenToLP(from, amountEmpPair, address(empPair), slippageBp);
        } else {
            IERC20(from).safeTransfer(msg.sender, amountEmpPair);
        }
        if (_checkMin(from, amountEsharePair)) {
            zapper.zapTokenToLP(from, amountEsharePair, address(esharePair), slippageBp);
        } else {
            IERC20(from).safeTransfer(msg.sender, amountEsharePair);
        }

        uint256 zappedEmpLP = empPair.balanceOf(address(this)).sub(prevEmpLP);
        uint256 zappedEshareLP = esharePair.balanceOf(address(this)).sub(prevEshareLP);
        
        if (zappedEmpLP > 0)
            empPair.safeTransfer(msg.sender,  zappedEmpLP);
        if (zappedEshareLP > 0)
            esharePair.safeTransfer(msg.sender,  zappedEshareLP);
            
        return (zappedEmpLP, zappedEshareLP);
    }
}