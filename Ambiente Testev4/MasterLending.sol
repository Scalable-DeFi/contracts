//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;


import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";



interface PortfolioMultiPool {
    function distribute(uint256) external;
}



//  is ERC721URIStorage, Ownable
contract MasterLending is Ownable, ReentrancyGuard{

    using Counters for Counters.Counter;
    Counters.Counter public _loansIds;

    IERC20 public USDCAddress;
    address public poolBorrower;
    address public portfolioMulti;
    address public scalablePool;
    PortfolioMultiPool public portfolioMultiInterface;

    bool public contractEnabled;
    bool public poolEnabled;

    
    //**Pool structure**:


    //Fixed interest rate
    uint256 public interestRate;
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
    //Scalable pool porcentagem do montante que vai receber:
    uint256 public scalablePoolFee;
    //Private investor porcentagem do montante que vai receber:
    uint256 public privateInvestorPoolFee;
    //PortfolioMulti porcentagem do montante que vai receber:
    uint256 public portfolioMultiPoolFee;
    //A partir do momento em que o borrower tomar um empréstimo, de quantos em quantos dias ele terá que pagar as parcelas?
    uint256 public daysDue;
    //Quantidade total de parcelas a serem pagas:
    uint256 public paymentFrequency;


    constructor(address _USDCAddress, address _poolBorrower, uint256 _interestRate, uint256 _paymentFrequency, uint256 _lateFee, uint256 _poolLimit, address _portfolioMulti, address _scalablePool, uint256 _scalablePoolFee, uint256 _privateInvestorPoolFee, uint256 _portfolioMultiPoolFee, uint256 _daysDue)  {
        require(_scalablePoolFee + _privateInvestorPoolFee + _portfolioMultiPoolFee == 1000, "The fees distribution are not correct");
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
        scalablePoolFee = _scalablePoolFee;
        privateInvestorPoolFee = _privateInvestorPoolFee;
        portfolioMultiPoolFee = _portfolioMultiPoolFee;
        daysDue = _daysDue;
    }

    function setPortfolioMultiInterface(PortfolioMultiPool _portfolioMultiInterface) public onlyOwner() {
        portfolioMultiInterface = _portfolioMultiInterface;
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
    function withdrawFromPool(uint256 _withdrawnAmount) public onlyBorrower() onlyContractEnabled() nonReentrant {
        
        bool sent = USDCAddress.transfer(msg.sender, _withdrawnAmount);
        require(sent, "Failed to withdraw the loan");
        _loansIds.increment();

        Loans[_loansIds.current()] = Loan ({
            withdrawnAmount: _withdrawnAmount,
            withdrawnTimestamp: block.timestamp,
            //quantas parcelar já foram pagas:
            repaidLoansAmount: 1,
            //o valor total do montante pago:
            repaidLoansValue: 0
        });

        poolAmount -= _withdrawnAmount;

        emit loanWithdrawn(_withdrawnAmount, block.timestamp);
    }

    //return an specific loan created by the borrower
    function getLoan(uint256 _id) public view returns(Loan memory){
        return(Loans[_id]);
    }


    function howMuchShouldIPay(uint256 _id) public view returns(uint256) {
        uint256 amount = ((Loans[_id].withdrawnAmount / paymentFrequency) + ((Loans[_id].withdrawnAmount * interestRate / 1000) / paymentFrequency));
        return(amount);
    }

    function howMuchShouldIPayLate(uint256 _id, uint256 whenYouShouldHavePaid) public view returns(uint256) {
        //uint256 whenYouShouldHavePaid = (Loans[_id].withdrawnTimestamp + ((30 * 86400) * Loans[_id].repaidLoansAmount));
        uint256 amount = ((Loans[_id].withdrawnAmount / paymentFrequency) + ((Loans[_id].withdrawnAmount * interestRate / 1000) / paymentFrequency) + (((Loans[_id].withdrawnAmount * lateFee / 1000) * (block.timestamp - whenYouShouldHavePaid)) / 86400));
        return(amount);
    }

    function timeStamp() public view returns(uint256) {
        return(block.timestamp);
    }

    struct PrivateInvestor {
        address investor;
        uint256 totalAmountInvested;
        uint256 totalAmountReceived;
        uint256 totalAmountWithdrawed;
        bool isActive;
    }

    mapping(uint256 => PrivateInvestor) public PrivateInvestors;
    event investmentDone(uint256 id, uint256 USDCAmount, address lender);

    //mapping to verify if address is a private investor
    mapping(address => bool) isPrivateInvestor;

    mapping(address => uint256) public addressToInvestorId;


    Counters.Counter public _privateInvestorsCounter;


    function repayLoanTeste(uint256 _id, uint256 USDCAmount) public onlyContractEnabled() nonReentrant {

                uint256 privateInvestorAmount = USDCAmount * privateInvestorPoolFee / 1000;
                for (uint i = 1; i < _privateInvestorsCounter.current(); i++){
                    PrivateInvestors[i].totalAmountReceived += privateInvestorAmount * PrivateInvestors[i].totalAmountInvested / privateInvestorsPoolAmount;
                }
                }


    function repayLoan(uint256 _id, uint256 USDCAmount) public onlyContractEnabled() nonReentrant {
        require(Loans[_id].repaidLoansAmount < paymentFrequency + 1, "error with paymentFrequency");

        if((Loans[_id].withdrawnTimestamp + (((daysDue) * 86400) * Loans[_id].repaidLoansAmount) >= block.timestamp)) {
                uint256 amount = ((Loans[_id].withdrawnAmount / paymentFrequency) + ((Loans[_id].withdrawnAmount * interestRate / 1000) / paymentFrequency));
                require(USDCAmount >= amount, "amount not sufficient");
                uint256 scalablePoolAmount = USDCAmount * scalablePoolFee / 1000;
                bool sent = USDCAddress.transferFrom(msg.sender, scalablePool, scalablePoolAmount);
                require(sent, "Failed to repay the loan");


                //calculando a parte para os privateinvestor:
                uint256 privateInvestorAmount = USDCAmount * privateInvestorPoolFee / 1000;
                for (uint i = 1; i <= _privateInvestorsCounter.current(); i++){
                    PrivateInvestors[i].totalAmountReceived += privateInvestorAmount * PrivateInvestors[i].totalAmountInvested / privateInvestorsPoolAmount;
                }

                uint256 portfolioMultiAmount = USDCAmount * portfolioMultiPoolFee / 1000;
                USDCAddress.transferFrom(msg.sender, portfolioMulti, portfolioMultiAmount);



                Loans[_id].repaidLoansAmount += 1;
                Loans[_id].repaidLoansValue += USDCAmount;

                portfolioMultiInterface.distribute(USDCAmount);

                emit loanRepaid(_id, Loans[_id].repaidLoansAmount);
            }
        
        else if((Loans[_id].withdrawnTimestamp + ((daysDue * 86400) * Loans[_id].repaidLoansAmount) < block.timestamp)) {

                uint256 whenYouShouldHavePaid = (Loans[_id].withdrawnTimestamp + ((daysDue * 86400) * Loans[_id].repaidLoansAmount));

                uint256 amount = ((Loans[_id].withdrawnAmount / paymentFrequency) + ((Loans[_id].withdrawnAmount * interestRate / 1000) / paymentFrequency) + (((Loans[_id].withdrawnAmount * lateFee / 1000) * (block.timestamp - whenYouShouldHavePaid)) / 86400));
                require(USDCAmount >= amount);
                uint256 scalablePoolAmount = USDCAmount * scalablePoolFee / 1000;
                bool sent = USDCAddress.transferFrom(msg.sender, scalablePool, scalablePoolAmount);
                require(sent, "Failed to repay the loan");

                                //calculando a parte para os privateinvestor:
                uint256 privateInvestorAmount = USDCAmount * privateInvestorPoolFee / 1000;
                for (uint i = 1; i <= _privateInvestorsCounter.current(); i++){
                    PrivateInvestors[i].totalAmountReceived += privateInvestorAmount * PrivateInvestors[i].totalAmountInvested / privateInvestorsPoolAmount;
                }

                uint256 portfolioMultiAmount = USDCAmount * portfolioMultiPoolFee / 1000;
                bool sentPortfolioMultiAmount = USDCAddress.transferFrom(msg.sender, portfolioMulti, portfolioMultiAmount);
                require(sentPortfolioMultiAmount, "Failed to repay the loan");

                Loans[_id].repaidLoansAmount += 1;
                Loans[_id].repaidLoansValue += amount;

                portfolioMultiInterface.distribute(USDCAmount);

                emit loanRepaid(_id, Loans[_id].repaidLoansAmount);
        }
       

        }


    //function for private investors/backers being able to invest through the PrivateInvestor tranche:
    function lendToBorrowerPool(uint256 _USDCAmount) public onlyPoolEnabled() onlyContractEnabled() nonReentrant {
        require(poolAmount + _USDCAmount <= poolLimit);

    if(!PrivateInvestors[addressToInvestorId[msg.sender]].isActive){

            bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
            require(sent, "Failed to transfer the amount");

            poolAmount += _USDCAmount;
            privateInvestorsPoolAmount += _USDCAmount;
            _privateInvestorsCounter.increment();
            PrivateInvestors[_privateInvestorsCounter.current()] = PrivateInvestor ({
                investor: msg.sender,
                totalAmountInvested: _USDCAmount,
                totalAmountReceived: 0,
                totalAmountWithdrawed: 0,
                isActive: true
            });
            addressToInvestorId[msg.sender] = _privateInvestorsCounter.current();
            emit investmentDone(_privateInvestorsCounter.current(), _USDCAmount, msg.sender);

        }

        //se o investidor já existe, usar a sua struct:
        else {

            bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
            require(sent, "Failed to transfer the amount");

            poolAmount += _USDCAmount;
            PrivateInvestors[addressToInvestorId[msg.sender]].totalAmountInvested += _USDCAmount;
            emit investmentDone(addressToInvestorId[msg.sender], _USDCAmount, msg.sender);

        }
    }


    //função para portfolioMultiPool investir no contrato:
        function PortfolioMultilendToBorrowerPool(uint256 _USDCAmount) public onlyPoolEnabled() onlyContractEnabled() nonReentrant {
        bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
        require(sent, "Failed to lend to borrower pool");
        poolAmount += _USDCAmount;
    }

    //função para investidor privado retirar seu lucro:
    function withdrawGainsPrivateInvestor(uint256 _usdcAmount) public onlyContractEnabled onlyPoolEnabled nonReentrant {
        require(PrivateInvestors[addressToInvestorId[msg.sender]].isActive, "Not allowed investor");
        require(PrivateInvestors[addressToInvestorId[msg.sender]].totalAmountReceived - PrivateInvestors[addressToInvestorId[msg.sender]].totalAmountWithdrawed >= _usdcAmount, "You do not have enough money to withdraw");
        
        PrivateInvestors[addressToInvestorId[msg.sender]].totalAmountReceived += _usdcAmount;
        bool sent = USDCAddress.transfer(msg.sender, _usdcAmount);
        require(sent, "Failed to withdraw the loan");
    }
    

    
}
