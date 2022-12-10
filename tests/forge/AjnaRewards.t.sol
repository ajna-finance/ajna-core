// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import 'src/AjnaRewards.sol';
import 'src/IAjnaRewards.sol';

import 'src/base/interfaces/IPositionManager.sol';
import 'src/base/PositionManager.sol';

contract AjnaRewardsTest {

    address          internal _ajna = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;
    ERC20            internal _ajnaToken;

    AjnaRewards      internal _ajnaRewards;
    PositionManager  internal _positionManager;

    function setUp() external {
        _ajnaToken       = ERC20(_ajna);
        _positionManager = new PositionManager();
        _ajnaRewards     = new AjnaRewards(_ajna, _positionManager);
    }

    function _mintAndMemorializePositionNFT() internal returns (uint256) {
        // _ajnaToken.mint(address(this), 1000);
        // _ajnaToken.approve(address(_positionManager), 1000);
        // return _positionManager.mintPositionNFT(1000);
    }

    function testDepositToken() external {

        // TODO: implemet this test
    
    }

    function testWithdrawToken() external {

        // TODO: implemet this test
    
    }

    function testClaimRewards() external {

        // TODO: implemet this test
    
    }

}
