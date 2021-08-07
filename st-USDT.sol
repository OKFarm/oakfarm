// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma experimental ABIEncoderV2;


contract StrategyCherrySingle {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant uniRouter = 0x865bfde337C8aFBffF144Ff4C29f9404EBb22b15;

    uint256 public strategistReward = 2000;
    uint256 public withdrawalFee = 0;
    uint256 public constant FEE_DENOMINATOR = 10000;

    IPool public pool = IPool(0x5dA6c582586a3dc7A9250AF0bed064A0363a751e);

    address public rewardToken = 0x8179D97Eb6488860d816e3EcAFE694a4153F216c;

    address public want;

    address public governance;
    address public controller;
    
    address[] public path;

    constructor(
        address _controller,
        address _want,
        address[] memory _path
    ) {
        governance = msg.sender;
        controller = _controller;
        want = _want;
        path = _path;
        
        IERC20(rewardToken).safeApprove(uniRouter, 0);
        IERC20(rewardToken).safeApprove(uniRouter, type(uint).max);

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
        pool.emergencyWithdraw();
        uint balance = IERC20(want).balanceOf(address(this));
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        IERC20(want).safeTransfer(_vault, balance);
    }

    function deposit() public {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            pool.deposit(_want);
        }
    }

    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(rewardToken != address(_asset), "rewardToken");
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
            pool.withdraw(_amount);
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
        pool.deposit(0);
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
        
        if (rewardToken != want) {
            Uni(uniRouter).swapExactTokensForTokens(
                rewardAmt,
                uint256(0),
                path,
                address(this),
                block.timestamp.add(1800)
            );
        }

        deposit();
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256) {
        UserInfo memory info = pool.userInfo(address(this));
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