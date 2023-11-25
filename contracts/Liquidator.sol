// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";
import { IUniswapV2Factory } from "v2-core/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router01 } from "v2-periphery/interfaces/IUniswapV2Router01.sol";
import { IWETH } from "v2-periphery/interfaces/IWETH.sol";
import { IFakeLendingProtocol } from "./interfaces/IFakeLendingProtocol.sol";

// This is liquidator contract for testing,
// all you need to implement is flash swap from uniswap pool and call lending protocol liquidate function in uniswapV2Call
// lending protocol liquidate rule can be found in FakeLendingProtocol.sol
contract Liquidator is IUniswapV2Callee, Ownable {
    address internal immutable _FAKE_LENDING_PROTOCOL;
    address internal immutable _UNISWAP_ROUTER;
    address internal immutable _UNISWAP_FACTORY;
    address internal immutable _WETH9;
    uint256 internal constant _MINIMUM_PROFIT = 0.01 ether;

    struct CallbackData {
        address pair;
        address repayToken;
        address borrowToken;
        uint256 repayAmount;
        uint256 borrowAmount;
    }

    constructor(address lendingProtocol, address uniswapRouter, address uniswapFactory) {
        _FAKE_LENDING_PROTOCOL = lendingProtocol;
        _UNISWAP_ROUTER = uniswapRouter;
        _UNISWAP_FACTORY = uniswapFactory;
        _WETH9 = IUniswapV2Router01(uniswapRouter).WETH();
    }

    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        // TODO
        // 1. check sender is must be a contract
        require(sender == address(this), "Sender must be this contract");
        // 2. decode callback data
        CallbackData memory callbackData = abi.decode(data, (CallbackData));
        // 3. check msg.sender is uniswap pair
        require(msg.sender == callbackData.pair, "msg.sigender must be uniswap pair");
        // 4 check amount0 or amount1 is greater than 0
        require(amount0 > 0 || amount1 > 0, "Amount0 or amount1 must be greater than 0");
        // 5. approve borrow token to lending protocol
        IERC20(callbackData.borrowToken).approve(_FAKE_LENDING_PROTOCOL, callbackData.borrowAmount);
        // 6. call lending protocol liquidatePosition function
        IFakeLendingProtocol(_FAKE_LENDING_PROTOCOL).liquidatePosition();
        // 7. deposit ETH to WETH
        IWETH(callbackData.repayToken).deposit{ value: callbackData.repayAmount }();
        // 8. transfer repay token WETH to uniswap pair
        IERC20(callbackData.repayToken).transfer(msg.sender, callbackData.repayAmount);
    }

    // we use single hop path for testing
    function liquidate(address[] calldata path, uint256 amountOut) external {
        // TODO
        // 1. check amountOut is greater than 0
        require(amountOut > 0, "AmountOut must be greater than 0");
        // 2. get pair address from uniswap factory
        address pair = IUniswapV2Factory(_UNISWAP_FACTORY).getPair(path[0], path[1]);
        // 3. get amountIn from uniswap
        uint256[] memory amountsIn = IUniswapV2Router01(_UNISWAP_ROUTER).getAmountsIn(amountOut, path);
        // 4. check amountIn is greater than amountOut + _MINIMUM_PROFIT
        require(
            amountsIn[0] > amountOut + _MINIMUM_PROFIT,
            "AmountIn must be greater than amountOut + _MINIMUM_PROFIT"
        );
        // path[0] repay token, path[1] borrow token
        // amountIn repay amount, amountOut borrow amount
        CallbackData memory data = CallbackData(pair, path[0], path[1], amountsIn[0], amountOut);
        // 5. call pair swap function
        IUniswapV2Pair(pair).swap(0, amountOut, address(this), abi.encode(data));
    }

    receive() external payable {}
}
