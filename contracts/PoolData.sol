/* Copyright (C) 2017 NexusMutual.io

  This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

  This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
    along with this program.  If not, see http://www.gnu.org/licenses/ */

pragma solidity 0.4.24;

import "./Iupgradable.sol";
import "./imports/openzeppelin-solidity/math/SafeMath.sol";


contract DSValue {
    function peek() public view returns (bytes32, bool);
    function read() public view returns (bytes32);
}


contract PoolData is Iupgradable {
    using SafeMath for uint;

    struct ApiId {
        bytes4 typeOf;
        bytes4 currency;
        uint id;
        uint64 dateAdd;
        uint64 dateUpd;
    }

    struct CurrencyAssets {
        address currAddress;
        uint baseMin;
        uint varMin;
    }

    struct InvestmentAssets {
        address currAddress;
        bool status;
        uint64 minHoldingPercX100;
        uint64 maxHoldingPercX100;
        uint8 decimals;
    }

    struct IARankDetails {
        bytes4 maxIACurr;
        uint64 maxRate;
        bytes4 minIACurr;
        uint64 minRate;
    }

    struct McrData {
        uint mcrPercx100;
        uint mcrEther;
        uint vFull; //Pool funds
        uint64 date;
    }
    
    modifier onlyOwner {
        require(ms.isOwner(msg.sender), "Not Owner");
        _;
    }

    IARankDetails[] internal allIARankDetails;
    McrData[] public allMCRData;

    bytes4[] internal allInvestmentCurrencies;
    bytes4[] internal allCurrencies;
    bytes32[] public allAPIcall;
    mapping(bytes32 => ApiId) public allAPIid;
    mapping(uint64 => uint) internal datewiseId;
    mapping(bytes16 => uint) internal currencyLastIndex;
    mapping(bytes4 => CurrencyAssets) internal allCurrencyAssets;
    mapping(bytes4 => InvestmentAssets) internal allInvestmentAssets;
    mapping(bytes4 => uint) internal caAvgRate;
    mapping(bytes4 => uint) internal iaAvgRate;

    address internal notariseMCR;
    address public daiFeedAddress;
    uint private constant DECIMAL1E18 = uint(10) ** 18;
    uint public uniswapDeadline;
    uint public liquidityTradeCallbackTime;
    uint public lastLiquidityTradeTrigger;
    uint64 internal lastDate;
    uint64 public variationPercX100;
    uint64 public iaRatesTime;
    uint public minCap;
    uint64 public mcrTime;
    uint64 public minMCRReq;
    uint64 public sfX100000;
    uint public shockParameter;
    uint64 public growthStep;
    uint64 public mcrFailTime; 

    constructor() public {
        growthStep = 1500000;
        sfX100000 = 140;
        mcrTime = 24 hours;
        mcrFailTime = 6 hours;
        minMCRReq = 0; //value in percentage e.g 60% = 60*100 
        allMCRData.push(McrData(0, 0, 0, 0));
        minCap = DECIMAL1E18;
        shockParameter = 50;
        variationPercX100 = 100; //1%
        iaRatesTime = 24 hours; //24 hours in seconds
        uniswapDeadline = 20 minutes;
        liquidityTradeCallbackTime = 4 hours;
        allCurrencies.push("ETH");
        allCurrencyAssets["ETH"] = CurrencyAssets(address(0), 6 * DECIMAL1E18, 0);
        allCurrencies.push("DAI");
        allCurrencyAssets["DAI"] = CurrencyAssets(0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359, 7 * DECIMAL1E18, 0);
        allInvestmentCurrencies.push("ETH");
        allInvestmentAssets["ETH"] = InvestmentAssets(address(0), true, 500, 5000, 18);
        allInvestmentCurrencies.push("DAI");
        allInvestmentAssets["DAI"] = InvestmentAssets(0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359, true, 500, 5000, 18);
    }

    /// @dev Changes address allowed to post MCR.
    function changeNotariseAddress(address _add) external onlyOwner {
        notariseMCR = _add;
    }

    /// @dev Sets minimum Cap.
    function changeMinCap(uint newCap) external onlyOwner {
        minCap = newCap;
    }

    /// @dev Sets Shock Parameter.
    function changeShockParameter(uint16 newParam) external onlyOwner {
        shockParameter = newParam;
    }

    /// @dev Changes Growth Step
    function changeGrowthStep(uint32 newGS) external onlyOwner {
        growthStep = newGS;
    }
    
    /// @dev Changes time period for obtaining new MCR data from external oracle query.
    function changeMCRTime(uint64 _time) external onlyInternal {
        mcrTime = _time;
    }

    /// @dev Sets MCR Fail time.
    function changeMCRFailTime(uint64 _time) external onlyInternal {
        mcrFailTime = _time;
    }

    /// @dev Changes minimum value of MCR required for the system to be working.
    /// @param minMCR in percentage. e.g 76% = 76*100
    function changeMinReqMCR(uint32 minMCR) external onlyInternal {
        minMCRReq = minMCR;
    }

    /// @dev Stores name of currency accepted in the system.
    /// @param curr Currency Name.
    function addCurrency(bytes4 curr) external onlyInternal {
        allCurrencies.push(curr);
    }

    /// @dev Changes scaling factor.
    function changeSF(uint32 val) external onlyInternal {
        sfX100000 = val;
    }
    
    /// @dev Updates the 3 day average rate of a currency.
    ///      To be replaced by MakerDao's on chain rates
    /// @param curr Currency Name.
    /// @param rate Average exchange rate X 100 (of last 3 days).
    function updateCAAvgRate(bytes4 curr, uint rate) external onlyInternal {
        caAvgRate[curr] = rate;
    }

    /// @dev Adds details of (Minimum Capital Requirement)MCR.
    /// @param mcrp Minimum Capital Requirement percentage (MCR% * 100 ,Ex:for 54.56% ,given 5456)
    /// @param vf Pool fund value in Ether used in the last full daily calculation from the Capital model.
    function pushMCRData(uint mcrp, uint mcre, uint vf, uint64 time) external onlyInternal {
        allMCRData.push(McrData(mcrp, mcre, vf, time));
    }

    /// @dev updates daiFeedAddress address.
    /// @param _add address of DAI feed.
    function changeDAIfeedAddress(address _add) external onlyOwner {
        daiFeedAddress = _add;
    }

    function changeUniswapDeadlineTime(uint newDeadline) external onlyInternal {
        uniswapDeadline = newDeadline;
    }

    function changeliquidityTradeCallbackTime(uint newTime) external onlyInternal {
        liquidityTradeCallbackTime = newTime;
    }

    /** 
     * @dev Updates the Timestamp at which result of oracalize call is received.
     */  
    function updateDateUpdOfAPI(bytes32 myid) external onlyInternal {
        allAPIid[myid].dateUpd = uint64(now);
    }

    /** 
     * @dev Saves the details of the Oraclize API.
     * @param myid Id return by the oraclize query.
     * @param _typeof type of the query for which oraclize call is made.
     * @param id ID of the proposal,quote,cover etc. for which oraclize call is made 
     */  
    function saveApiDetails(bytes32 myid, bytes4 _typeof, uint id) external onlyInternal {
        allAPIid[myid] = ApiId(_typeof, "", id, uint64(now), uint64(now));
    }

    /** 
     * @dev Stores the id return by the oraclize query. 
     * Maintains record of all the Ids return by oraclize query.
     * @param myid Id return by the oraclize query.
     */  
    function addInAllApiCall(bytes32 myid) external onlyInternal {
        allAPIcall.push(myid);
    }
    
    /**
     * @dev Saves investment asset rank details.
     * @param maxIACurr Maximum ranked investment asset currency.
     * @param maxRate Maximum ranked investment asset rate.
     * @param minIACurr Minimum ranked investment asset currency.
     * @param minRate Minimum ranked investment asset rate.
     * @param date in yyyymmdd.
     */  
    function saveIARankDetails(
        bytes4 maxIACurr,
        uint64 maxRate,
        bytes4 minIACurr,
        uint64 minRate,
        uint64 date
    )
        external
        onlyInternal
    {
        allIARankDetails.push(IARankDetails(maxIACurr, maxRate, minIACurr, minRate));
        datewiseId[date] = allIARankDetails.length.sub(1);
    }

    /**
     * @dev Changes time after which investment asset rates need to be fed.
     */  
    function changeIARatesTime(uint64 _newTime) external onlyInternal {
        iaRatesTime = _newTime;
    }

    function setLastLiquidityTradeTrigger() external onlyInternal {
        lastLiquidityTradeTrigger = now;
    }

    /** 
     * @dev Updates Last Date.
     */  
    function updatelastDate(uint64 newDate) external onlyInternal {
        lastDate = newDate;
    }
 
    /**
     * @dev Adds currency asset currency. 
     * @param curr currency of the asset
     * @param currAddress address of the currency
     * @param baseMin base minimum in 10^18. 
     */  
    function addCurrencyAssetCurrency(
        bytes4 curr,
        address currAddress,
        uint baseMin
    ) 
        external
    {
        require(ms.checkIsAuthToGoverned(msg.sender));
        allCurrencies.push(curr);
        allCurrencyAssets[curr] = CurrencyAssets(currAddress, baseMin, 0);
    }
    
    /**
     * @dev Adds investment asset. 
     */  
    function addInvestmentAssetCurrency(
        bytes4 curr,
        address currAddress,
        bool status,
        uint64 minHoldingPercX100,
        uint64 maxHoldingPercX100,
        uint8 decimals
    ) 
        external
    {
        require(ms.checkIsAuthToGoverned(msg.sender));
        allInvestmentCurrencies.push(curr);
        allInvestmentAssets[curr] = InvestmentAssets(currAddress, status,
            minHoldingPercX100, maxHoldingPercX100, decimals);
    }
    
    /**
     * @dev Changes the variation range percentage.
     */  
    function changeVariationPercX100(uint64 newPercX100) external onlyInternal {
        variationPercX100 = newPercX100;
    }

    /**
     * @dev Changes base minimum of a given currency asset.
     */ 
    function changeCurrencyAssetBaseMin(bytes4 curr, uint baseMin) external onlyInternal {
        allCurrencyAssets[curr].baseMin = baseMin;
    }

    /**
     * @dev changes variable minimum of a given currency asset.
     */  
    function changeCurrencyAssetVarMin(bytes4 curr, uint varMin) external onlyInternal {
        allCurrencyAssets[curr].varMin = varMin;
    }

    /**
     * @dev Updates investment asset decimals.
     */  
    function updateInvestmentAssetDecimals(bytes4 curr, uint8 newDecimal) external onlyInternal {
        allInvestmentAssets[curr].decimals = newDecimal;
    }

    /** 
     * @dev Changes the investment asset status.
     */ 
    function changeInvestmentAssetStatus(bytes4 curr, bool status) external onlyInternal {
        require(ms.checkIsAuthToGoverned(msg.sender));
        allInvestmentAssets[curr].status = status;
    }

    /** 
     * @dev Changes the investment asset Holding percentage of a given currency.
     */
    function changeInvestmentAssetHoldingPerc(
        bytes4 curr,
        uint64 minPercX100,
        uint64 maxPercX100
    )
        external
    {
        require(ms.checkIsAuthToGoverned(msg.sender));
        allInvestmentAssets[curr].minHoldingPercX100 = minPercX100;
        allInvestmentAssets[curr].maxHoldingPercX100 = maxPercX100;
    }

    /**
     * @dev Gets Currency asset token address. 
     */  
    function changeCurrencyAssetAddress(bytes4 curr, address currAdd) external onlyInternal {
        allCurrencyAssets[curr].currAddress = currAdd;
    }

    /**
     * @dev Changes Investment asset token address.
     */ 
    function changeInvestmentAssetAddress(
        bytes4 curr,
        address currAdd
    )
        external
        onlyInternal
    {
        allInvestmentAssets[curr].currAddress = currAdd;
    }

    /// @dev Checks whether a given address can notaise MCR data or not.
    /// @param _add Address.
    /// @return res Returns 0 if address is not authorized, else 1.
    function isnotarise(address _add) external view returns(bool res) {
        res = false;
        if (_add == notariseMCR)
            res = true;
    }

    /// @dev Gets the details of last added MCR.
    /// @return mcrPercx100 Total Minimum Capital Requirement percentage of that month of year(multiplied by 100).
    /// @return vFull Total Pool fund value in Ether used in the last full daily calculation.
    function getLastMCR() external view returns(uint mcrPercx100, uint mcrEtherx100, uint vFull, uint64 date) {
        uint index = allMCRData.length.sub(1);
        return (
            allMCRData[index].mcrPercx100,
            allMCRData[index].mcrEther,
            allMCRData[index].vFull,
            allMCRData[index].date
        );
    }

    /// @dev Gets last Minimum Capital Requirement percentage of Capital Model
    /// @return val MCR% value,multiplied by 100.
    function getLastMCRPerc() external view returns(uint) {
        return allMCRData[allMCRData.length.sub(1)].mcrPercx100;
    }

    /// @dev Gets last Ether price of Capital Model
    /// @return val ether value,multiplied by 100.
    function getLastMCREther() external view returns(uint) {
        return allMCRData[allMCRData.length.sub(1)].mcrEther;
    }

    /// @dev Gets Pool fund value in Ether used in the last full daily calculation from the Capital model.
    function getLastVfull() external view returns(uint) {
        return allMCRData[allMCRData.length.sub(1)].vFull;
    }

    /// @dev Gets last Minimum Capital Requirement in Ether.
    /// @return date of MCR.
    function getLastMCRDate() external view returns(uint64 date) {
        date = allMCRData[allMCRData.length.sub(1)].date;
    }

    /// @dev Gets details for token price calculation.
    function getTokenPriceDetails(bytes4 curr) external view returns(uint sf, uint gs, uint rate) {
        sf = sfX100000;
        gs = growthStep;
        rate = _getCAAvgRate(curr);
    }
    
    /// @dev Gets the total number of times MCR calculation has been made.
    function getMCRDataLength() external view returns(uint len) {
        len = allMCRData.length;
    }
 
    /**
     * @dev Gets investment asset rank details by given date.
     */  
    function getIARankDetailsByDate(
        uint64 date
    )
        external
        view
        returns(
            bytes4 maxIACurr,
            uint64 maxRate,
            bytes4 minIACurr,
            uint64 minRate
        )
    {
        uint index = datewiseId[date];
        return (
            allIARankDetails[index].maxIACurr,
            allIARankDetails[index].maxRate,
            allIARankDetails[index].minIACurr,
            allIARankDetails[index].minRate
        );
    }

    /** 
     * @dev Gets Last Date.
     */ 
    function getLastDate() external view returns(uint64 date) {
        return lastDate;
    }

    /**
     * @dev Gets investment currency for a given index.
     */  
    function getInvestmentCurrencyByIndex(uint index) external view returns(bytes4 currName) {
        return allInvestmentCurrencies[index];
    }

    /**
     * @dev Gets count of investment currency.
     */  
    function getInvestmentCurrencyLen() external view returns(uint len) {
        return allInvestmentCurrencies.length;
    }

    /**
     * @dev Gets all the investment currencies.
     */ 
    function getAllInvestmentCurrencies() external view returns(bytes4[] currencies) {
        return allInvestmentCurrencies;
    }

    /**
     * @dev Gets All currency for a given index.
     */  
    function getCurrenciesByIndex(uint index) external view returns(bytes4 currName) {
        return allCurrencies[index];
    }

    /** 
     * @dev Gets count of All currency.
     */  
    function getAllCurrenciesLen() external view returns(uint len) {
        return allCurrencies.length;
    }

    /**
     * @dev Gets all currencies 
     */  
    function getAllCurrencies() external view returns(bytes4[] currencies) {
        return allCurrencies;
    }

    /**
     * @dev Gets currency asset details for a given currency.
     */  
    function getCurrencyAssetVarBase(
        bytes4 curr
    )
        external
        view
        returns(
            bytes4 currency,
            uint baseMin,
            uint varMin
        )
    {
        return (
            curr,
            allCurrencyAssets[curr].baseMin,
            allCurrencyAssets[curr].varMin
        );
    }

    /**
     * @dev Gets minimum variable value for currency asset.
     */  
    function getCurrencyAssetVarMin(bytes4 curr) external view returns(uint varMin) {
        return allCurrencyAssets[curr].varMin;
    }

    /** 
     * @dev Gets base minimum of  a given currency asset.
     */  
    function getCurrencyAssetBaseMin(bytes4 curr) external view returns(uint baseMin) {
        return allCurrencyAssets[curr].baseMin;
    }

    /** 
     * @dev Gets investment asset maximum and minimum holding percentage of a given currency.
     */  
    function getInvestmentAssetHoldingPerc(
        bytes4 curr
    )
        external
        view
        returns(
            uint64 minHoldingPercX100,
            uint64 maxHoldingPercX100
        )
    {
        return (
            allInvestmentAssets[curr].minHoldingPercX100,
            allInvestmentAssets[curr].maxHoldingPercX100
        );
    }

    /** 
     * @dev Gets investment asset decimals.
     */  
    function getInvestmentAssetDecimals(bytes4 curr) external view returns(uint8 decimal) {
        return allInvestmentAssets[curr].decimals;
    }

    /**
     * @dev Gets investment asset maximum holding percentage of a given currency.
     */  
    function getInvestmentAssetMaxHoldingPerc(bytes4 curr) external view returns(uint64 maxHoldingPercX100) {
        return allInvestmentAssets[curr].maxHoldingPercX100;
    }

    /**
     * @dev Gets investment asset minimum holding percentage of a given currency.
     */  
    function getInvestmentAssetMinHoldingPerc(bytes4 curr) external view returns(uint64 minHoldingPercX100) {
        return allInvestmentAssets[curr].minHoldingPercX100;
    }

    /** 
     * @dev Gets investment asset details of a given currency
     */  
    function getInvestmentAssetDetails(
        bytes4 curr
    )
        external
        view
        returns(
            bytes4 currency,
            address currAddress,
            bool status,
            uint64 minHoldingPerc,
            uint64 maxHoldingPerc,
            uint8 decimals
        )
    {
        return (
            curr,
            allInvestmentAssets[curr].currAddress,
            allInvestmentAssets[curr].status,
            allInvestmentAssets[curr].minHoldingPercX100,
            allInvestmentAssets[curr].maxHoldingPercX100,
            allInvestmentAssets[curr].decimals
        );
    }

    /**
     * @dev Gets Currency asset token address.
     */  
    function getCurrencyAssetAddress(bytes4 curr) external view returns(address) {
        return allCurrencyAssets[curr].currAddress;
    }

    /**
     * @dev Gets investment asset token address.
     */  
    function getInvestmentAssetAddress(bytes4 curr) external view returns(address) {
        return allInvestmentAssets[curr].currAddress;
    }

    /**
     * @dev Gets investment asset active Status of a given currency.
     */  
    function getInvestmentAssetStatus(bytes4 curr) external view returns(bool status) {
        return allInvestmentAssets[curr].status;
    }

    /** 
     * @dev Gets type of oraclize query for a given Oraclize Query ID.
     * @param myid Oraclize Query ID identifying the query for which the result is being received.
     * @return _typeof It could be of type "quote","quotation","cover","claim" etc.
     */  
    function getApiIdTypeOf(bytes32 myid) external view returns(bytes4) {
        return allAPIid[myid].typeOf;
    }

    /** 
     * @dev Gets ID associated to oraclize query for a given Oraclize Query ID.
     * @param myid Oraclize Query ID identifying the query for which the result is being received.
     * @return id1 It could be the ID of "proposal","quotation","cover","claim" etc.
     */  
    function getIdOfApiId(bytes32 myid) external view returns(uint) {
        return allAPIid[myid].id;
    }

    /** 
     * @dev Gets the Timestamp of a oracalize call.
     */  
    function getDateAddOfAPI(bytes32 myid) external view returns(uint64) {
        return allAPIid[myid].dateAdd;
    }

    /**
     * @dev Gets the Timestamp at which result of oracalize call is received.
     */  
    function getDateUpdOfAPI(bytes32 myid) external view returns(uint64) {
        return allAPIid[myid].dateUpd;
    }

    /** 
     * @dev Gets currency by oracalize id. 
     */  
    function getCurrOfApiId(bytes32 myid) external view returns(bytes4) {
        return allAPIid[myid].currency;
    }

    /**
     * @dev Gets ID return by the oraclize query of a given index.
     * @param index Index.
     * @return myid ID return by the oraclize query.
     */  
    function getApiCallIndex(uint index) external view returns(bytes32 myid) {
        myid = allAPIcall[index];
    }

    /**
     * @dev Gets Length of API call. 
     */  
    function getApilCallLength() external view returns(uint) {
        return allAPIcall.length;
    }
    
    /**
     * @dev Get Details of Oraclize API when given Oraclize Id.
     * @param myid ID return by the oraclize query.
     * @return _typeof ype of the query for which oraclize 
     * call is made.("proposal","quote","quotation" etc.) 
     */  
    function getApiCallDetails(
        bytes32 myid
    )
        external
        view
        returns(
            bytes4 _typeof,
            bytes4 curr,
            uint id,
            uint64 dateAdd,
            uint64 dateUpd
        )
    {
        return (
            allAPIid[myid].typeOf,
            allAPIid[myid].currency,
            allAPIid[myid].id,
            allAPIid[myid].dateAdd,
            allAPIid[myid].dateUpd
        );
    }

    function getCAAvgRate(bytes4 curr) public view returns(uint rate) {
        return _getCAAvgRate(curr);
    }

    function changeDependentContractAddress() public onlyInternal {}

    /// @dev Gets the average rate of a currency.
    /// @param curr Currency Name.
    /// @return rate Average rate X 100(of last 3 days).
    function _getCAAvgRate(bytes4 curr) internal view returns(uint rate) {
        if (curr == "DAI") {
            DSValue ds = DSValue(daiFeedAddress);
            rate = uint(ds.read()).div(uint(10) ** 16);
        } else {
            rate = caAvgRate[curr];
        }
    }
}
