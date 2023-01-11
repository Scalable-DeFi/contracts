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
    function retrieveOneAboveAll() external view returns (address);
}

interface KYC {
    function isSanctionsSafe(address) external view returns (bool);
    function currentlyAccredited(address) external view returns (bool);
}


//  is ERC721URIStorage, Ownable
contract MasterLending is Ownable, ReentrancyGuard{

    using Counters for Counters.Counter;
    Counters.Counter public _privateInvestorsCounter;
    Counters.Counter public _loansIds;

    IERC20 public USDCAddress;
    address public poolBorrower;
    address public portfolioMulti;
    address public scalablePool;
    PortfolioMultiPool public portfolioMultiInterface;
    KYC public KYCInterface;

    bool public contractEnabled;
    bool public poolEnabled;

    
    //**Pool structure**:


    //Fixed interest rate
    uint256 public interestRate;
    //Additional interest owed when payments are late, e.g. 5%. 
    uint256 public lateFee;
    //The current amount of USDC in the pool:
    uint256 public poolAmount;
    //The total amount of USDC invested in the pool:
    uint256 public allTimePoolInvested;
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


    //estrutura do investidor privado
    struct PrivateInvestor {
        address investor;
        uint256 totalAmountInvested;
        uint256 totalAmountReceived;
        uint256 totalAmountWithdrawed;
        bool isActive;
    }

    //estrutura do empréstimo
    struct Loan {
        uint256 withdrawnAmount;
        uint256 withdrawnTimestamp;
        uint32 repaidLoansAmount;
        uint256 repaidLoansValue;
    }


    //id to privateInvestor
    mapping(uint256 => PrivateInvestor) public PrivateInvestors;
    
    //id to loan
    mapping(uint256 => Loan) public Loans;

    //mapping to verify if address is a private investor
    mapping(address => bool) isPrivateInvestor;

    mapping(address => uint256) public addressToInvestorId;


    event investmentDone(uint256 id, uint256 USDCAmount, address lender);
    event loanWithdrawn(uint256 withdrawnAmount, uint256 withdrawnTimestamp);
    event loanRepaid(uint256 loanId, uint32 repaidLoansAmount);
    event withdrawnGainsPrivateInvestor(uint256 id, uint256 USDCAmount, address lender); 
    event withdrawnInvestmentPrivateInvestor(uint256 id, uint256 USDCAmount, address lender); 


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

    function setKYCInterface(KYC _KYCInterface) public  onlyOwner() {
        KYCInterface = _KYCInterface;
    }


    //MODIFIERS:
    modifier onlyKYC(address _address) {
        require(KYCInterface.isSanctionsSafe(_address));
        require(KYCInterface.currentlyAccredited(_address));
        _;
    }

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



    //allow the borrower to get the credit from the pool:
    //permite aos tomadores retirarem o crédito da pool:
    function withdrawFromPool(uint256 _withdrawnAmount) public onlyBorrower onlyContractEnabled nonReentrant {
        
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

        bool sent = USDCAddress.transfer(msg.sender, _withdrawnAmount);
        require(sent, "Failed to withdraw the loan");

        emit loanWithdrawn(_withdrawnAmount, block.timestamp);
    }

    //função para calcular quanto o tomador deve pagar na sua próxima parcela do empréstimo
    function howMuchShouldIPay(uint256 _id) public view returns(uint256) {
        if((Loans[_id].withdrawnTimestamp + (((daysDue) * 86400) * Loans[_id].repaidLoansAmount) >= block.timestamp)) {
                uint256 amount = ((Loans[_id].withdrawnAmount / paymentFrequency) + ((Loans[_id].withdrawnAmount * interestRate / 1000) / paymentFrequency)); 
                return(amount);
                }

        else if((Loans[_id].withdrawnTimestamp + ((daysDue * 86400) * Loans[_id].repaidLoansAmount) < block.timestamp)) { 
                uint256 whenYouShouldHavePaid = (Loans[_id].withdrawnTimestamp + ((daysDue * 86400) * Loans[_id].repaidLoansAmount));
                uint256 amount = ((Loans[_id].withdrawnAmount / paymentFrequency) + ((Loans[_id].withdrawnAmount * interestRate / 1000) / paymentFrequency) + (((Loans[_id].withdrawnAmount * lateFee / 1000) * (block.timestamp - whenYouShouldHavePaid)) / 86400));
                return(amount);
        }
    }



    function repayLoan(uint256 _id, uint256 USDCAmount, address _address) public onlyContractEnabled nonReentrant {
        require(Loans[_id].repaidLoansAmount < paymentFrequency + 1, "error with paymentFrequency");

        if((Loans[_id].withdrawnTimestamp + (((daysDue) * 86400) * Loans[_id].repaidLoansAmount) >= block.timestamp)) {
                uint256 amount = ((Loans[_id].withdrawnAmount / paymentFrequency) + ((Loans[_id].withdrawnAmount * interestRate / 1000) / paymentFrequency));
                require(USDCAmount >= amount, "amount not sufficient");
                uint256 scalablePoolAmount = USDCAmount * scalablePoolFee / 1000;
                bool sent = USDCAddress.transferFrom(msg.sender, scalablePool, scalablePoolAmount);
                require(sent, "Failed to repay the loan");


                //calculando a parte para os privateinvestor:
                uint256 privateInvestorAmount = USDCAmount * privateInvestorPoolFee / 1000;
                USDCAddress.transferFrom(msg.sender, address(this), privateInvestorAmount);
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
    function lendToBorrowerPool(uint256 _USDCAmount, address _address) public onlyPoolEnabled onlyContractEnabled nonReentrant {
        require(poolAmount + _USDCAmount <= poolLimit);

        address msgSender = msg.sender == portfolioMultiInterface.retrieveOneAboveAll() ? _address : msg.sender;

        if(!PrivateInvestors[addressToInvestorId[msgSender]].isActive){

            bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
            require(sent, "Failed to transfer the amount");

            poolAmount += _USDCAmount;
            allTimePoolInvested += _USDCAmount;
            privateInvestorsPoolAmount += _USDCAmount;
            _privateInvestorsCounter.increment();
            PrivateInvestors[_privateInvestorsCounter.current()] = PrivateInvestor ({
                investor: msgSender,
                totalAmountInvested: _USDCAmount,
                totalAmountReceived: 0,
                totalAmountWithdrawed: 0,
                isActive: true
            });
            addressToInvestorId[msgSender] = _privateInvestorsCounter.current();
            emit investmentDone(_privateInvestorsCounter.current(), _USDCAmount, msgSender);

        }

        //se o investidor já existe, usar a sua struct:
        else {

            bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
            require(sent, "Failed to transfer the amount");

            poolAmount += _USDCAmount;
            allTimePoolInvested += _USDCAmount;
            PrivateInvestors[addressToInvestorId[msgSender]].totalAmountInvested += _USDCAmount;
            emit investmentDone(addressToInvestorId[msgSender], _USDCAmount, msgSender);

        }
    }


    //função para portfolioMultiPool investir no contrato:
    function PortfolioMultilendToBorrowerPool(uint256 _USDCAmount) public onlyPoolEnabled onlyContractEnabled nonReentrant {
        bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
        require(sent, "Failed to lend to borrower pool");
        poolAmount += _USDCAmount;
        allTimePoolInvested += _USDCAmount;
    }



    //função para investidor privado retirar seu lucro:
    function withdrawGainsPrivateInvestor(uint256 _usdcAmount, address _address) public onlyContractEnabled onlyPoolEnabled nonReentrant {

        address msgSender = msg.sender == portfolioMultiInterface.retrieveOneAboveAll() ? _address : msg.sender;

        require(PrivateInvestors[addressToInvestorId[msgSender]].isActive, "Not allowed investor");
        require(PrivateInvestors[addressToInvestorId[msgSender]].totalAmountReceived - PrivateInvestors[addressToInvestorId[msgSender]].totalAmountWithdrawed >= _usdcAmount, "You do not have enough money to withdraw");
        
        

        PrivateInvestors[addressToInvestorId[msgSender]].totalAmountWithdrawed += _usdcAmount;
        bool sent = USDCAddress.transfer(msg.sender, _usdcAmount);
        require(sent, "Failed to withdraw the loan");
        emit withdrawnGainsPrivateInvestor(addressToInvestorId[msgSender], _usdcAmount, msgSender);
    }



    //função para investidor privado retirar seu capital de investimento:
    function withdrawInvestmentPrivateInvestor(uint256 _usdcAmount, address _address) public onlyContractEnabled onlyPoolEnabled nonReentrant {

        address msgSender = msg.sender == portfolioMultiInterface.retrieveOneAboveAll() ? _address : msg.sender;

        require(PrivateInvestors[addressToInvestorId[msgSender]].isActive, "Not allowed investor");
        require(PrivateInvestors[addressToInvestorId[msgSender]].totalAmountInvested >= _usdcAmount, "You do not have enough money to withdraw");
        require(poolAmount >= _usdcAmount, "You do not have enough money to withdraw");

        PrivateInvestors[addressToInvestorId[msgSender]].totalAmountInvested -= _usdcAmount;
        poolAmount -= _usdcAmount;
        bool sent = USDCAddress.transfer(msg.sender, _usdcAmount);
        require(sent, "Failed to withdraw the investment");
        emit withdrawnGainsPrivateInvestor(addressToInvestorId[msgSender], _usdcAmount, msgSender);


    }
    


}
