// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.4.16;

import "./lib/ERC/ERC20.sol";
import "./lib/Ownable.sol";

contract Octos is ERC20, Ownable {
    struct LockInfo {
        bool isLocked;
        uint256 amount;
        uint256 unlockTime;
    }

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 duration;
        bool claimed;
    }

    struct StakeConfigInfo {
        uint256 minStakeDuration;
        uint256 maxStakeDuration;
    }

    mapping(address => LockInfo) private lockedTokens;
    mapping(address => StakeInfo[]) public stakings;

    StakeConfigInfo public stakeConfigInfo;

    uint256 public interestRatePerYearBP = 100;

    constructor(
        address recipient,
        uint256 amount,
        address ownerAddress
    ) ERC20("OCTOS", "OCTOS") Ownable(ownerAddress) {
        require(recipient != address(0), "Invalid Recipient address");
        require(amount > 0, "Amount must be > 0");
        _mint(recipient, amount);

        stakeConfigInfo = StakeConfigInfo({
            minStakeDuration: 365 days,
            maxStakeDuration: 730 days
        });
    }

    function getLockedAmount(address user) public view returns (uint256) {
        if (!lockedTokens[user].isLocked) {
            return 0;
        }
        uint256 locked = lockedTokens[user].amount;
        if (locked == 0) {
            // 모든 잔고를 Lock
            locked = balanceOf(user);
        }

        if (
            (lockedTokens[user].unlockTime == 0) ||
            // 무제한 Lock
            (block.timestamp < lockedTokens[user].unlockTime)
        ) {
            return locked;
        }

        return 0;
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 locked = getLockedAmount(msg.sender);
        require(
            balanceOf(msg.sender) - amount >= locked,
            "Trying to transfer locked tokens"
        );
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 locked = getLockedAmount(from);
        require(
            balanceOf(from) - amount >= locked,
            "Trying to transfer locked tokens"
        );
        return super.transferFrom(from, to, amount);
    }

    function stake(uint256 amount, uint256 duration) external {
        require(amount > 0, "Stake amount must be greater than 0");
        require(
            duration >= stakeConfigInfo.minStakeDuration,
            "Duration below minimum stake period"
        );
        require(
            duration <= stakeConfigInfo.maxStakeDuration,
            "Duration exceeds maximum stake period"
        );
        _transfer(msg.sender, address(this), amount);

        stakings[msg.sender].push(
            StakeInfo({
                amount: amount,
                startTime: block.timestamp,
                duration: duration,
                claimed: false
            })
        );
    }

    function claimStake(uint256 index) external {
        StakeInfo storage stakeInfo = stakings[msg.sender][index];
        require(!stakeInfo.claimed, "Already claimed");
        require(
            block.timestamp >= stakeInfo.startTime + stakeInfo.duration,
            "Not yet unlocked"
        );

        uint256 reward = (stakeInfo.amount *
            interestRatePerYearBP *
            stakeInfo.duration) / (365 days * 10000);
        stakeInfo.claimed = true;
        _mint(msg.sender, reward);
        _transfer(address(this), msg.sender, stakeInfo.amount);
    }

    function getUserStakes(
        address user
    ) external view returns (StakeInfo[] memory) {
        return stakings[user];
    }

    function getStakeConfigInfo()
        external
        view
        returns (uint256 minStakeDuration, uint256 maxStakeDuration)
    {
        return (
            stakeConfigInfo.minStakeDuration,
            stakeConfigInfo.maxStakeDuration
        );
    }

    function setInterestRate(string memory _apyPercentStr) external onlyOwner {
        interestRatePerYearBP = parseInterestRate(_apyPercentStr);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

    function lock(
        address user,
        uint256 amount,
        uint256 duration
    ) external onlyOwner {
        require(balanceOf(user) >= amount, "Insufficient balance to lock");
        uint256 unlockTime = 0;
        if (duration > 0) {
            // 기간지정시, 특정 기간동안만 Lock
            unlockTime = block.timestamp + duration;
        }
        lockedTokens[user] = LockInfo({
            isLocked: true,
            amount: amount,
            unlockTime: unlockTime
        });
    }

    function unlock(address user) external onlyOwner {
        delete lockedTokens[user];
    }

    function setStakeDurationLimits(
        uint256 _min,
        uint256 _max
    ) external onlyOwner {
        require(_min > 0, "Minimum must be greater than 0");
        require(_max >= _min, "Max must be >= min");
        stakeConfigInfo.minStakeDuration = _min;
        stakeConfigInfo.maxStakeDuration = _max;
    }

    // =============================== utils ===============================
    function parseInterestRate(
        string memory s
    ) internal pure returns (uint256) {
        bytes memory b = bytes(s);
        uint256 result = 0;
        uint256 decimals = 0;
        bool hasDot = false;

        for (uint i = 0; i < b.length; i++) {
            if (b[i] == ".") {
                require(!hasDot, "Multiple decimal points");
                hasDot = true;
            } else {
                require(b[i] >= "0" && b[i] <= "9", "Invalid character");
                if (hasDot) {
                    decimals++;
                    require(decimals <= 2, "Too many decimal places");
                }
                result = result * 10 + (uint8(b[i]) - 48);
            }
        }

        if (decimals == 1) {
            result *= 10;
        } else if (decimals == 0) {
            result *= 100;
        }

        return result;
    }
}
