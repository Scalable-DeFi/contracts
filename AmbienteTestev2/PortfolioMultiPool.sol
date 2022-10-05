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


/*Este é o contrato do empréstimo em si. Toda vez que um borrower quiser abrir uma ordem de empréstimos, deverá ser feito um
deploy deste contrato, inserindo as variáveis específicas no constructor após a negociação com o borrower.
Aqui o private investor poderá investir, bem como a multiportfoliopool. Após a angariação de fundos e abertura da pool,
o borrower poderá sacar os empréstimos. As parcelas dos empréstimos com o juros acrescentados também será paga por esse contrato,
que distribuirá proporcionalmente para cada investidor.
*/

//  is ERC721URIStorage, Ownable
contract MasterLending is Ownable, ReentrancyGuard{

    using Counters for Counters.Counter;
    Counters.Counter public _loansIds;

    //Pools e endereços:
    IERC20 public USDCAddress;
    address public poolBorrower;
    address public portfolioMulti;
    address public scalablePool;
    PortfolioMultiPool public portfolioMultiInterface;

    bool public contractEnabled;
    bool public poolEnabled;

    
    //**Pool structure**:


    //Juros
    uint256 public interestRate;
    //Pagamanto adicional quando parcelas estão atrasadas (por dia), e.g. 5%. 
    uint256 public lateFee;
    //O montante atual de USDC na pool:
    uint256 public poolAmount;
    //O quanto das pool o borrower já sacou:
    uint256 public withdrawnAmount;
    //O limite total de USDC que a pool aceita:
    uint256 public poolLimit;
    //Total investido pelos private investors:
    uint256 public privateInvestorsPoolAmount;
    //A porcentagem do lucro que a scalable irá receber:
    uint256 public scalablePoolFee;
    //A porcentagem do lucro que os private investors irão receber:
    uint256 public privateInvestorPoolFee;
    //A porcentagem do lucro que o portfolioMulti irá receber:
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



    //Setar o endereço do contrato do portfolio multi
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


    //Toda vez que o borrower sacar um montante, criaremos uma "Loan" que armazenará o quanto ele sacou, quando e quanto ele 
    //já pagou.
    struct Loan {
        uint256 withdrawnAmount;
        uint256 withdrawnTimestamp;
        uint32 repaidLoansAmount;
        uint256 repaidLoansValue;
    }


    //id to loan
    mapping(uint256 => Loan) public Loans;

    //eventos para o frontend:
    event loanWithdrawn(uint256 withdrawnAmount, uint256 withdrawnTimestamp);
    event loanRepaid(uint256 loanId, uint32 repaidLoansAmount);

    //Função que permite o borrower sacar da pool:
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


    //Funções para verificar o quanto deverá ser pago e quanto será pago caso atrase os pagamentos:

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


    //Função para repagar uma parcela da Loan:
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
                for (uint i = 1; i <= _lendingsIds.current(); i++){
                    uint256 fee = (Lendings[i].USDCAmount / privateInvestorAmount);
                    uint256 USDCFee = privateInvestorAmount * fee;
                    bool sentPrivateInvestorAmount = USDCAddress.transferFrom(msg.sender, Lendings[i].lender, USDCFee);
                    require(sentPrivateInvestorAmount, "Failed to repay the loan");
                }

                uint256 portfolioMultiAmount = USDCAmount * portfolioMultiPoolFee / 1000;
                bool sentPortfolioMultiAmount = USDCAddress.transferFrom(msg.sender, portfolioMulti, portfolioMultiAmount);
                require(sentPortfolioMultiAmount, "Failed to repay the loan");


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
                for (uint i = 1; i <= _lendingsIds.current(); i++){
                    uint256 fee = (Lendings[i].USDCAmount / privateInvestorAmount);
                    uint256 USDCFee = privateInvestorAmount * fee;
                    bool sentPrivateInvestorAmount = USDCAddress.transferFrom(msg.sender, Lendings[i].lender, USDCFee);
                    require(sentPrivateInvestorAmount, "Failed to repay the loan");
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


    //Toda vez que um privateInvestor fizer um empréstimo na pool, será criado uma lending que armazena seu endereço,
    //o quanto investiu e quando.

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

    //função para os privateinvestors serem capazes de investir na pool:
    function lendToBorrowerPool(uint256 _USDCAmount) public onlyPoolEnabled() onlyContractEnabled() nonReentrant {
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

    

    
}