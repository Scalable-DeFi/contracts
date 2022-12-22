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

interface KYC {
    function isSanctionsSafe(address) external view returns (bool);
    function currentlyAccredited(address) external view returns (bool);
}



contract PortfolioMultiPool is Ownable, ReentrancyGuard, ERC20, ERC20Burnable {

    using Counters for Counters.Counter;
    Counters.Counter public _investors;

    //endereço master, que chama as funções e paga o gas para outros usuários:
    address public oneAboveAll;


    ERC20 public USDCAddress;
    address public scalablePool;
    MasterLending public masterLendingAddress;
    KYC public KYCInterface;


    bool public contractEnabled;
    bool public poolEnabled;



    //LP structure:
    uint256 public LPTokensTotalAmount;

    
    //Pool structure:
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



    constructor(address _USDCAddress, uint256 _minInvestment, uint256 _poolLimit, string memory _name, string memory _symbol, address _oneAboveAll, KYC _KYCInterface)  ERC20(_name, _symbol) {
        USDCAddress = ERC20(_USDCAddress);
        contractEnabled = true;
        poolEnabled = true;
        poolLimit = _poolLimit;    
        minInvestment = _minInvestment;
        oneAboveAll = _oneAboveAll;
        KYCInterface = _KYCInterface;
    }


    function retrieveOneAboveAll() public view returns(address) {
        return oneAboveAll;
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

    function seeKYC(address _address) public view returns(bool){
        return KYCInterface.isSanctionsSafe(_address);
    }

    //MODIFIERS:
    modifier onlyKYC(address _address) {
        require(KYCInterface.isSanctionsSafe(_address) == true || _address == oneAboveAll);
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

    function investInPool(uint256 _USDCAmount, address _address) public onlyPoolEnabled() onlyContractEnabled() onlyKYC(msg.sender) {
        require(_USDCAmount >= minInvestment, "You need to invest more");

        address msgSender = msg.sender == oneAboveAll ? _address : msg.sender;

        //se investidor não existe ainda, criar struct:
        if(!Investors[addressToInvestorId[msgSender]].isActive){

            bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
            require(sent, "Failed to transfer the amount");


            //Investindo na pool e criando uma struct para guardar informações sobre o investimento
            totalAmountInvested += _USDCAmount;
            _investors.increment();
            Investors[_investors.current()] = Investor ({
                investor: msgSender,
                totalAmountInvested: _USDCAmount,
                totalAmountReceived: 0,
                totalAmountWithdrawed: 0,
                isActive: true
            });
            addressToInvestorId[msgSender] = _investors.current();
            emit newInvestorCreated(msgSender, _USDCAmount, _investors.current());

            //emitindo a quantidade par de LP tokens para o investidor:

            _mint(msgSender, _USDCAmount);


        }

        //se o investidor já existe, usar a sua struct:
        else {

            bool sent = USDCAddress.transferFrom(msg.sender, address(this), _USDCAmount);
            require(sent, "Failed to transfer the amount");

            totalAmountInvested += _USDCAmount;
            Investors[addressToInvestorId[msgSender]].totalAmountInvested += _USDCAmount;
            emit newInvestment(msgSender, _USDCAmount, addressToInvestorId[msgSender]);

            _mint(msgSender, _USDCAmount);

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
    }


    event usdcSwapped(address Investor, uint256 lpAmount, uint256 usdcAmount);

    function swapLPToUSDC(uint256 _LPAmount, address _address) public nonReentrant {

        address msgSender = msg.sender == oneAboveAll ? _address : msg.sender;

        require(USDCAddress.balanceOf(address(this)) > 0, "There is no USDC in the pool");
        require(balanceOf(msgSender) >= _LPAmount, "You does not have the required amount");
        
        uint256 amount = _LPAmount * USDCAddress.balanceOf(address(this)) / totalSupply();

        _burn(msgSender, _LPAmount);

        USDCAddress.transfer(msg.sender, amount);

        emit usdcSwapped(msgSender, _LPAmount, amount);

    }


    mapping(address => uint256) masterPoolToAmountInvested;

    function lendToBorrower(uint256 amount, address _address) public nonReentrant onlyOwner {
        USDCAddress.increaseAllowance(_address, amount);
        masterLendingAddress = MasterLending(_address);
        masterLendingAddress.PortfolioMultilendToBorrowerPool(amount);
        masterPoolToAmountInvested[_address] += amount;

    }
   
}
