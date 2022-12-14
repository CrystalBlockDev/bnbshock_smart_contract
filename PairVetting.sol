// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PairVetting is Ownable
{    
	using SafeMath for uint256;

	address private gameManager = 0x614D7984d20495e9276080008C36AEa9C0752910;
	uint public claimDuration = 24 * 3600;
	uint public referrlRate = 2;
    uint256 public MIN_DEPOSIT_LIMIT = 1 * 1e16; /* 0.01 BNB  */
    uint256 public MAX_DEPOSIT_LIMIT = 10 * 1e18; /* 10 BNB  */

	struct player
	{
		address wallet;
		uint amount;
		string idOnDB;
	}

	mapping( address => uint256 ) depositAmount;
	mapping( address => uint256 ) refAwardAmount;
	mapping( address => uint256 ) countOfRerrals;
  	mapping( address => uint256 ) claimedTime;

	event StartOfVetting(address wallet, string pairId ,uint pairPrice, uint amount, uint vettingPeriod, bool upOrDown);
	event EndOfVetting(player[] winners, player[] victims);
	event Maintenance(address owner, uint tokenBalance, uint nativeBalance);
	event ChangedGameManager(address owner, address newManager);
	event ChangedClaimDuration(address owner, uint newDuration);
	event ClaimedAward(address wallet, uint awardAmount);
	event WithDrawedPlayerFunds(address wallet, uint withdrawnAmount);
	event ChangedReferralRate(address owner, uint newRate);
	event ChangeMinDepositLimit(address owner, uint newLimit);
	event ChangeMaxDepositLimit(address owner, uint newLimit);
	
    event Received(address, uint);
    event Fallback(address, uint);

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    fallback() external payable { 
        emit Fallback(msg.sender, msg.value);
    }

	function changeClaimDuration(uint newDuration) external {
		require(msg.sender == gameManager || msg.sender == owner(), "104");
		claimDuration = newDuration;
		emit ChangedClaimDuration(owner(), claimDuration);
	}

	function enterVettingWithoutRef(string memory pairId, uint pairPrice, uint vettingPeriod, bool upOrDown, uint256 amount, address wallet) external payable    
	{		
		require(msg.sender == gameManager);		
		require(depositAmount[wallet].sub(amount) >= 0);
		emit StartOfVetting(wallet, pairId, pairPrice, amount, vettingPeriod, upOrDown);
	}

	function enterVetting(string memory pairId, uint pairPrice, uint vettingPeriod, bool upOrDown, address ref, uint amount, address wallet) external payable    
	{		
		require(msg.sender == gameManager);
		require(depositAmount[wallet].sub(amount) >= 0);
		uint awardAmount = amount.mul(referrlRate).div(100);
		refAwardAmount[ref] = refAwardAmount[ref].add(awardAmount);
		countOfRerrals[ref] = countOfRerrals[ref].add(1);		
		emit StartOfVetting(wallet, pairId, pairPrice, amount - awardAmount, vettingPeriod, upOrDown);
	}

	function changeGameManager(address newAddr) external {
		require(msg.sender == gameManager || msg.sender == owner(), "104");
		gameManager = newAddr;
		emit ChangedGameManager(owner(), gameManager);
	}

	function changeReferralRate(uint newRate) external {
		require(msg.sender == gameManager || msg.sender == owner(), "104");
		require(newRate>=0 && newRate<=100, "105");
		referrlRate = newRate;
		emit ChangedReferralRate(owner(), referrlRate);
	}
	
	function changeMinDepositLimit(uint newAmount) external {
		require(msg.sender == gameManager || msg.sender == owner(), "104");
		MIN_DEPOSIT_LIMIT = newAmount;
		emit ChangeMinDepositLimit(owner(), MIN_DEPOSIT_LIMIT);
	}
	
	function changeMaxDepositLimit(uint newAmount) external {
		require(msg.sender == gameManager || msg.sender == owner(), "104");
		MAX_DEPOSIT_LIMIT = newAmount;
		emit ChangeMaxDepositLimit(owner(), MAX_DEPOSIT_LIMIT);
	}

	function getClaimableInformation(address user) public view returns(uint, uint, uint, uint) {
		return (refAwardAmount[user], countOfRerrals[user], claimedTime[user], depositAmount[user]);
	}

	function canWithdrawGameFunds() public view returns (uint ) {
		if(depositAmount[msg.sender] == 0 ) return 1;
		else if(address(this).balance < depositAmount[msg.sender])	return 2;
		else return 0;		
	}

	function canClaimReferralAwards() public view returns (uint) {
		if(refAwardAmount[msg.sender] == 0) return 1;
		else if(address(this).balance < refAwardAmount[msg.sender]) return 2;
		else if(claimedTime[msg.sender] + claimDuration <= block.timestamp && claimedTime[msg.sender] != 0) return 3;
		else return 0;
	}

	function withDrawPlayerFunds()  external {
		if(depositAmount[msg.sender] > 0)
		{
			require( address(this).balance > depositAmount[msg.sender], "101");
			payable(msg.sender).transfer(depositAmount[msg.sender]);
			emit WithDrawedPlayerFunds(msg.sender, depositAmount[msg.sender]);
		}
	}

	function claimReferralAwards(address user) external {
		require( refAwardAmount[user] > 0, "103");
    	require( claimedTime[user] == 0 || ((claimedTime[user] + claimDuration) > block.timestamp), "102" );
		require( address(this).balance > refAwardAmount[user], "101");

 		payable(user).transfer(refAwardAmount[user]);
		emit ClaimedAward(user, refAwardAmount[user]);

		refAwardAmount[user] = 0;
		countOfRerrals[user] = 0;
		claimedTime[user] = block.timestamp;
	}

	function endVetting(player[] memory winners, player[] memory victims) external
	{
		require(msg.sender == gameManager);
		for(uint idx = 0; idx<winners.length; idx++)
		{
			depositAmount[winners[idx].wallet] = depositAmount[winners[idx].wallet].add(winners[idx].amount);
		}		
		for(uint idx1 = 0; idx1<victims.length; idx1++)
		{
			depositAmount[victims[idx1].wallet] = depositAmount[victims[idx1].wallet].sub(victims[idx1].amount);
		}
		emit EndOfVetting(winners, victims); 
	}

	function withdraw(address _addr) external
	{
	  require(msg.sender == owner() || msg.sender == gameManager);
		uint256 balance = IERC20(_addr).balanceOf(address(this));
		if(balance > 0) {
      IERC20(_addr).transfer(msg.sender, balance);
		}
		uint256 nativeBal = address(this).balance;
		if(nativeBal> 0) {
			payable(msg.sender).transfer(nativeBal);
		}
		emit Maintenance(msg.sender, balance, nativeBal);
	}	

	function depositFunds() external payable {		
        require(msg.value >= MIN_DEPOSIT_LIMIT, "107");
        require(depositAmount[msg.sender].add(msg.value) <= MAX_DEPOSIT_LIMIT, "108");
		depositAmount[msg.sender] = depositAmount[msg.sender].add(msg.value);
	}

}
