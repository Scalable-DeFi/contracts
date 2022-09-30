//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;


import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

//  is ERC721URIStorage, Ownable
contract lending is Ownable {

    using Counters for Counters.Counter;
    Counters.Counter public _loansIds;

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
    //The length of time until the full principal is due, e.g. 365 days.    
    uint256 public term;
    //Additional interest owed when payments are late, e.g. 5%. 
    uint256 public lateFee;
    //The current amount of USDC in the pool:
    uint256 public poolAmount;
    //The current withdrawn amount from the borrower:
    uint256 public withdrawnAmount;
    //The pool USDC limit amount:
    uint256 public poolLimit;
    //Total invested to the private investors pool:
    uint256 public privateInvestorsPoolAmount;


    constructor(address _USDCAddress, address _poolBorrower, uint256 _interestRate, uint256 _paymentFrequency, uint256 _term, uint256 _lateFee, uint256 _poolLimit, address _portfolioMulti, address _scalablePool)  {
        USDCAddress = IERC20(_USDCAddress);
        poolBorrower = _poolBorrower;
        contractEnabled = true;
        poolEnabled = true;
        interestRate = _interestRate;
        paymentFrequency = _paymentFrequency;
        term = _term;
        lateFee = _lateFee;
        poolLimit = _poolLimit;    
        portfolioMulti = _portfolioMulti;
        scalablePool = _scalablePool;
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


    modifier onlyBorrower() {
        require(msg.sender == poolBorrower, "Only the pool Borrower can withdraw");
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


    struct Loan {
        uint256 withdrawnAmount;
        uint256 withdrawnTimestamp;
        uint32 repaidLoansAmount;
        uint256 repaidLoansValue;
    }


    //id to loan
    mapping(uint256 => Loan) public Loans;
    event loanWithdrawn(uint256 withdrawnAmount, uint256 withdrawnTimestamp);
    event loanRepaid(uint256 loanId, uint32 repaidLoansAmount);

    //allow the borrower to get the credit from the pool:
    function withdrawFromPool(uint256 _withdrawnAmount) public onlyBorrower() onlyContractEnabled() {
        
        bool sent = USDCAddress.transfer(msg.sender, _withdrawnAmount);
        require(sent, "Failed to withdraw the loan");
        _loansIds.increment();

        Loans[_loansIds.current()] = Loan ({
            withdrawnAmount: _withdrawnAmount,
            withdrawnTimestamp: block.timestamp,
            //quantas parcelar já foram pagas:
            repaidLoansAmount: 0,
            //o valor total do montante pago:
            repaidLoansValue: 0
        });

        emit loanWithdrawn(_withdrawnAmount, block.timestamp);
    }

    //return an specific loan created by the borrower
    function getLoan(uint256 _id) public view returns(Loan memory){
        return(Loans[_id]);
    }


    function howMuchShouldIPay(uint256 _id) public view returns(uint256) {
        uint256 amount = ((Loans[_id].withdrawnAmount / paymentFrequency) + ((Loans[_id].withdrawnAmount * interestRate / 100) / paymentFrequency));
        return(amount);
    }

    function interestRateView() public view returns(uint256) {
        return(interestRate / 100);
    }

    function repayLoan(uint256 _id, uint256 USDCAmount) public onlyContractEnabled() {
        require(Loans[_id].repaidLoansAmount < paymentFrequency);

        if((Loans[_id].withdrawnTimestamp + (((term/paymentFrequency) * 86400) * Loans[_id].repaidLoansAmount) <= block.timestamp)) {
                uint256 amount = ((Loans[_id].withdrawnAmount / paymentFrequency) + ((Loans[_id].withdrawnAmount * interestRate) / paymentFrequency));
                require(USDCAmount >= amount, "amount not sufficient");
                uint256 scalablePoolAmount = USDCAmount * 1 / 10;
                bool sent = USDCAddress.transferFrom(msg.sender, scalablePool, scalablePoolAmount);
                require(sent, "Failed to repay the loan");


                //calculando a parte para os privateinvestor:
                uint256 privateInvestorAmount = USDCAmount * 375 / 1000;
                for (uint i = 1; i <= _lendingsIds.current(); i++){
                    uint256 fee = (Lendings[i].USDCAmount / privateInvestorAmount);
                    uint256 USDCFee = privateInvestorAmount * fee;
                    bool sentPrivateInvestorAmount = USDCAddress.transferFrom(msg.sender, Lendings[i].lender, USDCFee);
                    require(sentPrivateInvestorAmount, "Failed to repay the loan");
                }

                uint256 portfolioMultiAmount = USDCAmount * 525 / 1000;
                bool sentPortfolioMultiAmount = USDCAddress.transferFrom(msg.sender, portfolioMulti, portfolioMultiAmount);
                require(sentPortfolioMultiAmount, "Failed to repay the loan");


                Loans[_id].repaidLoansAmount += 1;
                Loans[_id].repaidLoansValue += USDCAmount;

                emit loanRepaid(_id, Loans[_id].repaidLoansAmount);
            }
        
        else if((Loans[_id].withdrawnTimestamp + (((term/paymentFrequency) * 86400) * Loans[_id].repaidLoansAmount) > block.timestamp)) {
                uint256 amount = ((Loans[_id].withdrawnAmount / paymentFrequency) + ((Loans[_id].withdrawnAmount * interestRate) / paymentFrequency) + ((Loans[_id].withdrawnAmount / paymentFrequency) * (lateFee) * ((Loans[_id].withdrawnTimestamp + (((term/paymentFrequency) * 86400) * Loans[_id].repaidLoansAmount) - block.timestamp))));
                require(USDCAmount >= amount);
                uint256 scalablePoolAmount = USDCAmount * 1/10;
                bool sent = USDCAddress.transferFrom(msg.sender, scalablePool, scalablePoolAmount);
                require(sent, "Failed to repay the loan");

                                //calculando a parte para os privateinvestor:
                uint256 privateInvestorAmount = USDCAmount * 375/1000;
                for (uint i = 1; i <= _lendingsIds.current(); i++){
                    uint256 fee = (Lendings[i].USDCAmount / privateInvestorAmount);
                    uint256 USDCFee = USDCAmount * fee;
                    bool sentPrivateInvestorAmount = USDCAddress.transferFrom(msg.sender, Lendings[i].lender, USDCFee);
                    require(sentPrivateInvestorAmount, "Failed to repay the loan");
                }

                uint256 portfolioMultiAmount = USDCAmount * 525/1000;
                bool sentPortfolioMultiAmount = USDCAddress.transferFrom(msg.sender, portfolioMulti, portfolioMultiAmount);
                require(sentPortfolioMultiAmount, "Failed to repay the loan");







                Loans[_id].repaidLoansAmount += 1;
                Loans[_id].repaidLoansValue += amount;
                emit loanRepaid(_id, Loans[_id].repaidLoansAmount);
        }



        }


        function teste(uint256 _id, uint256 USDCAmount) public {
        require(Loans[_id].repaidLoansAmount < paymentFrequency, "erro aqui");

        if((Loans[_id].withdrawnTimestamp + (((term/paymentFrequency) * 86400) * Loans[_id].repaidLoansAmount) <= block.timestamp)) {
                uint256 amount = ((Loans[_id].withdrawnAmount / paymentFrequency) + ((Loans[_id].withdrawnAmount * interestRate) / paymentFrequency));
                require(USDCAmount >= amount);
                uint256 scalablePoolAmount = USDCAmount * 1/10;
                bool sent = USDCAddress.transferFrom(msg.sender, scalablePool, scalablePoolAmount);
                require(sent, "Failed to repay the loan");


                //calculando a parte para os privateinvestor:
                uint256 privateInvestorAmount = USDCAmount * 375/1000;
                for (uint i = 1; i <= _lendingsIds.current(); i++){
                    uint256 fee = (Lendings[i].USDCAmount / privateInvestorAmount);
                    uint256 USDCFee = privateInvestorAmount * fee;
                    bool sentPrivateInvestorAmount = USDCAddress.transferFrom(msg.sender, Lendings[i].lender, USDCFee);
                    require(sentPrivateInvestorAmount, "Failed to repay the loan");
                }

                uint256 portfolioMultiAmount = USDCAmount * 525/1000;
                bool sentPortfolioMultiAmount = USDCAddress.transferFrom(msg.sender, portfolioMulti, portfolioMultiAmount);
                require(sentPortfolioMultiAmount, "Failed to repay the loan");


                Loans[_id].repaidLoansAmount += 1;
                Loans[_id].repaidLoansValue += USDCAmount;

                emit loanRepaid(_id, Loans[_id].repaidLoansAmount);
            }
        }





















    struct Lending {
        uint256 lendingTimeStamp;
        address lender;
        uint256 USDCAmount;
        //mapping -> passa o id da loan e recebe quantos payments ele já recebeu da loan:
        mapping(uint256 => uint256) paymentsReceveid;
    }

    mapping(uint256 => Lending) public Lendings;
    event lendingMinted(uint256 id,  uint256 lendingTimeStamp, uint256 USDCAmount, address lender);

    //mapping to verify if address is a private investor
    mapping(address => bool) isPrivateInvestor;

    Counters.Counter public _lendingsIds;

    //function for private investors/backers being able to invest through the junior tranche:
    function lendToBorrowerPool(uint256 _USDCAmount) public onlyPoolEnabled() onlyContractEnabled() {
        require(poolAmount + _USDCAmount <= poolLimit);

        bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
        require(sent, "Failed to lend to borrower pool");

        _lendingsIds.increment();

        uint256 lIds = _lendingsIds.current();

        Lending storage l = Lendings[lIds];
        l.lendingTimeStamp = block.timestamp;
        l.lender = msg.sender;
        l.USDCAmount = _USDCAmount;
        poolAmount += _USDCAmount;
        privateInvestorsPoolAmount += _USDCAmount;
        isPrivateInvestor[msg.sender] = true;
    }

   /* 
    function getLoanpayment(uint256 _id) public onlyContractEnabled() {
        require(isPrivateInvestor[msg.sender] == true);
        require(Lendings[msg.sender].paymentsReceveid[_id] < Loans[_id].repaidLoansAmount);

        uint256 amount = Loans[_id].repaidLoansAmount - Lendings[msg.sender].paymentsReceveid[_id];

        for (uint256 i = 1; i <= amount; i++) { 
    
        }
    }
    */
    

    
}
