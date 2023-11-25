// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";

// This is a practice contract for flash swap arbitrage
contract Arbitrage is IUniswapV2Callee, Ownable {
    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    struct CallbackData {
        address priceLowerPool;
        address priceHigherPool;
        uint256 repayAmount;
        uint256 profitAmount;
    }

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
        // 1. check sender must be a contract
        require(sender == address(this), "Sender must be this contract");
        // 2. decode calldata
        CallbackData memory callbackData = abi.decode(data, (CallbackData));
        // 3. check msg.sender must be a uniswap pair
        require(msg.sender == callbackData.priceLowerPool, "Sender must be a uniswap pair");
        // 4. check amount0 or amount1 is greater than 0
        require(amount0 > 0 || amount1 > 0, "Amount0 or Amount1 must be greater than 0");
        // transfer WETH from this contract to high price pool
        IERC20(IUniswapV2Pair(callbackData.priceLowerPool).token0()).transfer(callbackData.priceHigherPool, amount0);
        // 5. swap WETH to USDC in higher price pool
        // please notice the parameter order of swap()
        IUniswapV2Pair(callbackData.priceHigherPool).swap(0, callbackData.profitAmount, address(this), new bytes(0));
        // 6. repay USDC from this contract to lower price pool
        // msg.sender is low price pool
        IERC20(IUniswapV2Pair(callbackData.priceHigherPool).token1()).transfer(msg.sender, callbackData.repayAmount);
    }

    // Method 1 is
    //  - borrow WETH from lower price pool
    //  - swap WETH for USDC in higher price pool
    //  - repay USDC to lower pool
    // Method 2 is
    //  - borrow USDC from higher price pool
    //  - swap USDC for WETH in lower pool
    //  - repay WETH to higher pool
    // for testing convenient, we implement the method 1 here
    function arbitrage(address priceLowerPool, address priceHigherPool, uint256 borrowETH) external {
        // TODO

        // 1. check borrowETH is greater than 0
        require(borrowETH > 0, "borrowETH must be greater than 0");
        // 2. get repay amount from lowerpool
        // 2.1 getReserve() from lowerpool
        (uint112 reserveEth_l, uint112 reserveUSDC_l, ) = IUniswapV2Pair(priceLowerPool).getReserves();
        // notice that the parameter order is according to borrow token - WETH
        uint256 repayUSDCamount = _getAmountIn(borrowETH, reserveUSDC_l, reserveEth_l);
        // 3. get profit amount from higherpool
        // 3.1 getReserve() from higherpool
        (uint112 reserveEth_h, uint112 reserveUSDC_h, ) = IUniswapV2Pair(priceHigherPool).getReserves();
        // notice that the parameter order is according to return token - USDC
        uint256 profitUSDCamount = _getAmountOut(borrowETH, reserveEth_h, reserveUSDC_h);
        // 4. check this can earn profit
        require(profitUSDCamount > repayUSDCamount, "profitamount must be greater than repayamount");
        // 5. decode callback data
        CallbackData memory data = CallbackData(priceLowerPool, priceHigherPool, repayUSDCamount, profitUSDCamount);
        // 6. call lowerpool pair borrow ETH to this contract
        // please notice the parameter order of swap()
        IUniswapV2Pair(priceLowerPool).swap(borrowETH, 0, address(this), abi.encode(data));
    }

    //
    // INTERNAL PURE
    //

    // copy from UniswapV2Library
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // copy from UniswapV2Library
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
