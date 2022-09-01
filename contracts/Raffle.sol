// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "hardhat/console.sol";

//hard coded error msg
error Raffle__NotEnoughEthEntered();
error Raffle__TransferFailed();
error Raffle__NotOpen();
error Raffle__UpKeepNotNeeded(uint256 currnetBalance, uint256 numPlayers, uint256 raffleState);

/**@title A simple raffle contract
 * @author Paul Junia
 * @notice This contract is for creating an untamperable decentralized smartcontract
 * @dev This implements chainlink VRF V2 and ChainLink keepers
 */

contract Raffle is VRFConsumerBaseV2, KeeperCompatibleInterface {
    //type declaration
    enum RaffleState {
        OPEN,
        CALCULATING
    }
    //state variables
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATION = 3;
    uint32 private constant NUM_WORDS = 1;

    //lottery variables
    address private s_recentWinner;
    uint256 private immutable i_entranceFee;
    RaffleState private s_raffleState;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    uint256 private immutable i_interval;

    //Events
    event RaffleEnter(address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);
    event WinnerPicked(address indexed winner);

    //constructor
    constructor(
        address vrfCoordinatorV2,
        uint256 entranceFee,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit,
        uint256 interval
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_entranceFee = entranceFee;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        i_interval = interval;
    }

    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthEntered();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen();
        }
        s_players.push(payable(msg.sender));
        //Emit an event when we update a dynamic array or mapping
        //named events with the function name reversed
        emit RaffleEnter(msg.sender);
    }

    /**
     * @dev This is the function that the chianLink keeper nodes call
     * they look for the upkeepNeeded to return true.
     * The following should be true in order to return true.
     * 1. our time interval should have passed
     * 2. The lottery should have at least 1 player, and have some ETH
     * 3. Our subscription is funded with link
     * 4. The lottery should be in an open state.
     */
    function checkUpkeep(
        bytes memory /**checkData*/
    )
        public
        view
        override
        returns (
            bool upKeepNeeded,
            bytes memory /*perfomData */
        )
    {
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upKeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);
        return (upKeepNeeded, "0x0");
    }

    //Requesting Random winner function
    function performUpkeep(
        bytes calldata /*perfomData */
    ) external override {
        //Request random number
        //two transanction process
        // Will revert if subscription is not set and funded.
        (bool upKeepNeeded, ) = checkUpkeep("");
        if (!upKeepNeeded) {
            revert Raffle__UpKeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATION,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256,
        /*requestId*/
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinnner = s_players[indexOfWinner];
        s_recentWinner = recentWinnner;
        s_raffleState = RaffleState.OPEN;
        //reset players $ timestamp
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        //send all money to winner
        (bool success, ) = recentWinnner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(recentWinnner);
    }

    //view / pure functions
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getNumOfPlayers() public view returns (uint256) {
        return s_players.length;
    }

    function getLatestTimestamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRequestConfirmation() public pure returns (uint256) {
        return REQUEST_CONFIRMATION;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }
}
//15:21
