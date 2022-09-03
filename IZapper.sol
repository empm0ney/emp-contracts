// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

/**
 *
 */
interface IZapper {
	/**
	 * Create LP (_to) from BNB
	 */
	function zapBNBToLP(address _to, uint256 _slippageBp) external payable;

	/**
	 * Creates LP (_to) from a single asset (_from). Use this when the _from asset is not BNB
	 */
	function zapTokenToLP(
		address _from,
		uint256 amount,
		address _to,
		uint256 slippageBp
	) external;

	/**
	 * Breaks LP (_from) and returns the single assets to the sender
	 */
	function breakLP(address _from, uint256 amount) external;
}