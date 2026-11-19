// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPancakeFactory {
    function getPair(address a, address b) external view returns (address);
    function createPair(address a, address b) external returns (address);
}

interface IPancakePair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 r0, uint112 r1, uint32 ts);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function swap(uint256 out0, uint256 out1, address to, bytes calldata data) external;
    function mint(address to) external returns (uint256 liquidity);
    function sync() external;
    function totalSupply() external view returns (uint256);
}

interface IWBNB {
    function withdraw(uint256 amount) external;
}

interface IAgentRegistrar {
    function ownerOf(uint256 tokenId) external view returns (address);
}

library PancakeMath {
    function amountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 feeBps)
        internal
        pure
        returns (uint256)
    {
        uint256 inWithFee = amountIn * (10_000 - feeBps);
        return (inWithFee * reserveOut) / (reserveIn * 10_000 + inWithFee);
    }
}
