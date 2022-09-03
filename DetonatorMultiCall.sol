// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

interface IDetonator {
    struct User {
        address referrer;
        uint256 referral_rewards;
        uint256 num_referrals;
        uint256 deposit_time;
        uint256 claim_time;
        uint256 total_deposits;
        uint256 total_deposits_scaled;
        uint256 total_withdraws;
        uint256 total_withdraws_scaled;
        uint256 last_distPoints;
        uint256 lottery_winnings;
        uint256 largest_winnings;
        uint256 day_deposits;
    }
    function userIndices(uint256 index) external view returns (address);
    function users(address user) external view returns (User memory);
    function userInfoTotals(address _addr) external view returns (
        uint256 total_withdraws,
        uint256 total_withdraws_scaled,
        uint256 total_deposits,
        uint256 total_deposits_scaled,
        uint256 referral_rewards,
        uint256 lottery_winnings,
        uint256 largest_winnings
    );
    function getDayDeposits(address account) external view returns (uint256);
}

contract DetonatorMultiCall {
    struct UserData {
        address key;
        uint256 total_deposits;
        uint256 total_deposits_scaled;
        uint256 total_withdraws;
        uint256 total_withdraws_scaled;
    }
    struct DayDeposits {
        address key;
        uint256 day_deposits;
    }

    IDetonator public immutable DETONATOR;

    constructor(IDetonator _detonator) public { DETONATOR = _detonator; }

    function getUsersTotals(uint256[] memory indicies) external view returns (UserData[] memory) {
        UserData[] memory data = new UserData[](indicies.length);
        for (uint256 i = 0; i < indicies.length; i++) {
            address _addr = DETONATOR.userIndices(indicies[i]);
            (
                uint256 _total_withdraws,
                uint256 _total_withdraws_scaled,
                uint256 _total_deposits,
                uint256 _total_deposits_scaled,
                ,,
            ) = DETONATOR.userInfoTotals(_addr);
            
            data[i] = UserData({
                key: _addr,
                total_deposits: _total_deposits,
                total_deposits_scaled: _total_deposits_scaled,
                total_withdraws: _total_withdraws,
                total_withdraws_scaled: _total_withdraws_scaled
            });
        }
        return data;
    }

    function getDayDeposits(uint256[] memory indicies) external view returns (DayDeposits[] memory) {
        DayDeposits[] memory data = new DayDeposits[](indicies.length);
        for (uint256 i = 0; i < indicies.length; i++) {
            address _addr = DETONATOR.userIndices(indicies[i]);
            data[i] = DayDeposits({
                key: _addr,
                day_deposits: DETONATOR.getDayDeposits(_addr)
            });
        }
        return data;
    }
}