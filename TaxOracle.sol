// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-old/math/SafeMath.sol";
import "@openzeppelin/contracts-old/access/Ownable.sol";
import "@openzeppelin/contracts-old/token/ERC20/IERC20.sol";

contract TaxOracle is Ownable {
    using SafeMath for uint256;

    IERC20 public emp;
    IERC20 public eth;
    address public pair;

    constructor(
        address _emp,
        address _eth,
        address _pair
    ) public {
        require(_emp != address(0), "emp address cannot be 0");
        require(_eth != address(0), "eth address cannot be 0");
        require(_pair != address(0), "pair address cannot be 0");
        emp = IERC20(_emp);
        eth = IERC20(_eth);
        pair = _pair;
    }

    function consult(address _token, uint256 _amountIn) external view returns (uint144 amountOut) {
        require(_token == address(emp), "token needs to be emp");
        uint256 empBalance = emp.balanceOf(pair);
        uint256 ethBalance = eth.balanceOf(pair);
        return uint144(empBalance.mul(_amountIn).div(ethBalance));
    }

    function getEmpBalance() external view returns (uint256) {
	return emp.balanceOf(pair);
    }

    function getEthBalance() external view returns (uint256) {
	return eth.balanceOf(pair);
    }

    function getPrice() external view returns (uint256) {
        uint256 empBalance = emp.balanceOf(pair);
        uint256 ethBalance = eth.balanceOf(pair);
        return empBalance.mul(1e18).div(ethBalance);
    }


    function setEmp(address _emp) external onlyOwner {
        require(_emp != address(0), "emp address cannot be 0");
        emp = IERC20(_emp);
    }

    function setEth(address _eth) external onlyOwner {
        require(_eth != address(0), "eth address cannot be 0");
        eth = IERC20(_eth);
    }

    function setPair(address _pair) external onlyOwner {
        require(_pair != address(0), "pair address cannot be 0");
        pair = _pair;
    }



}