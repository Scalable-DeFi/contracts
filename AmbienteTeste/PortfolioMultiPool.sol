//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract PortfolioMultiPool is Ownable {

    using Counters for Counters.Counter;
    Counters.Counter public _investors;

    IERC20 public USDCAddress;
    address public poolBorrower;
    address public portfolioMulti;
    address public scalablePool;

    bool public contractEnabled;
    bool public poolEnabled;

    
    //**Pool structure**:


    //Fixed interest rate
    uint256 public interestRate;
    //Frequency of interest and principal payments, e.g. every 30 days.
    uint256 public paymentFrequency;
    //Additional interest owed when payments are late, e.g. 5%. 
    uint256 public lateFee;
    //The current amount of USDC in the pool:
    uint256 public poolAmount;
    //Minimun investment allowed to the pool:
    uint256 public minInvestment;
    //The current withdrawn amount from the borrower:
    uint256 public withdrawnAmount;
    //The pool USDC limit amount:
    uint256 public poolLimit;
    //Total invested to the private investors pool:
    uint256 public privateInvestorsPoolAmount;


    constructor(address _USDCAddress, address _poolBorrower, uint256 _interestRate, uint256 _minInvestment, uint256 _paymentFrequency, uint256 _lateFee, uint256 _poolLimit, address _portfolioMulti, address _scalablePool)  {
        USDCAddress = IERC20(_USDCAddress);
        poolBorrower = _poolBorrower;
        contractEnabled = true;
        poolEnabled = true;
        interestRate = _interestRate;
        paymentFrequency = _paymentFrequency;
        lateFee = _lateFee;
        poolLimit = _poolLimit;    
        portfolioMulti = _portfolioMulti;
        scalablePool = _scalablePool;
        minInvestment = _minInvestment;
    }





    //MODIFIERS:
    modifier onlyContractEnabled() {
        require(contractEnabled == true);
        _;
    }

    modifier onlyPoolEnabled() {
        require(poolEnabled == true);
        _;
    }


    function modifyContractEnabled(bool _bool) public onlyOwner() {
        contractEnabled = _bool;
    }

    function modifyPoolEnabled(bool _bool) public onlyOwner() {
        poolEnabled = _bool;
    }

    function modifyPoolBorrower(address _address) public onlyOwner() {
        poolBorrower = _address;
    }




    struct Investor {
        address investor;
        uint256 totalAmountInvested;
        uint256 totalAmountReceived;
        bool isActive;
    }

    event newInvestorCreated(address Investor, uint256 totalAmountInvested, uint256 id);
    event newInvestment(address Investor, uint256 newAmount, uint256 id);

    mapping(uint256 => Investor) public Investors;
    mapping(address => uint256) public addressToInvestorId;

    function investInPool(uint256 _USDCAmount) public onlyPoolEnabled() onlyContractEnabled() {
        require(_USDCAmount >= minInvestment, "You need to invest more");


        //se investidor não existe ainda, criar struct:
        if(!Investors[addressToInvestorId[msg.sender]].isActive){

            bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
            require(sent, "Failed to transfer the amount");

            poolAmount += _USDCAmount;
            _investors.increment();
            Investors[_investors.current()] = Investor ({
                investor: msg.sender,
                totalAmountInvested: _USDCAmount,
                totalAmountReceived: 0,
                isActive: true
            });
            addressToInvestorId[msg.sender] = _investors.current();
            emit newInvestorCreated(msg.sender, _USDCAmount, _investors.current());

        }

        //se o investidor já existe, usar a sua struct:
        else {

            bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
            require(sent, "Failed to transfer the amount");

            poolAmount += _USDCAmount;
            Investors[addressToInvestorId[msg.sender]].totalAmountInvested += _USDCAmount;
            emit newInvestment(msg.sender, _USDCAmount, addressToInvestorId[msg.sender]);

        }
        

    }



    //Finalmente, função chamada para repartir os ganhos da pool:
    function distributeGains(uint256 _USDCAmount) public onlyOwner() {
        require(poolAmount > 0, "The pool does not have usdc to distribute");

        for (uint256 i = 1; i <= _investors.current(); i++){
            if(Investors[i].isActive){
                uint256 amount = Investors[i].totalAmountInvested / poolAmount;

                bool sent = USDCAddress.transfer(Investors[i].investor, amount * _USDCAmount);
                require(sent, "Failed to withdraw the loan");
                Investors[i].totalAmountReceived += (amount * _USDCAmount);

            }
        }
    }



    //Permitir investidor sacar seu dinheiro:
    function withdrawAmount(uint256 _USDCAmount) public onlyContractEnabled() onlyPoolEnabled() {
        require(_USDCAmount <= Investors[addressToInvestorId[msg.sender]].totalAmountReceived);
        bool sent = USDCAddress.transfer(msg.sender, _USDCAmount);
        require(sent, "Failed to withdraw the loan");
    }

   
}