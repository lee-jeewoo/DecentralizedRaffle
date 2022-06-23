// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "./NFT.sol";

struct RaffleState {
    bool isOpen;
    uint32 endTime;
    uint256 raffleId;
}

error Raffle__NotEnoughMoney();
error Raffle__TransferFailed();
error Raffle__NotOpen();
error Raffle__CannotWithdraw(string m);
error Raffle__UpkeepNotNeeded(uint256 currentBalance, bool raffleState);

contract Raffle is VRFConsumerBaseV2, KeeperCompatibleInterface {
    /* chainlink */
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1; //for requesting random word from chainlinkvrf

    /* raffle */
    uint256 private immutable i_minInputMoney;
    uint256 private s_time;
    uint256 public s_total_deposited = 0;
    uint256 public s_squared_total = 0;
    uint256 private immutable i_item_price;
    uint256 private s_lastTimeStamp;
    uint256 private s_winNum;
    address private s_owner; // might be removed later.
    mapping(address => uint256) private deposits;
    RaffleState private s_raffleState;

    /* events */
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player, uint256 amount);
    event WinnerPicked(address indexed player);
    event WinnerAlerted(address indexed player);
    event Withdrawed(address indexed player);
    event LoserAlerted(address indexed player);

    constructor(
        address vrfCoordinatorV2,
        uint256 _minInput,
        uint256 _itemPrice,
        uint256 _raffleID,
        uint32 _endTime,
        address _owner,
        bytes32 _gasLane,
        uint64 _subscriptionID,
        uint32 _callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_minInputMoney = _minInput;
        i_gasLane = _gasLane;
        i_subscriptionId = _subscriptionID;
        i_callbackGasLimit = _callbackGasLimit;
        s_raffleState = RaffleState(true, _endTime, _raffleID);
        i_item_price = _itemPrice;
        s_owner = _owner;
    }

    function example() public {}

    /*
     * function checkUpkeep, performupKeepm and fulfillRandomWords are utilzied to keep track of when to close the raffle and
     * choose the random winner.
     */
    function checkUpkeep(
        bytes memory /*checkData*/
    )
        public
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        bool isOpen = true == s_raffleState.isOpen;
        bool timePassed = (block.timestamp > (s_raffleState.endTime));
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && timePassed && hasBalance);
    }

    function performUpkeep(
        bytes calldata /*performData*/
    ) external override {
        // Request the random number
        // once we get it, do something with it
        // 2 transaction process
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_raffleState.isOpen);
        }
        s_raffleState.isOpen = false;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256, /*requestId*/
        uint256[] memory randomWords
    ) internal override {
        s_winNum = randomWords[0] % 100; //100 should be lastval from NFT.sol
        // s_lastTimeStamp = block.timestamp;
        // (bool success, ) = recentWinner.call{value: address(this).balance}("");
        // if (!success) {
        //     revert Raffle__TransferFailed();
        // }
        // emit WinnerPicked(recentWinner);
    }

    /*
     * enterRaffle allows users to put money and get a raffle ticket (NFT).
     */
    function enterRaffle(uint256 amount) public payable {
        if (msg.value - amount > i_minInputMoney) {
            revert Raffle__NotEnoughMoney();
        }
        if (s_raffleState.isOpen == false) {
            revert Raffle__NotOpen();
        }

        s_total_deposited += amount;
        s_squared_total += sqrt(amount);
        deposits[msg.sender] += amount;

        // call NFT.sol's minting function here
    }

    /*
     * withdraw allows users to withdraw amount they have deposited when the raffle deposit goal hasn’t met in time.
     */
    function withrdaw() public {
        if (s_raffleState.isOpen == false && s_total_deposited < i_item_price) {
            revert Raffle__CannotWithdraw("Raffle is not closed!");
        }
        if (deposits[msg.sender] < 0) {
            revert Raffle__CannotWithdraw("Doesn't have matic to withdraw");
        }

        s_total_deposited -= deposits[msg.sender];
        (bool success, ) = msg.sender.call{value: address(this).balance}("");

        if (!success) {
            revert Raffle__TransferFailed();
        }
        deposits[msg.sender] = 0;
        emit Withdrawed(msg.sender);
    }

    /*
     * potentialChances calculate potential chances for user to win the raffle
     */
    function potentialChances(uint256 amount) public view returns (uint256 chance) {
        chance = (sqrt(amount)) / (s_squared_total + sqrt(amount));
    }

    /*
     * tokenChances calculate actual chances for the token to win the raffle
     */
    function tokenChances(uint256 tokenId) public view returns (uint256 chance) {
        // get tokenData from NFT contract
    }

    /*
     * checkWin allow people to confirm if they won with NFT they hold.
     */
    function checkWin() public view returns (bool) {
        // under construction
        // NFT.ownerOf?
    }

    /* utils */
    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    // from https://github.com/Uniswap/v2-core/blob/4dd59067c76dea4a0e8e4bfdda41877a6b16dedc/contracts/libraries/Math.sol#L11-L22
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
