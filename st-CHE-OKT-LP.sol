// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma experimental ABIEncoderV2;

import "okfarm/library.sol";

interface IController {
    function withdraw(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
    function earn(address, uint256) external;
    function want(address) external view returns (address);
    function rewards() external view returns (address);
    function vaults(address) external view returns (address);
    function strategies(address) external view returns (address);
}

interface Uni {
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external;

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

interface UniPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
}

struct PoolInfo {
    address lpToken;
    uint256 allocPoint;
    uint256 lastRewardBlock;
    uint256 accRewardPerShare;
}

interface IPool {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
    function userInfo(uint pid, address user) external view returns (UserInfo memory);
    function poolInfo(uint pid) external view returns (PoolInfo memory);
}

contract StrategyCherryLp {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant uniRouter = 0x865bfde337C8aFBffF144Ff4C29f9404EBb22b15;

    uint256 public strategistReward = 500;
    uint256 public withdrawalFee = 0;
    uint256 public constant FEE_DENOMINATOR = 10000;

    IPool public pool = IPool(0x8cddB4CD757048C4380ae6A69Db8cD5597442f7b);
    uint public poolId;

    address public rewardToken = 0x8179D97Eb6488860d816e3EcAFE694a4153F216c;

    address public want;

    address public governance;
    address public controller;

    address[] public path0;
    address[] public path1;

    address public token0;
    address public token1;

    constructor(
        address _controller,
        address _want,
        uint _pid,
        address[] memory _path0,
        address[] memory _path1
    ) {
        governance = msg.sender;
        controller = _controller;
        want = _want;
        poolId = _pid;
        path0 = _path0;
        path1 = _path1;

        if (_path0.length == 0) {
            token0 = rewardToken;
        } else {
            require(_path0[0] == rewardToken);
            token0 = _path0[_path0.length - 1];
        }
        if (_path1.length == 0) {
            token1 = rewardToken;
        } else {
            require(_path1[0] == rewardToken);
            token1 = _path1[_path1.length - 1];
        }
        require(UniPair(_want).token0() == token0 || UniPair(_want).token0() == token1);
        require(UniPair(_want).token1() == token0 || UniPair(_want).token1() == token1);

        require(pool.poolInfo(_pid).lpToken == want);

        IERC20(rewardToken).safeApprove(uniRouter, 0);
        IERC20(rewardToken).safeApprove(uniRouter, type(uint).max);

        IERC20(token0).safeApprove(uniRouter, 0);
        IERC20(token0).safeApprove(uniRouter, type(uint).max);

        IERC20(token1).safeApprove(uniRouter, 0);
        IERC20(token1).safeApprove(uniRouter, type(uint).max);

        IERC20(want).safeApprove(address(pool), 0);
        IERC20(want).safeApprove(address(pool), type(uint).max);
    }

    function setWithdrawalFee(uint256 _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        require(_withdrawalFee < FEE_DENOMINATOR);
        withdrawalFee = _withdrawalFee;
    }

    function setStrategistReward(uint256 _strategistReward) external {
        require(msg.sender == governance, "!governance");
        require(_strategistReward < FEE_DENOMINATOR);
        strategistReward = _strategistReward;
    }

    function e_exit() external {
        require(msg.sender == governance, "!governance");
        pool.emergencyWithdraw(poolId);
        uint balance = IERC20(want).balanceOf(address(this));
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        IERC20(want).safeTransfer(_vault, balance);
    }

    function deposit() public {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            pool.deposit(poolId, IERC20(want).balanceOf(address(this)));
        }
    }

    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(rewardToken != address(_asset), "want");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == controller, "!controller");
        uint256 _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        uint256 _fee = _amount.mul(withdrawalFee).div(FEE_DENOMINATOR);

        if (_fee > 0) {
            IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
        }
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        if (_amount > _fee) {
            IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
        }
    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        uint256 before = IERC20(want).balanceOf(address(this));
        if (_amount > 0) {
            pool.withdraw(poolId, _amount);
        }
        return IERC20(want).balanceOf(address(this)).sub(before);
    }

    function withdrawAll() external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();

        balance = IERC20(want).balanceOf(address(this));

        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        if (balance > 0) {
            IERC20(want).safeTransfer(_vault, balance);
        }
    }

    function _withdrawAll() internal {
        _withdrawSome(balanceOfPool());
    }

    modifier onlyBenevolent {
        require(msg.sender == tx.origin || msg.sender == governance);
        _;
    }

    function harvest() public onlyBenevolent {
        pool.deposit(poolId, 0);
        uint256 rewardAmt = IERC20(rewardToken).balanceOf(address(this));

        if (rewardAmt == 0) {
            return;
        }
        uint256 fee = rewardAmt.mul(strategistReward).div(FEE_DENOMINATOR);

        IERC20(rewardToken).safeTransfer(IController(controller).rewards(), fee);

        rewardAmt = IERC20(rewardToken).balanceOf(address(this));

        if (rewardAmt == 0) {
            return;
        }

        if (token0 != rewardToken) {
            Uni(uniRouter).swapExactTokensForTokens(
                rewardAmt.div(2),
                uint256(0),
                path0,
                address(this),
                block.timestamp.add(1800)
            );
        }
        if (token1 != rewardToken) {
            Uni(uniRouter).swapExactTokensForTokens(
                rewardAmt.div(2),
                uint256(0),
                path1,
                address(this),
                block.timestamp.add(1800)
            );
        }

        Uni(uniRouter).addLiquidity(
            token0,
            token1,
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            0,
            0,
            address(this),
            block.timestamp.add(1800)
        );
        deposit();
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256) {
        UserInfo memory info = pool.userInfo(poolId, address(this));
        return info.amount;
    }

    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
}