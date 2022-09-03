// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./interfaces/IZapper.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IWrappedEth.sol";
import "./ContractWhitelisted.sol";

interface IMDB {
	function mintWithBacking(uint256 numTokens, address recipient) external returns (uint256);
}

/**
 * A zapper implementation which converts a single asset into
 * a ESHARE/ETH or EMP/ETH liquidity pair. And breaks a liquidity pair to single assets
 *
 */
contract ZapMDB is Ownable, IZapper, Pausable, ContractWhitelisted {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	address public immutable WBNB;
	address public immutable BUSD;
	address public immutable MDB;

	IUniswapV2Router private ROUTER;

	/*
	 * ====================
	 *    STATE VARIABLES
	 * ====================
	 */

	/**
	 * @dev Stores intermediate route information to convert a token to WBNB
	 */
	mapping(address => address) private routePairAddresses;

	/*
	 * ====================
	 *        INIT
	 * ====================
	 */

	constructor(
		address _router,
		address _EMP,
		address _ESHARE,
		address _ETH,
		address _BUSD,
		address _MDB
	) {
		ROUTER = IUniswapV2Router(_router);
		WBNB = ROUTER.WETH();
		BUSD = _BUSD;
		MDB = _MDB;

		// approve our main input tokens
		IERC20(_EMP).safeApprove(address(ROUTER), type(uint256).max);
		IERC20(_MDB).safeApprove(address(ROUTER), type(uint256).max);
		IERC20(_ESHARE).safeApprove(address(ROUTER), type(uint256).max);
		IERC20(_ETH).safeApprove(address(ROUTER), type(uint256).max);
		IERC20(_BUSD).safeApprove(address(ROUTER), type(uint256).max);
		IERC20(_BUSD).safeApprove(_MDB, type(uint256).max);

		// set route pairs for our tokens
		// routePairAddresses[_ESHARE] = _WBNB;
		routePairAddresses[_EMP] = _ETH;
	}

	receive() external payable {}

	/*
	 * ====================
	 *    VIEW FUNCTIONS
	 * ====================
	 */

	function routePair(address _address) external view returns (address) {
		return routePairAddresses[_address];
	}

	/*
	 * =========================
	 *     EXTERNAL FUNCTIONS
	 * =========================
	 */

	function zapBNBToLP(address _to, uint256 _slippageBp)
		external
		payable
		override
		whenNotPaused
		isAllowedContract(msg.sender)
	{
		_swapBNBToLP(_to, msg.value, msg.sender, _slippageBp);
	}

	function zapTokenToLP(
		address _from,
		uint256 amount,
		address _to,
		uint256 slippageBp
	) external override whenNotPaused isAllowedContract(msg.sender) {
		IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
		
		// Unknown future input tokens will make use of this
		uint256 bnbAmount = _swapTokenForBNB(_from, amount, address(this), slippageBp);
		_swapBNBToLP(_to, bnbAmount, msg.sender, slippageBp);
	}

	function breakLP(address _from, uint256 amount)
		external
		override
		whenNotPaused
		isAllowedContract(msg.sender)
	{
		IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);

		IUniswapV2Pair pair = IUniswapV2Pair(_from);
		address token0 = pair.token0();
		address token1 = pair.token1();
		ROUTER.removeLiquidity(
			token0,
			token1,
			amount,
			0,
			0,
			msg.sender,
			block.timestamp + 600
		);
	}

	/*
	 * =========================
	 *     PRIVATE FUNCTIONS
	 * =========================
	 */

	function _swapBNBToLP(
		address lp,
		uint256 amount,
		address receiver,
		uint256 slippageBp
	) private {
		address token0 = IUniswapV2Pair(lp).token0();
		address token1 = IUniswapV2Pair(lp).token1();

		uint256 swapValue = amount.div(2);
		
		if (token0 != WBNB)
			_swapBNBForToken(token0, swapValue, address(this), slippageBp);
		
		if (token1 != WBNB)
			_swapBNBForToken(token1, amount.sub(swapValue), address(this), slippageBp);

		if (token0 != WBNB && token1 != WBNB) {			
			ROUTER.addLiquidity(
				token0,
				token1,
				IERC20(token0).balanceOf(address(this)).mul(token1 == MDB ? 9925 : 10000).div(10000),
				IERC20(token1).balanceOf(address(this)).mul(token0 == MDB ? 9925 : 10000).div(10000),
				0,
				0,
				receiver,
				block.timestamp + 600
			);
		} else {
			address other = token0 == WBNB ? token1 : token0;
			if (token0 != WBNB) swapValue = amount.sub(swapValue);

			ROUTER.addLiquidityETH{value: swapValue}(
				other, 
				IERC20(other).balanceOf(address(this)), 
				0, 
				0, 
				receiver, 
				block.timestamp + 600
			);
		}
	}

	function _swapBNBForToken(
		address token,
		uint256 value,
		address receiver,
		uint256 slippageBp
	) private returns (uint256) {
		address[] memory path;

		if (token == MDB) {
			require(value > 0, "Zero value");
			path = new address[](2);
			path[0] = WBNB;
			path[1] = BUSD;
			// BNB -> BUSD
        	ROUTER.swapExactETHForTokens{value: value}(
            	0, path, address(this), block.timestamp + 600
        	);

        	// BUSD -> MDB+
        	IMDB(MDB).mintWithBacking(IERC20(BUSD).balanceOf(address(this)), address(this));
			require(IERC20(MDB).balanceOf(address(this)) > 0, "No MDB minted");
			return IERC20(MDB).balanceOf(address(this));
		}

		if (routePairAddresses[token] != address(0)) {
			// E.g. [WBNB, ETH, ESHARE/EMP]
			path = new address[](3);
			path[0] = WBNB;
			path[1] = routePairAddresses[token];
			path[2] = token;
		} else {
			path = new address[](2);
			path[0] = WBNB;
			path[1] = token;
		}

		uint[] memory quoteAmounts = ROUTER.getAmountsOut(value, path);
		uint256[] memory amounts = ROUTER.swapExactETHForTokens{value: value}(
			quoteAmounts[quoteAmounts.length.sub(1)].mul(SafeMath.sub(10000, slippageBp)).div(10000),
			path,
			receiver,
			block.timestamp + 600
		);
		return amounts[amounts.length - 1];
	}

	function _swapTokenForBNB(
		address token,
		uint256 amount,
		address receiver,
		uint256 slippageBp
	) private returns (uint256) {
		address[] memory path;
		if (routePairAddresses[token] != address(0)) {
			// E.g. [EMP/ESHARE, ETH, WBNB]
			path = new address[](3);
			path[0] = token;
			path[1] = routePairAddresses[token];
			path[2] = WBNB;
		} else {
			path = new address[](2);
			path[0] = token;
			path[1] = WBNB;
		}

		uint[] memory quoteAmounts = ROUTER.getAmountsOut(amount, path);
		uint256[] memory amounts = ROUTER.swapExactTokensForETH(
			amount,
			quoteAmounts[quoteAmounts.length.sub(1)].mul(SafeMath.sub(10000, slippageBp)).div(10000),
			path,
			receiver,
			block.timestamp + 600
		);
		return amounts[amounts.length - 1];
	}

	/*
	 * Generic swap function that can swap between any two tokens with a maximum of three intermediate hops
	 * Not very useful for our current use case as bolt input currencies will only be ETH, WBNB, EMP, ESHARE
	 * However having this function helps us open up to more input currencies
	 */
	function _swap(
		address _from,
		uint256 amount,
		address _to,
		address receiver,
		uint256 slippageBp
	) private returns (uint256) {
		address intermediate = routePairAddresses[_from];
		if (intermediate == address(0)) {
			intermediate = routePairAddresses[_to];
		}

		address[] memory path;
		if (intermediate != address(0) && (_from == WBNB || _to == WBNB)) {
			// E.g. [WBNB, ETH, ESHARE/EMP] or [ESHARE/EMP, ETH, WBNB]
			path = new address[](3);
			path[0] = _from;
			path[1] = intermediate;
			path[2] = _to;
		} else if (
			intermediate != address(0) &&
			(_from == intermediate || _to == intermediate)
		) {
			// E.g. [ETH, ESHARE/EMP] or [ESHARE/EMP, ETH]
			path = new address[](2);
			path[0] = _from;
			path[1] = _to;
		} else if (
			intermediate != address(0) &&
			routePairAddresses[_from] == routePairAddresses[_to]
		) {
			// E.g. [EMP, ETH, ESHARE] or [ESHARE, ETH, EMP]
			path = new address[](3);
			path[0] = _from;
			path[1] = intermediate;
			path[2] = _to;
		} else if (
			routePairAddresses[_from] != address(0) &&
			routePairAddresses[_to] != address(0) &&
			routePairAddresses[_from] != routePairAddresses[_to]
		) {
			// E.g. routePairAddresses[xToken] = xRoute
			// [ESHARE/ESHARE, ETH, WBNB, xRoute, xToken]
			path = new address[](5);
			path[0] = _from;
			path[1] = routePairAddresses[_from];
			path[2] = WBNB;
			path[3] = routePairAddresses[_to];
			path[4] = _to;
		} else if (
			intermediate != address(0) &&
			routePairAddresses[_from] != address(0)
		) {
			// E.g. [ESHARE/EMP, ETH, WBNB, xTokenWithWBNBLiquidity]
			path = new address[](4);
			path[0] = _from;
			path[1] = intermediate;
			path[2] = WBNB;
			path[3] = _to;
		} else if (
			intermediate != address(0) && routePairAddresses[_to] != address(0)
		) {
			// E.g. [xTokenWithWBNBLiquidity, WBNB, ETH, ESHARE/EMP]
			path = new address[](4);
			path[0] = _from;
			path[1] = WBNB;
			path[2] = intermediate;
			path[3] = _to;
		} else if (_from == WBNB || _to == WBNB) {
			// E.g. [WBNB, xTokenWithWBNBLiquidity] or [xTokenWithWBNBLiquidity, WBNB]
			path = new address[](2);
			path[0] = _from;
			path[1] = _to;
		} else {
			// E.g. [xTokenWithWBNBLiquidity, WBNB, yTokenWithWBNBLiquidity]
			path = new address[](3);
			path[0] = _from;
			path[1] = WBNB;
			path[2] = _to;
		}

		uint[] memory quoteAmounts = ROUTER.getAmountsOut(amount, path);
		uint256[] memory amounts = ROUTER.swapExactTokensForTokens(
			amount,
			quoteAmounts[quoteAmounts.length.sub(1)].mul(SafeMath.sub(10000, slippageBp)).div(10000),
			path,
			receiver,
			block.timestamp + 600
		);
		return amounts[amounts.length - 1];
	}

	/*
	 * ========================
	 *     OWNER FUNCTIONS
	 * ========================
	 */

	/**
	 * Helps store intermediate route information to convert a token to WBNB
	 */
	function setRoutePairAddress(address asset, address route)
		external
		onlyOwner
	{
		routePairAddresses[asset] = route;
	}

	/**
	 * Approves a new input token for the zapper.
	 * Use this method to add new input tokens to be accepted by the zapper
	 */
	function approveNewInputToken(address token) external onlyOwner {
		if (IERC20(token).allowance(address(this), address(ROUTER)) == 0) {
			IERC20(token).safeApprove(address(ROUTER), type(uint256).max);
		}
	}

	/**
	 *
	 *  Recovers stuck tokens in the contract
	 *
	 */
	function withdraw(address token) external onlyOwner {
		if (token == address(0)) {
			payable(owner()).transfer(address(this).balance);
			return;
		}

		IERC20(token).safeTransfer(
			owner(),
			IERC20(token).balanceOf(address(this))
		);
	}

	function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}
}