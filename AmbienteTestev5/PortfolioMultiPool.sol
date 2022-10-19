//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


interface MasterLending {
    function PortfolioMultilendToBorrowerPool(uint256) external;
}

//DÚVIDA: Essa pool emprestou dia 11/08 uma quantidade de dinheiro para um borrower, dia 12/08 uma pessoa X investe nessa pool. Quando a pool recebor o pagamento do borrower, elas distribuirá também
//para a pessoa X? mesmo se o empréstimo foi feito antes da pessoa X entrar na pool?


contract PortfolioMultiPool is Ownable, ReentrancyGuard, ERC20, ERC20Burnable {

    using Counters for Counters.Counter;
    Counters.Counter public _investors;

    ERC20 public USDCAddress;
    address public poolBorrower;
    address public scalablePool;
    MasterLending public masterLendingAddress;

    bool public contractEnabled;
    bool public poolEnabled;



    //LP structure:
    uint256 public LPTokensTotalAmount;

    
    //Pool structure:
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
    //Total amount invested by the normal investors:
    uint256 public totalAmountInvested;
    //Total amount received from the masterLending pools:
    uint256 public totalAmountReceived;






    constructor(address _USDCAddress, uint256 _minInvestment, uint256 _poolLimit, string memory _name, string memory _symbol)  ERC20(_name, _symbol) {
        USDCAddress = ERC20(_USDCAddress);
        contractEnabled = true;
        poolEnabled = true;
        poolLimit = _poolLimit;    
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





    struct Investor {
        address investor;
        uint256 totalAmountInvested;
        uint256 totalAmountReceived;
        uint256 totalAmountWithdrawed;
        bool isActive;
    }

    event newInvestorCreated(address Investor, uint256 totalAmountInvested, uint256 id);
    event newInvestment(address Investor, uint256 newAmount, uint256 id);
    event newAmountReceived(address Investor, uint256 amount, uint256 id);

    mapping(uint256 => Investor) public Investors;
    mapping(address => uint256) public addressToInvestorId;

    function investInPool(uint256 _USDCAmount) public onlyPoolEnabled() onlyContractEnabled() {
        require(_USDCAmount >= minInvestment, "You need to invest more");


        //se investidor não existe ainda, criar struct:
        if(!Investors[addressToInvestorId[msg.sender]].isActive){

            bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
            require(sent, "Failed to transfer the amount");


            //Investindo na pool e criando uma struct para guardar informações sobre o investimento
            poolAmount += _USDCAmount;
            totalAmountInvested += _USDCAmount;
            _investors.increment();
            Investors[_investors.current()] = Investor ({
                investor: msg.sender,
                totalAmountInvested: _USDCAmount,
                totalAmountReceived: 0,
                totalAmountWithdrawed: 0,
                isActive: true
            });
            addressToInvestorId[msg.sender] = _investors.current();
            emit newInvestorCreated(msg.sender, _USDCAmount, _investors.current());

            //emitindo a quantidade par de LP tokens para o investidor:

            _mint(msg.sender, _USDCAmount);


        }

        //se o investidor já existe, usar a sua struct:
        else {

            bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
            require(sent, "Failed to transfer the amount");

            poolAmount += _USDCAmount;
            totalAmountInvested += _USDCAmount;
            Investors[addressToInvestorId[msg.sender]].totalAmountInvested += _USDCAmount;
            emit newInvestment(msg.sender, _USDCAmount, addressToInvestorId[msg.sender]);

            _mint(msg.sender, _USDCAmount);

        }
        

    }

    //fazer um mapping de contratos das pool borrowers, informando se eles fizeram pagamento ou não:
    mapping(address => bool) public isMasterPool;

    function modifyIsMasterPool(bool _bool, address _address) public onlyOwner() {
        isMasterPool[_address] = _bool;
    }

    //função para distribuir quanto cada um possui de reward para retirar:
    function distribute(uint256 _USDCAmount) public  {
        require(isMasterPool[msg.sender], "You are not a verified master pool");

        totalAmountReceived += _USDCAmount;

        for (uint256 i = 1; i <= _investors.current(); i++){
            if(Investors[i].isActive){
                uint256 amount = _USDCAmount * Investors[i].totalAmountInvested / poolAmount;
                Investors[i].totalAmountReceived += amount;
                emit newAmountReceived(Investors[i].investor, amount, i);
            }
        }

    }



    function swapUSDCToLPToken(uint256 _LPAmount) public nonReentrant {
        require(poolAmount > 0, "There is no USDC in the pool");
        require(balanceOf(msg.sender) >= _LPAmount, "You does not have the required amount");
        
        uint256 amount = _LPAmount * poolAmount / totalSupply();

        poolAmount -= amount;


        burn(_LPAmount);

        USDCAddress.transfer(msg.sender, amount);

    }


    mapping(address => uint256) masterPoolToAmountInvested;

    function lendToBorrower(uint256 amount, address _address) public nonReentrant onlyOwner {
        USDCAddress.increaseAllowance(_address, amount);
        masterLendingAddress = MasterLending(_address);
        masterLendingAddress.PortfolioMultilendToBorrowerPool(amount);
        masterPoolToAmountInvested[_address] += amount;

    }

        //Finalmente, função chamada para repartir os ganhos da pool:
    /* function distributeGains(uint256 _USDCAmount) public onlyOwner() {
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
    */

    //Permitir investidor sacar seu dinheiro:
    //Isso será permitido? Já que pode não ter dinheiro na pool por conta do empréstimo para borrowers
    /*
    function withdrawAmount(uint256 _USDCAmount) public onlyContractEnabled() onlyPoolEnabled() {
        require(_USDCAmount <= Investors[addressToInvestorId[msg.sender]].totalAmountReceived);
        bool sent = USDCAddress.transfer(msg.sender, _USDCAmount);
        require(sent, "Failed to withdraw the loan");
    }
    */
   
}