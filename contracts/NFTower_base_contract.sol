// SPDX-License-Identifier: NFTower
pragma solidity >=0.8.0;


//import "./ERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


//@gilad
// EtherScan entry:  https://ropsten.etherscan.io/tx/0x1e8847b95021e4b9405410f569ab81e7edf9c6b8e89f3485a5fb4f34bb19bbc7
// contract address:    0xEC33f510fA064D960eDf4eE6679f2B0A9d3a8af9
// owner address:       0x1da0ebd30170d8c289ca03b256757e6aa271223e 

contract GiladContract is IERC721Receiver { 
    
    //@gilad create dev env: custom ERC721 token ; deploy contract on testnet; invoke contract functions
    //      size optimization: add cost 20K gas per word ; modify cost: 5K 
    // also: add multi-payment functions 
    //      disable anonPayment storage + events (flag controlled)

    //  ifan nft is marked NOT for sale: clear its approved operator == set it to address(0)
    
/* @gilad
        simplify payment process:
            1. you make monthly payment (half a day GRACE)
            2. after: undue date shifts 30 days;
            3. on returning loan (or marke sell) you pay loan sum + RELATIVE interest
            4. add function: payAhead(nft, numOfPaidMonths)
            
    */   
    
    //@doc data structures
    //--------------------
    /*struct LoanOffer {// 6 words 
        address contractAddr;//20
        uint tokenId;//32
        uint loanSum;//32
        uint monthlyInterest;//32
        uint loanPeriod;//32 
        uint offerIsValidUntil;//32 
    }*/

    struct LoanOffer {// 2 words 
        uint256 tokenId;//32
        address contractAddr;//20
        uint32 loanSumMEth;//4 in MilliEther max = 4M Ether
        uint16 monthlyInterestMEth;//2  in MilliEther max = 65 Ether
        uint16 loanPeriodInMonths;//2 
        uint32 offerIsValidUntilDate;//4 
    }

    
    /*struct MonthlyPayment { //2 words
        uint startDate; //32 
        uint endDate; //32 
    }*/
    
    
    /*struct ActualLoan { //11 words 
        address origOwner;// 20 
        LoanOffer terms; //6*32 
        bool tryToSell; //1 
        uint sellingPrice; //32  
        MonthlyPayment pendingPayment;//2*32 
    }*/

    struct ActualLoan { //3 words
        LoanOffer terms; //2*32 
        address origOwner;// 20 
        uint32 sellingPriceMEth; //4  in MilliEther max = 4M Ether
        uint32 nextPaymentUntilDate; //4 
    }
        
    struct AnonPayment {
        uint sumInWei;
        address from;
        uint date;
    }
    ///////////
    
    
    
    bytes4 constant ERC721_RECEIVED = 0xf0b9e5ba;
    
    uint32 constant EXTENDED_MONTH = 31 days; // allow some grace time 


    //@doc roles 
    //-----------
    address private owner;
    address private manager; // the platform itself should be assigned with a manager role 
    
    
    //@doc contract state members
    bool private onlyNftOwnerCanApply; 
    uint256 private maxLoanMEth;
    bool private isActive;
    bool private acceptNewLoans;
    bool private writeToAnonArray; 
    bool private emitAnonEvent; 


    //@doc data members
    mapping (bytes32  => LoanOffer) private loanOffersMap;
    
    mapping (bytes32  => ActualLoan) private actualLoansMap;
    
    AnonPayment[] private anonPayments; 
    
    
    //@doc events 
    //--------------
    event OwnerSet(address indexed oldOwner, address indexed newOwner);
    
    event ManagerSet(address indexed oldManager, address indexed newManager);
    
    event IsActiveSet(bool indexed isActive);
    
    event MaxLoanSet(uint indexed maxLoanME);
    
    event NewLoanOffer(
                address indexed contractAddr_,
                uint indexed tokenId_,
                uint indexed loanSumMEth_,
                uint monthlyInterestMEth_,
                uint loanPeriodInMonths_,
                uint offerIsValidUntilDate_ );
                
    event LoanWasStarted(address indexed contractAddr_,
                         uint indexed tokenId_,
                         address indexed nftOwner,
                         uint loanSumMEth,
                         uint monthlyInterestMEth,
                         uint loanPeriodInMonths);                          
    

    event LoanSuccessfullyPaidFor(address indexed contractAddr_,  
                                  uint indexed tokenId_ , 
                                  address indexed origOwner, 
                                  uint loanSumMEth,
                                  uint remainingInerestMEth);
            
    event AnonimousPaymentReceived(uint indexed sumInWei, address indexed from, uint date);


    event LoanPeriodicalInterestPaid(address indexed contractAddr_,  
                                     uint indexed tokenId_ , 
                                     uint indexed totalInterestMEth, 
                                     uint numMonths,
                                     uint nextPaymentUntilDate);

    event PaymentPeriodIncreased(
                    address indexed contractAddr_, 
                    uint indexed tokenId_ , 
                    uint priorEndDate, 
                    uint newEndDate);

    event NftPurchasedOnMarketplace(address indexed contractAddr_, 
                                    uint indexed tokenId_ , 
                                    address indexed origOwner, 
                                    uint totalPaymnentInWei, 
                                    uint ownersCutInWei);


    event LoanSellingStatusChanged(address indexed contractAddr_,
                                    uint indexed tokenId_,
                                    address indexed nftOwner,
                                    uint sellingPriceMEth_);

    event LoanOfferCancelled(address indexed contractAddr_, uint indexed tokenId_);

    event AcceptingNewLoansChanged(bool indexed acceptingNewLoans);
    
    event WriteToAnonArraySet(bool writeToAnonArray);

    event EmitAnonEventSet(bool emitAnonEvent);

    /////////



    //@doc modifiers
    //----------------
    modifier ownerOnly() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }
     
    modifier managerOnly() {
        require(msg.sender == owner || msg.sender == manager, "Caller is not manager");
        _;
    }
    
    modifier onlyIfActive() {
        require(isActive == true, "Contract is not active");
        _;
    }
                                                
    modifier onlyIfAcceptingNewLoans() {
        require(acceptNewLoans == true, "Contract is not accepting new loans");
        _;
    }
    
    ////////
            
            
            
    //@doc called once on contract deployment            
    constructor() {
        isActive = true;    
        acceptNewLoans = true;
        
        writeToAnonArray = false;
        emitAnonEvent = false;

        onlyNftOwnerCanApply = false;
        owner = msg.sender; 
        manager = msg.sender;
        maxLoanMEth = 2000; //== 2 ether 
        emit OwnerSet(address(0), owner);
    }
     
     
    //@doc platform provides issues a loan offer to nft
    //      @req: if onlyNftOwnerCanApply => msg.sender should be ownerOrApproved_
    //      TODO >> an alternative offer is to omit the offer model, 
    //              only keep offers in a protected DB and allow the user 
    //              to enter the loan and pass the loan params in a single 
    //              command initiated by blicking a btn in our site 
    //              the site logic will populate the request params and, 
    //              most importantly, will validate them against the protected DB 
    //              record according to the emitted event.
    //              The problem here is that we still need another transaction to issue 
    //              payment only after loan terms where approved, so no real gain
    function addLoanOffer(address contractAddr_,
                          uint tokenId_,
                          address loanRequestor_,
                          uint loanSumMEth_,
                          uint monthlyInterestMEth_,
                          uint loanPeriodInMonths_,
                          uint offerIsValidUntilDate_) 
                          external managerOnly onlyIfAcceptingNewLoans onlyIfActive {
        bytes32 key = getNFTKey(contractAddr_, tokenId_);
        if (onlyNftOwnerCanApply) { 
            // Allow limiting loan offers by the platform to owners or approvers
            require(loanRequestor_ != address(0), "Loan requestor address must be passed when in owner-only mode");
            bool ownerOrApproved_ = isOwnerOrApproved(loanRequestor_, contractAddr_, tokenId_);
            require(ownerOrApproved_, "Loan offer requestor is neither NFT owner or approved"); 
        }
        require(contractAddr_ != address(0), "Bad NFT contract address");
        require(loanOffersMap[key].loanSumMEth == 0, "A loan offer for this NFT was already issued");
        require(actualLoansMap[key].terms.tokenId == 0, "A loan for this NFT already exists"); 

        uint loanSumInWei = milliEtherToWei(loanSumMEth_);
        require(address(this).balance >= loanSumInWei, "Insufficient contract balance");
        
        loanOffersMap[key] = LoanOffer(
                tokenId_,
                contractAddr_,
                uint32(loanSumMEth_),
                uint16(monthlyInterestMEth_),
                uint16(loanPeriodInMonths_),
                uint32(offerIsValidUntilDate_) );
        
        emit NewLoanOffer(
                contractAddr_,
                tokenId_,
                loanSumMEth_,
                monthlyInterestMEth_,
                loanPeriodInMonths_,
                offerIsValidUntilDate_ );
    }


    //@doc nft owner accepts loan terms
    //      @req: contract has sufficient balance
    //      @req: onlyIfAcceptingNewLoans
    //      @req: offer is still valid 
    //      @req: loanSum <= maxLoan
    //      @req: contract has sufficient balance
    //      @req: onlyIfAcceptingNewLoans
    //      @req: msg.sender s/b owner/approved operator -- else nftContract.safeTransferFrom will fail
    //      @par: tryToSell_, sellingPrice_
    //      @payInterestNow: pay 1st month interest now to save gas 
    function startLoan(address contractAddr_, uint tokenId_, bool payInterestNow_,
                        bool tryToSell_, uint sellingPriceMEth_) 
                        payable external onlyIfAcceptingNewLoans onlyIfActive {

        if (tryToSell_ == true) {
            require(sellingPriceMEth_ > 0, "Selling price not set");    
        } else {
            require(sellingPriceMEth_ == 0, "Price set for non-sell NFT");  
        }
        uint _now = block.timestamp;
        require(contractAddr_ != address(0), "Bad NFT contract address");
        bytes32 key = getNFTKey(contractAddr_, tokenId_);
        
        LoanOffer storage offer = getLoanOffer(key, contractAddr_, tokenId_);

        require(offer.offerIsValidUntilDate >= _now, "Offer is no longer valid");
        require(offer.loanSumMEth <= maxLoanMEth, "Loan sum exceeds max loan");
        
        uint loanSumInWei = milliEtherToWei(offer.loanSumMEth);
        
        uint firstInterestInWei = 0;
        if (payInterestNow_ == true) {
            firstInterestInWei = milliEtherToWei(offer.monthlyInterestMEth);
        }
        require(address(this).balance >= loanSumInWei - firstInterestInWei, "Insufficient contract balance");

        require(actualLoansMap[key].terms.tokenId == 0, "A loan for this NFT already exists"); 
        delete loanOffersMap[key];
        
        // transfer token to contract address;
        IERC721 nftContract = IERC721(contractAddr_);
        address nftOwner = nftContract.ownerOf(tokenId_);
        
        // if the safeTransfer works, msg.sender is either the nft owner or an approved operator
        nftContract.safeTransferFrom(nftOwner, address(this), tokenId_);

        //MonthlyPayment memory pendingPayment_ = MonthlyPayment({startDate: _now, endDate: _now+EXTENDED_MONTH}); //@gilad
        
        uint32 payUntilDate_ = uint32(_now + EXTENDED_MONTH);
        if (payInterestNow_ == true) {
            payUntilDate_ += EXTENDED_MONTH;
        }
        actualLoansMap[key] = ActualLoan(offer, nftOwner, uint32(sellingPriceMEth_), payUntilDate_);

        // call below will use all available gas
        (bool wasSent, ) = nftOwner.call{value: loanSumInWei - firstInterestInWei}("");
        require(wasSent == true, "Failed to send payment to NFT owner");

        emit LoanWasStarted(contractAddr_, 
                            tokenId_,
                            nftOwner,
                            offer.loanSumMEth,
                            offer.monthlyInterestMEth,
                            offer.loanPeriodInMonths);


        if (payInterestNow_ == true) {
             emit LoanPeriodicalInterestPaid(contractAddr_, tokenId_ , 
                    offer.monthlyInterestMEth, 1, payUntilDate_);
        }
    }
    
    //@doc pay monthly interest
    function periodicalPayLoanInterest(address contractAddr_, uint tokenId_) 
                                        payable external onlyIfActive  {
        payLoanInterestForMultipleMonths(contractAddr_, tokenId_, 1);                                             
    }

    //@doc gas optimization method: pay multiple month interest
    function payLoanInterestForMultipleMonths(address contractAddr_, uint tokenId_, uint numMonths_) 
                                        payable public onlyIfActive {
        require(numMonths_ > 0, "Zero period specified");                                    
        require(contractAddr_ != address(0), "Bad contract address");
        bytes32 key = getNFTKey(contractAddr_, tokenId_);
        
        ActualLoan storage loan = getActualLoan(key, contractAddr_, tokenId_);
        
        require(loan.terms.monthlyInterestMEth > 0, "Bad monthly interest value");
        
        
        uint lastPaymentDay = loan.nextPaymentUntilDate;
        
        // do not accept overdue payments (contract owner pay shift endDate see #increasePaymentPeriod)
        require(block.timestamp <= lastPaymentDay, "Payment is overdue");
        
        uint totalInterestMEth = numMonths_ * loan.terms.monthlyInterestMEth;
        uint totalInterestInWei = milliEtherToWei(totalInterestMEth);
        
        require(msg.value >= totalInterestInWei, "Transaction does not carry enough funds");
        
        uint refundSumInWei = msg.value - totalInterestInWei;

        //  return refundSum to msg.sender;
        if (refundSumInWei > 0) {
            (bool wasRefunded, ) = msg.sender.call{value: refundSumInWei}("");
            require(wasRefunded, "Failed to refund sender");
        }
        
        lastPaymentDay += (numMonths_ * EXTENDED_MONTH); // shift due until date by paid-for months 
        
        loan.nextPaymentUntilDate = uint32(lastPaymentDay);
        
        emit LoanPeriodicalInterestPaid(contractAddr_,  tokenId_ , 
            totalInterestMEth, numMonths_, lastPaymentDay);

    }

            
    //@doc (pre) exit loan
    function payLoanAndObtainNft(address contractAddr_, uint tokenId_) 
                                 payable external onlyIfActive {
        require(contractAddr_ != address(0), "Bad NFT contract address");
        bytes32 key = getNFTKey(contractAddr_, tokenId_);
        
        ActualLoan storage loan = getActualLoan(key, contractAddr_, tokenId_);
        
        require(loan.terms.monthlyInterestMEth > 0, "Bad monthly interest");
        
        // pay remaining interest + loan         
        //uint monthlyInterestInWei = milliEtherToWei(loan.terms.interestME);
        
        //MonthlyPayment storage lastPayment = loan.payments[loan.payments.length-1];
        //MonthlyPayment storage pendingPayment_ = loan.pendingPayment;
        //uint lastPeriodStartDate = pendingPayment_.startDate;
        //uint remainingInerest = (block.timestamp - lastPeriodStartDate) * monthlyInterestInWei / 30 days;
        
        uint remainintInterestMEth = loan.terms.monthlyInterestMEth; //@gilad >> better calc partial payment 
        uint totalPaymentMEth = loan.terms.loanSumMEth + remainintInterestMEth;
        uint totalPaymentInWei = milliEtherToWei(totalPaymentMEth);
        
        require(msg.value >= totalPaymentInWei, "Message value lesser than total payment");
        uint refundSumInWei = msg.value - totalPaymentInWei;

        //  return refundSum to msg.sender;
        if (refundSumInWei > 0) {
            (bool wasRefunded, ) = msg.sender.call{value: refundSumInWei}("");
            require(wasRefunded, "Failed to refund message sender");
        }

        // pass nft to orig owner  
        IERC721 nftContract = IERC721(contractAddr_);
        nftContract.safeTransferFrom(address(this), loan.origOwner, tokenId_);

        // remove from actualLoans
        delete actualLoansMap[key];
        
        emit LoanSuccessfullyPaidFor(contractAddr_,  tokenId_ , 
                loan.origOwner, loan.terms.loanSumMEth, remainintInterestMEth);
    }

    
    //@doc provide grace period 
    function increasePaymentPeriod(address contractAddr_, uint tokenId_, uint32 timeAdded_) 
                        external onlyIfActive ownerOnly {
        require(contractAddr_ != address(0), "Bad contract address");
        bytes32 key = getNFTKey(contractAddr_, tokenId_);
        
        ActualLoan storage loan = getActualLoan(key, contractAddr_, tokenId_);
        
        require(loan.terms.monthlyInterestMEth > 0, "Bad monthly interest value");
        
        //MonthlyPayment storage pendingPayment_ = loan.pendingPayment;
        uint priorEndDate = loan.nextPaymentUntilDate;
        //pendingPayment_.endDate += timeAdded_;
        loan.nextPaymentUntilDate += timeAdded_;
        
        emit PaymentPeriodIncreased(contractAddr_, tokenId_ , priorEndDate, loan.nextPaymentUntilDate);
    }
    
    
    //@doc nft purchase handler
    //      @req: nft marked for selling
    //      @req: min selling price is met 
    //      @action: loan+interest remains in contract, rest transferred to orig owner 
    function onNftPurchasedOnMarketplace(address contractAddr_, uint tokenId_, 
                uint actualSellingPriceInWei_) payable external onlyIfActive {
        require(contractAddr_ != address(0), "Bad contract address");
        bytes32 key = getNFTKey(contractAddr_, tokenId_);
        
        ActualLoan storage loan = getActualLoan(key, contractAddr_, tokenId_);
        
        require(loan.terms.monthlyInterestMEth > 0, "No active loan");
        
        require(loan.sellingPriceMEth > 0, "Token is not marked for sale");
        
        uint minSellingPriceInWei = milliEtherToWei(loan.sellingPriceMEth); 
        
        require(actualSellingPriceInWei_ >= minSellingPriceInWei, "Insufficient selling price");
        require(msg.value >= actualSellingPriceInWei_, "Transaction does not contain necessary funds");
        
        //MonthlyPayment storage pendingPayment_ = loan.pendingPayment;

        uint contractsCutMEth = loan.terms.loanSumMEth + loan.terms.monthlyInterestMEth; //@gilad maybe  partial interest?
        uint contractsCutInWei = milliEtherToWei(contractsCutMEth);
        uint ownersCutInWei = actualSellingPriceInWei_ - contractsCutInWei;

        if (ownersCutInWei > 0) {
            (bool ownerWasPaid, ) = loan.origOwner.call{value: ownersCutInWei}("");
            require(ownerWasPaid, "Failed to pay NFT owner");
        }
        
        uint refundSumInWei = msg.value - actualSellingPriceInWei_;
        //  return refundSum to msg.sender;
        if (refundSumInWei > 0) {
            (bool wasRefunded, ) = msg.sender.call{value: refundSumInWei}("");
            require(wasRefunded, "Failed to refund sender");
        }
        
        delete actualLoansMap[key];
        
        emit NftPurchasedOnMarketplace(contractAddr_, tokenId_ , loan.origOwner, actualSellingPriceInWei_, ownersCutInWei);
    }
 
    
    //@doc update selling price of an NFT while in loan period
    //      @req: can only be dome by orig nft owner
    //      @req: NFT must be marked for selling (undoing selling order may be overly risky)
    function updateNftSellingPrice(address contractAddr_, uint tokenId_, uint newSellingPriceMEth_) external onlyIfActive {
        require(contractAddr_ != address(0), "Bad NFT contract address");
        bytes32 key = getNFTKey(contractAddr_, tokenId_);
        
        require(newSellingPriceMEth_ > 0, "Selling price not set");

        ActualLoan storage loan = getActualLoan(key, contractAddr_, tokenId_);

        require(loan.terms.tokenId != 0, "A loan for this NFT does not exists");
        require(loan.sellingPriceMEth > 0, "NFT is not marked for selling");
        
        require(msg.sender == loan.origOwner, "Only the orig NFT owner may allow NFT selling"); 
        
        //bool ownerOrApproved_ = isOwnerOrApproved(msg.sender, contractAddr_, tokenId_); -- will not work, NFT oner is now this contract
        //require(ownerOrApproved_, "Only the orig NFT owner or an approved operator may allow NFT selling"); 

        loan.sellingPriceMEth = uint32(newSellingPriceMEth_);

        emit LoanSellingStatusChanged(contractAddr_,
                            tokenId_,
                            loan.origOwner,
                             newSellingPriceMEth_);
    }
    
    function getNFTKey(address contractAddr_, uint tokenId_) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(contractAddr_, tokenId_));
    }

    /*
    function loanRequestorIsOwnerOrApproved(address loanRequestor_, address contractAddr_, uint tokenId_) view external managerOnly returns(bool) {
        // Allow limiting loan offers by the platform to oners or approvers
        return isOwnerOrApproved(loanRequestor_, contractAddr_, tokenId_);
    }*/
    
    function senderIsOwnerOrApproved(address contractAddr_, uint tokenId_) view external returns(bool) {
        // allow msg sender to invoke the the contract to validate oner or approver
        return isOwnerOrApproved(msg.sender, contractAddr_, tokenId_);
    }

    function isOwnerOrApproved(address loanRequestor_, address contractAddr_, uint tokenId_) view private onlyIfAcceptingNewLoans onlyIfActive returns(bool) {
        // Allow limiting loan offers by the platform to oners or approvers
        IERC721 nftContract = IERC721(contractAddr_);
        address nftOwner = nftContract.ownerOf(tokenId_);
        return (nftOwner == loanRequestor_) ||
               (nftContract.getApproved(tokenId_) == loanRequestor_) ||
               (nftContract.isApprovedForAll(nftOwner, loanRequestor_));
    }
    
    
    //@doc size reducing methods: delete overdue offers
    function deleteLoanOffer(address contractAddr_, uint tokenId_) external managerOnly onlyIfActive {
        require(contractAddr_ != address(0), "Bad NFT contract address");
        bytes32 key = getNFTKey(contractAddr_, tokenId_);
        require(loanOffersMap[key].loanSumMEth > 0, "Bad loan sum");
        delete loanOffersMap[key];
        
        emit LoanOfferCancelled(contractAddr_, tokenId_);
    }
    

    function deleteMultipleLoanOffers(address[] calldata contractAddrArr, uint[] calldata tokenIdArr) 
                    external managerOnly onlyIfActive {
        require(contractAddrArr.length == tokenIdArr.length, "Arrays must be of the same length");
        for (uint i = 0; i < contractAddrArr.length; i++) {
            bytes32 key = getNFTKey(contractAddrArr[i], tokenIdArr[i]);
            delete loanOffersMap[key];
            emit LoanOfferCancelled(contractAddrArr[i], tokenIdArr[i]);
        }    
    }
    
    
    //@doc OnlyNftOwnerCanApply management methods 
    function setOnlyNftOwnerCanApply(bool onlyOwner) external ownerOnly {
        onlyNftOwnerCanApply = onlyOwner;
    }

    function getOnlyNftOwnerCanApply() external view managerOnly returns(bool) {
        return onlyNftOwnerCanApply;
    } 
    
    
    //@doc contract state management methods 
    function setContractIsActive(bool active) external ownerOnly {
        isActive = active;
        emit IsActiveSet(isActive);
    }
    
    function setAcceptingNewLoans(bool acceptingNewLoans_) external ownerOnly {
        acceptNewLoans = acceptingNewLoans_;
        emit AcceptingNewLoansChanged(acceptNewLoans);
    }
    
    function setMaxLoanMEth(uint newMaxLoanMEth) external ownerOnly {
        maxLoanMEth = newMaxLoanMEth;
        emit MaxLoanSet(maxLoanMEth);
    }

    function setWriteToAnonArray(bool writeAnon) external ownerOnly {
        writeToAnonArray = writeAnon;
        emit WriteToAnonArraySet(writeToAnonArray);
    }

    function getWriteToAnonArray() external view managerOnly returns(bool) {
        return writeToAnonArray;
    }
    
    function setEmitAnonEvent(bool emitAnon) external ownerOnly {
        emitAnonEvent = emitAnon;
        emit EmitAnonEventSet(emitAnonEvent);
    }

    function getEmitAnonEvent() external view managerOnly returns(bool) {
        return emitAnonEvent;
    }
    

    //@doc role management methods 
    function setOwner(address newOwner) public ownerOnly {
        require(newOwner != address(0), "Bad owner address");
        address oldOwner = owner;
        owner = newOwner; 
        emit OwnerSet(oldOwner, owner);
    }
    
    function setManager(address newManager) external ownerOnly {
        require(newManager != address(0), "Bad new manager address");
        address oldManager = manager;
        manager = newManager; 
        emit ManagerSet(oldManager, manager);
    }
    
    function setOwnerToMsgSender() external ownerOnly {
        setOwner(msg.sender);
    }
    
    //@doc kill contract 
    //      @req: contract marked inActive
    //      @req: contract's balance is zero 
    function removeOwnerAndKillContract() external ownerOnly {
        require(isActive == false, "Cannot kill an active contract");
        require(address(this).balance == 0, "Contract balance must be zero");
        address oldOwner = owner;
        owner = address(0); 
        manager = address(0); 
        emit OwnerSet(oldOwner, owner);
    }

    //@doc mark contract as a valid ERC721 receiver 
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return ERC721_RECEIVED;   
    }
    

    // @doc fallback funcs use case:        
    //  - fallback: contract received ether and no data e.g. via send() or transfer()
    //  - receive:  contract received data but no function matched the function called

    receive() external payable onlyIfActive {
        anonPayment();
    }
    
    fallback() external payable onlyIfActive {
        anonPayment();
    }
         
    function anonPayment() private { 
        if (msg.value > 0) {
            if (writeToAnonArray) {
                anonPayments.push(AnonPayment(msg.value, msg.sender, block.timestamp));
            }
            if (emitAnonEvent) {
                emit AnonimousPaymentReceived(msg.value, msg.sender, block.timestamp);
            }
        }    
    }
    
    //@doc anon payments management methods
    function getNumAnonPayments() external view managerOnly returns(uint) { 
        return anonPayments.length;
    }
    
    function getSingleAnonPayment(uint ind_) external view managerOnly returns(uint, address, uint) { 
        AnonPayment storage curr = anonPayments[ind_];
        return (curr.sumInWei, curr.from, curr.date);
    }
    
    function deleteSingleAnonPayment(uint ind_) external managerOnly { 
        delete anonPayments[ind_];
    }
    
    function deleteAllAnonPayments() external ownerOnly { 
        delete anonPayments;
        assert(anonPayments.length == 0);
    }
    
    //@doc state getters (manager role)
    function getLoanOfferDetails(address contractAddr_, uint tokenId_) 
                external view managerOnly returns(uint,uint,uint,uint) {
        bytes32 key = getNFTKey(contractAddr_, tokenId_); 

        LoanOffer storage offer = getLoanOffer(key, contractAddr_, tokenId_);

        return (offer.loanSumMEth, offer.monthlyInterestMEth, offer.loanPeriodInMonths, offer.offerIsValidUntilDate);
    }

    function getActualLoanDetails(address contractAddr_, uint tokenId_) 
                external view managerOnly returns(uint,address,uint,uint,uint,uint) {
        bytes32 key = getNFTKey(contractAddr_, tokenId_);
        
        ActualLoan storage loan = getActualLoan(key, contractAddr_, tokenId_);

        return (loan.nextPaymentUntilDate, loan.origOwner, loan.sellingPriceMEth, 
                loan.terms.loanSumMEth, loan.terms.monthlyInterestMEth, loan.terms.loanPeriodInMonths);
    }
        

    function getLoanOffer(bytes32 key, address contractAddr_, uint tokenId_) private view returns(LoanOffer storage) {
        LoanOffer storage offer = loanOffersMap[key];
        assert(offer.contractAddr == contractAddr_);
        assert(offer.tokenId == tokenId_);
        return offer;
    }

    function getActualLoan(bytes32 key, address contractAddr_, uint tokenId_) private view returns(ActualLoan storage) {
        ActualLoan storage loan = actualLoansMap[key];
        assert(loan.terms.contractAddr == contractAddr_);
        assert(loan.terms.tokenId == tokenId_);
        return loan;
    }
    
    function milliEtherToWei(uint valueInMEth_) internal pure returns(uint) { 
        uint valInWei = valueInMEth_ * 1 ether / 1000;
        assert(valInWei == valueInMEth_ * 1e15);
        return valInWei;
    }

}

