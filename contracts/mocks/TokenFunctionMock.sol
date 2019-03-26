pragma solidity 0.4.24;

import "../Pool1.sol";

contract TokenFunctionMock is TokenFunctions {

	 /**
     * @dev Burns tokens staked against a Smart Contract Cover.
     * Called when a claim submitted against this cover is accepted.
     */
    function burnStakerLockedToken(address scAddress, uint burnNXMAmount) external {
        uint totalStaker = td.getStakedContractStakersLength(scAddress);
        address stakerAddress;
        uint stakerStakedNXM;
        uint toBurn = burnNXMAmount;
        for (uint i = td.stakedContractCurrentBurnIndex(scAddress); i < totalStaker; i++) {
            if (toBurn > 0) {
                stakerAddress = td.getStakedContractStakerByIndex(scAddress, i);
                uint stakerIndex = td.getStakedContractStakerIndex(
                scAddress, i);
                uint V;
                (V, stakerStakedNXM) = _unlockableBeforeBurningAndCanBurn(stakerAddress, scAddress, stakerIndex);
                td.pushUnlockableBeforeLastBurnTokens(stakerAddress, stakerIndex, V);
                // stakerStakedNXM =  _getStakerStakedTokensOnSmartContract(stakerAddress, scAddress, i);
                if (stakerStakedNXM > 0) {
                    if (stakerStakedNXM >= toBurn) {
                        _burnStakerTokenLockedAgainstSmartContract(
                            stakerAddress, scAddress, i, toBurn);
                        if (i > 0)
                            td.setStakedContractCurrentBurnIndex(scAddress, i);
                        toBurn = 0;
                        break;
                    } else {
                        _burnStakerTokenLockedAgainstSmartContract(
                            stakerAddress, scAddress, i, stakerStakedNXM);
                        toBurn = toBurn.sub(stakerStakedNXM);
                    }
                }
            } else
                break;
        }
        if (toBurn > 0 && totalStaker > 0)
            td.setStakedContractCurrentBurnIndex(scAddress, totalStaker.sub(1));
    }

    function mint(address _member, uint _amount) external {
        tc.mint(_member, _amount);
    }

    function burnFrom(address _of, uint amount) external {
        tc.burnFrom(_of, amount);
    }
    
}
