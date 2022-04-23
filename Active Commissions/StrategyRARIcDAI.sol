// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearn/yearn-vaults/blob/main/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    constructor(address _vault) public BaseStrategy(_vault) {
        // You can set these parameters on deployment to whatever you want
        // maxReportDelay = 6300;
        // profitFactor = 100;
        // debtThreshold = 0;
        ETHDAI = Oracle(0x773616e4d11a78f511299002da57a0a94577f1f4);

        //Nothing else needed here
    }

    IERC20 want = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); //This is DAI
    Rari fcDAI = Rari(0x0000000000000000000000000000000000000000); // Replace with the actual fcDAI address please.
    Comp cDAI = Comp(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643); // This is cDAI

    // cDAI and fcDAI are auto compounding by default, so this contract needs to track its profits itself using this variable
    uint StampBalance;
    // a chainlink oracle for ETH/DAI
    Oracle ETHDAI; 

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {

        return "StrategyRARIcDAI";
    }

    function estimatedTotalAssets() public view override returns (uint256) {

        return (fcDAI.balanceOf(address(this)) * (fcDAI.exchangeRateCurrent()/10**18) * (cDAI.exchangeRateCurrent()/10**18));
    }

    function prepareReturn(uint256 _debtOutstanding) internal override returns(uint256 _profit, uint256 _loss, uint256 _debtPayment){
        // TODO: Do stuff here to free up any returns back into `want`
        // NOTE: Return `_profit` which is value generated by all positions, priced in `want`
        // NOTE: Should try to free up at least `_debtOutstanding` of underlying position

        _profit = estimatedTotalAssets() - StampBalance;
        fcDAI.redeemUnderlying(_profit * cDAI.exchangeRateCurrent);
        cDAI.redeemUnderlying(_profit);

        StampBalance = estimatedTotalAssets();

        fcDAI.redeemUnderlying(_debtOutstanding * cDAI.exchangeRateCurrent);
        cDAI.redeemUnderlying(_debtOutstanding);

        StampBalance -= _debtOutstanding;

        _loss = 0; // It is impossible to lose money from this stratagy, so loss is always zero.
        // (Unless compound gets hacked.. but then this vault will probably be the least of your concerns.)

        _debtPayment = 0; // No debts are paid

        return (_profit, _loss, _debtPayment);
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {

        DAI.transferFrom(vault, address(this), _debtOutstanding);
        cDAI.mint(DAI.balanceOf(address(this)));
        fcDAI.mint(cDAI.balanceOf(address(this)));

        debtOutstanding += _debtOutstanding;

        if(StampBalance == 0){StampBalance = estimatedTotalAssets();}
        else{

            StampBalance += (_debtOutstanding * (fcDAI.exchangeRateCurrent()/10**18) * (cDAI.exchangeRateCurrent()/10**18));
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // TODO: Do stuff here to free up to `_amountNeeded` from all positions back into `want`
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`

        fcDAI.redeemUnderlying(_amountNeeded * cDAI.exchangeRateCurrent);
        cDAI.redeemUnderlying(_amountNeeded);

        StampBalance -= _amountNeeded;

        uint256 totalAssets = want.balanceOf(address(this));
        if (_amountNeeded > totalAssets) {
            _liquidatedAmount = totalAssets;
            _loss = _amountNeeded.sub(totalAssets);
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        fcDAI.redeem(fcDAI.balanceOf(address(this)));
        cDAI.redeem(cDAI.balanceOf(address(this)));
        return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one

        fcDAI.transfer(_newStrategy, fcDAI.balanceOf(address(this)));
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens() internal view override returns(address[] memory){

        address[] memory protected = new address[](2);

        protected[0] = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
        protected[1] = 0x0000000000000000000000000000000000000000; // Replace with the actual fcDAI address please.
        
        return protected;
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei) public view virtual override returns (uint256){
        // TODO create an accurate price oracle
        (,int price,,,) = ETHDAI.latestRoundData();

        _amtInWei *= (uint(price)/10**8);

        return _amtInWei;
    }
}

interface Oracle{

    // Chainlink Dev Docs https://docs.chain.link/docs/
    function latestRoundData() external returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface Rari{

    // Rari Dev Docs https://docs.rari.capital/fuse/#general
    function mint(uint) external returns (uint);
    function redeem(uint) external returns (uint);
    function redeemUnderlying(uint) external returns (uint);
    function transferFrom(address, address, uint256) external;
    function transfer(address, uint256) external;
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function exchangeRateCurrent() external returns (uint);
    function balanceOf(address) external view returns(uint);
    function getAccountLiquidity(address account) external returns (uint, uint, uint);
    function borrowBalanceCurrent(address account) external returns (uint);
}

interface Comp {

    // Comp dev docs https://medium.com/compound-finance/supplying-assets-to-the-compound-protocol-ec2cf5df5aa#afff
    function mint(uint256) external returns (uint256);
    function exchangeRateCurrent() external returns (uint256);
    function supplyRatePerBlock() external returns (uint256);
    function redeem(uint) external returns (uint);
    function redeemUnderlying(uint) external returns (uint);
    function approve(address, uint256) external returns (bool success);
    function transferFrom(address, address, uint256) external;
    function transfer(address, uint256) external;
    function balanceOf(address) external view returns(uint);
}
