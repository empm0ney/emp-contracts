// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-old/math/SafeMath.sol";
import "./owner/Operator.sol";
import "./interfaces/ITaxable.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IERC20.sol";

contract TaxOfficeV2 is Operator {
    using SafeMath for uint256;

    address public emp;
    address public weth = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address public uniRouter = address(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    mapping(address => bool) public taxExclusionEnabled;

    constructor(address _emp, address _weth, address _uniRouter) public {
        emp = _emp;
        weth = _weth;
        uniRouter = _uniRouter;
    }

    function setTaxTiersTwap(uint8 _index, uint256 _value) public onlyOperator returns (bool) {
        return ITaxable(emp).setTaxTiersTwap(_index, _value);
    }

    function setTaxTiersRate(uint8 _index, uint256 _value) public onlyOperator returns (bool) {
        return ITaxable(emp).setTaxTiersRate(_index, _value);
    }

    function enableAutoCalculateTax() public onlyOperator {
        ITaxable(emp).enableAutoCalculateTax();
    }

    function disableAutoCalculateTax() public onlyOperator {
        ITaxable(emp).disableAutoCalculateTax();
    }

    function setTaxRate(uint256 _taxRate) public onlyOperator {
        ITaxable(emp).setTaxRate(_taxRate);
    }

    function setBurnThreshold(uint256 _burnThreshold) public onlyOperator {
        ITaxable(emp).setBurnThreshold(_burnThreshold);
    }

    function setTaxCollectorAddress(address _taxCollectorAddress) public onlyOperator {
        ITaxable(emp).setTaxCollectorAddress(_taxCollectorAddress);
    }

    function excludeAddressFromTax(address _address) external onlyOperator returns (bool) {
        return _excludeAddressFromTax(_address);
    }

    function _excludeAddressFromTax(address _address) private returns (bool) {
        if (!ITaxable(emp).isAddressExcluded(_address)) {
            return ITaxable(emp).excludeAddress(_address);
        }
    }

    function includeAddressInTax(address _address) external onlyOperator returns (bool) {
        return _includeAddressInTax(_address);
    }

    function _includeAddressInTax(address _address) private returns (bool) {
        if (ITaxable(emp).isAddressExcluded(_address)) {
            return ITaxable(emp).includeAddress(_address);
        }
    }

    function taxRate() external returns (uint256) {
        return ITaxable(emp).taxRate();
    }

    function addLiquidityTaxFree(
        address token,
        uint256 amtEmp,
        uint256 amtToken,
        uint256 amtEmpMin,
        uint256 amtTokenMin
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtEmp != 0 && amtToken != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(emp).transferFrom(msg.sender, address(this), amtEmp);
        IERC20(token).transferFrom(msg.sender, address(this), amtToken);
        _approveTokenIfNeeded(emp, uniRouter);
        _approveTokenIfNeeded(token, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtEmp;
        uint256 resultAmtToken;
        uint256 liquidity;
        (resultAmtEmp, resultAmtToken, liquidity) = IUniswapV2Router(uniRouter).addLiquidity(
            emp,
            token,
            amtEmp,
            amtToken,
            amtEmpMin,
            amtTokenMin,
            msg.sender,
            block.timestamp
        );

        if (amtEmp.sub(resultAmtEmp) > 0) {
            IERC20(emp).transfer(msg.sender, amtEmp.sub(resultAmtEmp));
        }
        if (amtToken.sub(resultAmtToken) > 0) {
            IERC20(token).transfer(msg.sender, amtToken.sub(resultAmtToken));
        }
        return (resultAmtEmp, resultAmtToken, liquidity);
    }

    function addLiquidityETHTaxFree(
        uint256 amtEmp,
        uint256 amtEmpMin,
        uint256 amtEthMin
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtEmp != 0 && msg.value != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(emp).transferFrom(msg.sender, address(this), amtEmp);
        _approveTokenIfNeeded(emp, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtEmp;
        uint256 resultAmtEth;
        uint256 liquidity;
        (resultAmtEmp, resultAmtEth, liquidity) = IUniswapV2Router(uniRouter).addLiquidityETH{value: msg.value}(
            emp,
            amtEmp,
            amtEmpMin,
            amtEthMin,
            msg.sender,
            block.timestamp
        );

        if (amtEmp.sub(resultAmtEmp) > 0) {
            IERC20(emp).transfer(msg.sender, amtEmp.sub(resultAmtEmp));
        }
        return (resultAmtEmp, resultAmtEth, liquidity);
    }

    function setTaxableEmpOracle(address _empOracle) external onlyOperator {
        ITaxable(emp).setEmpOracle(_empOracle);
    }

    function transferTaxOffice(address _newTaxOffice) external onlyOperator {
        ITaxable(emp).setTaxOffice(_newTaxOffice);
    }

    function taxFreeTransferFrom(
        address _sender,
        address _recipient,
        uint256 _amt
    ) external {
        require(taxExclusionEnabled[msg.sender], "Address not approved for tax free transfers");
        _excludeAddressFromTax(_sender);
        IERC20(emp).transferFrom(_sender, _recipient, _amt);
        _includeAddressInTax(_sender);
    }

    function setTaxExclusionForAddress(address _address, bool _excluded) external onlyOperator {
        taxExclusionEnabled[_address] = _excluded;
    }

    function _approveTokenIfNeeded(address _token, address _router) private {
        if (IERC20(_token).allowance(address(this), _router) == 0) {
            IERC20(_token).approve(_router, type(uint256).max);
        }
    }
}
