// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

    // This contract is a yield strategy for FEI dao.

    // Here are the steps to success:

    // 1) Deposit cDAI into Rari.capital 
    // 2) Borrow cDAI off of FEI from rari.capital
    // 3) Unwrap cDAI to DAI using Compound
    // 4) Swap DAI to LUSD using Curve.fi
    // 5) Deposit LUSD into the liquity stability pool

// IMPORTANT:
// In order for this contract to work, the tokens FEI and BAMM must be approved for use on this contract.
// The FEI/cDAI rari market must also be intialized with sufficent liquidity before this contract is deployed

    // now to the code:

contract PrintMoney {

    constructor(){

        //Input FEI DAO address
        Slippage = 995; //Translates to 0.5% slippage
        LTV = 20; //Translates to 80% target LTV
    }

//                                        //
//// Variables that this contract uses: ////
//                                        //

    ERC20 DAI  = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 FEI  = ERC20(0x956F47F50A910163D8BF957Cf5846D573E7f87CA);
    ERC20 LUSD = ERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);
    ERC20 USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    Comp cDAI  = Comp(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    Rari fcDAI = Rari(0x0000000000000000000000000000000000000000); // Replace with the actual fcDAI address please.
    Rari fcFEI = Rari(0x0000000000000000000000000000000000000000); // Replace with the actual fcFEI address pretty please.

    Curve LUSD3CRV = Curve(0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA); 

    StbPool POOL = StbPool(0x0000000000000000000000000000000000000000); // Replace this with the actual BAMM address please ;-; 

    address DAO;
    uint Slippage;
    uint LTV;

//                                                //
//// Visible Functions that this contract uses: ////
//                                                //

    function deposit(uint amount) public {

    //  Step 1: Deposit FEI into rari.capital.
        FEI.transferFrom(msg.sender, address(this), amount);
        FEI.approve(address(fcFEI), amount);
        fcFEI.mint(amount);

    //  Step 2: Borrow cDAI at 80% LTV and unwrap it.
        // NOTE: 80% LTV is very safe but could still be risky if a stablecoin depegs.
        uint AvalBorrow;
        uint a;
        (a, AvalBorrow, a) = fcDAI.getAccountLiquidity(address(this));
        fcDAI.borrow((AvalBorrow-(AvalBorrow/LTV)));
        cDAI.redeem(cDAI.balanceOf(address(this)));

    //  Step 3: Swap DAI to LUSD on Curve.fi
        LUSD3CRV.exchange_underlying(1, 0, DAI.balanceOf(address(this)), (DAI.balanceOf(address(this))*(Slippage/1000)));

    //  Step 4: Deposit all LUSD held by this address into the LUSD stability pool
        POOL.deposit(LUSD.balanceOf(address(this)));

    //  Step 5: Send the LUSD receipt tokens to the DAO treasury
        POOL.transfer(DAO, POOL.balanceOf(address(this)));

    }

    // Sweep ETH from this address to the DAO address

    function Sweep() public payable {

        (bool sent, bytes memory data) = DAO.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");

    }

    function withdraw(uint percentage) public {

    //  Step 1: Get the receipt tokens from the DAO and withdraw LUSD and ETH rewards from the stability pool

        POOL.transferFrom(DAO, address(this), (POOL.balanceOf(DAO)*percentage/100));
        POOL.withdraw(POOL.balanceOf(address(this)));



    //  Step 2: Swap all LUSD for DAI

        LUSD3CRV.exchange_underlying(0, 1, LUSD.balanceOf(address(this)), (LUSD.balanceOf(address(this))*(Slippage/1000)));

    //  Step 3: Wrap DAI into cDAI and pay back the loan on rari.capital.

        DAI.approve(address(cDAI), DAI.balanceOf(address(this)));
        cDAI.mint(DAI.balanceOf(address(this)));
        cDAI.approve(address(fcDAI), cDAI.balanceOf(address(this)));

        if(cDAI.balanceOf(address(this)) <= fcDAI.borrowBalanceCurrent(address(this))){

            fcDAI.repayBorrow(cDAI.balanceOf(address(this)));
        }

        else{

            fcDAI.repayBorrow(fcDAI.borrowBalanceCurrent(address(this)));
        }


    // Step 4: Withdraw a safe amount of FEI (or all if percentage is 100%) and return it to its owner.

    }
    

// Internal and External Functions this contract uses:
// (msg.sender SHOULD NOT be used/assumed in any of these functions.)


}

//// Contracts that this contract uses, contractception!

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

interface Curve{

    function exchange_underlying(int128, int128, uint256, uint256) external;
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

interface ERC20{

    function transferFrom(address, address, uint256) external;
    function transfer(address, uint256) external;
    function balanceOf(address) external view returns(uint);
    function approve(address, uint256) external returns (bool success);
}

interface StbPool {

    // IBAMM Interface https://github.com/fei-protocol/fei-protocol-core/blob/develop/contracts/pcv/liquity/IBAMM.sol

    function fetchPrice() external view returns (uint256);

    /// @notice returns amount of ETH received for an LUSD swap
    function getSwapEthAmount(uint256 lusdQty) external view returns (uint256 ethAmount, uint256 feeEthAmount);

    /// @notice Liquity Stability Pool Address
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);

    /// @notice Reward token
    function bonus() external view returns (address);

    // Mutative Functions

    /// @notice deposit LUSD for shares in BAMM
    function deposit(uint256 lusdAmount) external;

    /// @notice withdraw shares  in BAMM for LUSD + ETH
    function withdraw(uint256 numShares) external;

    function transfer(address to, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external;

}

// Stability Pool Interface Ref: https://github.com/fei-protocol/fei-protocol-core/blob/develop/contracts/pcv/liquity/IStabilityPool.sol