pragma solidity >=0.4.21 <0.7.0;

contract TestSFC {
    uint256 public delegationRewards1;
    uint256 public delegationRewards2;
    uint256 public delegationRewards3;
    uint256 public validatorRewards1;
    uint256 public validatorRewards2;
    uint256 public validatorRewards3;
    uint256 public _currentEpoch;

    function setDelegationRewards(uint256 v1, uint256 v2, uint256 v3) external {
        delegationRewards1 = v1;
        delegationRewards2 = v2;
        delegationRewards3 = v3;
    }

    function setValidatorRewards(uint256 v1, uint256 v2, uint256 v3) external {
        validatorRewards1 = v1;
        validatorRewards2 = v2;
        validatorRewards3 = v3;
    }

    function setCurrentEpoch(uint256 epoch) external {
        _currentEpoch = epoch;
    }

    function calcDelegationRewards(address /*delegator*/, uint256 /*_fromEpoch*/, uint256 /*maxEpochs*/) external view returns (uint256, uint256, uint256) {
        return(delegationRewards1, delegationRewards2, delegationRewards3);
    }

    function calcValidatorRewards(uint256 /*stakerID*/, uint256 /*_fromEpoch*/, uint256 /*maxEpochs*/) external view returns (uint256, uint256, uint256) {
        return(validatorRewards1, validatorRewards2, validatorRewards3);
    }

    function getStakerID(address /*addr*/) public pure returns (uint256) {
        return 0;
    }

    function currentEpoch() external view returns (uint256) {
        return(_currentEpoch);
    }
}
