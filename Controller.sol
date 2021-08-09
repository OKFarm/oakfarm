// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "okfarm/library.sol";

interface Strategy {
    function want() external view returns (address);
    function deposit() external;
    function withdraw(address) external;
    function withdraw(uint) external;
    function withdrawAll() external returns (uint);
    function balanceOf() external view returns (uint);
}

interface IVault {
    function token() external view returns (address);
}

contract SimpleController {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    address public governance;
    address public strategist;
    
    mapping (address => address) public vaults;
    mapping (address => address) public strategies;
    
    constructor() {
        governance = msg.sender;
        strategist = msg.sender;
    }
    
    function setStrategist(address _strategist) public {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }
    
    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
    
    function setVault(address _token, address _vault) public {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        require(vaults[_token] == address(0), "exist vault");
        require(IVault(_vault).token() == _token, "!vault");
        vaults[_token] = _vault;
    }
    
    function setStrategy(address _token, address _strategy) public {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        require(Strategy(_strategy).want() == _token, "!strategy");
        
        address _current = strategies[_token];
        if (_current != address(0)) {
           Strategy(_current).withdrawAll();
        }
        strategies[_token] = _strategy;
    }
    
    function earn(address _token, uint _amount) public {
        address _strategy = strategies[_token];
        IERC20(_token).safeTransfer(_strategy, _amount);
        Strategy(_strategy).deposit();
    }
    
    function balanceOf(address _token) external view returns (uint) {
        return Strategy(strategies[_token]).balanceOf();
    }
    
    function withdrawAll(address _token) public {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        Strategy(strategies[_token]).withdrawAll();
    }
    
    function inCaseTokensGetStuck(address _token, uint _amount) public {
        require(msg.sender == strategist || msg.sender == governance, "!governance");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }
    
    function inCaseStrategyTokenGetStuck(address _strategy, address _token) public {
        require(msg.sender == strategist || msg.sender == governance, "!governance");
        Strategy(_strategy).withdraw(_token);
    }
    
    function withdraw(address _token, uint _amount) public {
        require(msg.sender == vaults[_token], "!vault");
        Strategy(strategies[_token]).withdraw(_amount);
    }

    function rewards() public view returns (address) {
        return governance;
    }
}