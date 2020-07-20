pragma solidity ^0.5.12;
pragma experimental ABIEncoderV2;
///@title 币期权
///@author https://coinoptions.xmsxsp.com/
///@dev https://coinoptions.xmsxsp.com/

contract CoinOptionsContract  {
    using SafeMath for uint256;
    uint256 constant AMT = 1000000000000 wei; 
    uint256 constant DOWNTIME_AMT =1000000000000 wei; 
    uint256 constant SUPER_NODE_AMT = 1000000000000 wei;                            
    uint256 constant ONE_DAY = 1 days;
    uint256 constant private ROUND_MAX = 2 minutes;// 一轮最多时间
    uint256 constant private ROUND_PER_TIME = 100 seconds;//一次增加    

    struct Customer {
        address customerAddr;//获取钱包的地址，每个地址对应一个账号
        address recommendAddr;//推荐人地址，如果没有，就用公司地址
        uint256 totalInput;//累计投入金额
        uint256 frozenAmount;//冻结金额
        uint256 staticBonus;//静态奖金
        uint256 dynamicBonus;//动态奖金
        uint256 bw;//可参与游戏金额
        uint256 balance;//可提币金额-暂时无用
        uint256 createTime;//加入时间
        uint8 status;//0=未投资；1=有投资；-暂无用
        uint8 membershipLevel;//会员级别 //0=普通会员 1=节点会员-暂无用
        uint256 level;//等于父层+1
        uint8 isValid;//用户是否投资过
        uint256 burnAmount;//烧伤奖金
        uint256 nodeBonus;//节点奖金
        uint256 reserveFund;//储备金
    }
  
    struct InvestOrder {
        address customerAddr;//投资人
        address recommendAddr;//推荐人
        uint256 amount;//金额
        uint256 createTime;//加入时间
        uint256 peroid;//投资周期-天
        uint8 status;//0=初始 1=到期 2=终止
        uint256 endTime;//结束时间
        uint256 interestRate;//每天利率，在计算的时候需要/(30*100)  
        uint256 seq;//序号
        uint256 stopTime;//终止时间
        uint256 interest;//已经获取的利息
        uint256 nodeIdx;//在节点数组中的index
        uint256 roundIdx;//当前参与的轮数
        uint256 originPeroid;//最初投资周期-天
       
    }
    
    struct Round {
        address lasted;// 最后一个会员      
        uint256 end; //结束时间
        bool ended; //是否结束      
        uint256 start; //开始时间
        uint256 qty;// 总共多少数量
        bool isStart;//是否已经启动
    }
      struct Winner {
        uint256 roundNum;//第几轮中奖
        address account;//中奖账号 
        uint256 qty; //中奖数量
        uint256 createTime; //中奖时间
    }
     struct GuessOrder {
        address customerAddr;//投资人
        uint256 amount;//金额
        uint8 direction;//0=涨 1=跌
        uint256 createTime;//时间
        uint256 bonus;//奖金
    }
    event Invest(address indexed  customerAddr,address recommendAddr,uint256 amount,uint256 peroid,uint8 status, uint256 interestRate, uint256 createTime, uint256 endTime,uint256 num,uint256 roundIdx);
    event RenewContract(address indexed customerAddr,uint256 num,uint256 createTime, uint256 endTime,uint256 peroid,uint256 interestRate);
    event Abolishment(address indexed customerAddr,uint256 num);
    event TransferToGame(address indexed customerAddr,uint256 num);
    event RoundEnd(uint256 roundNum,address lasted,uint amount,uint256 startTime,uint256 endTime);
    event Compute(uint256 kind,uint256 num,uint amount,uint opTime);
    event Guess(address customerAddr,uint amount, uint8 direction,uint createTime);
    
    address payable private recieveAccount; 
    address payable private contractAccount;
    uint256 private superNodeCount = 0;
    mapping(address => Customer) private customerMapping;
    mapping(address => address[]) private teamUserMapping;//推荐数
    mapping(address => InvestOrder[]) private  investOrderMapping; //会员的投资订单
    InvestOrder[] private investOrders;//所有订单
    InvestOrder[] private superNodeOrders; //节点订单
 
    uint256 private userCount = 0;//用户量
    uint256 private staticLastCheck;//最近静态结算时间
    uint256 private nodeBonusLastCheck;//最近节点分红结算时间   
    uint256 private reserveFundPool=0;//储备金
    uint256 private nodeBonusPool=0;//节点奖池
    uint256 private totalNodeBonus=0;//累计发放节点奖
    uint256 private totalAmount=0;//累计投资
    uint256 private totalBonus=0;//累计发放奖金
    
     uint256 private roundNum=0;//总共多少轮 
     mapping (uint256 =>Round) private rounds; 
     Winner[] private winners; //每一轮的赢家 
     uint256 private pool=0;//当前倒计时奖金池
     
     GuessOrder[] private guessOrders;//所有竞猜游戏订单
     mapping(address => GuessOrder[]) private  guessOrderMapping; //会员的竞猜游戏订单
     
    constructor(address payable _recieveAccount,address payable _contractAccount) public{
        recieveAccount = _recieveAccount;
        contractAccount = _contractAccount;
        Customer memory u = Customer(recieveAccount, address(0), 0, 0, 0, 0, 0, 0, now, 0, 0, 0, 1,0,0,0);
        customerMapping[recieveAccount] = u;
        staticLastCheck=now;
        nodeBonusLastCheck=now;
        Round memory r=Round(address(0),0,false,0,0,false);
        rounds[roundNum]=r;       
    }
    function invest(uint256 _peroid, address _recommendAddr) public payable{
      // require(msg.value >= AMT , "Investment amount must be greater than or equal to 1 eth!");
     //  require(msg.value == (msg.value/1000000000000000000).mul(1000000000000000000), "Multiple of investment amount must be 1 eth!");
       require(_peroid == 30 || _peroid == 60 || _peroid == 90 || _peroid == 180, "days is not valid");
        address userAddr = msg.sender;
        uint256 inputAmount = msg.value;
        uint256 peroid=_peroid;
        address recommendAddr=_recommendAddr;
        Customer memory user = customerMapping[userAddr];
        if (user.isValid == 1) {
            user.totalInput =user.totalInput.add(inputAmount);
            user.frozenAmount =user.frozenAmount.add(inputAmount);
            user.status = 1;
            customerMapping[userAddr] = user;
            recommendAddr=user.recommendAddr;
        } else {
            address realRec = recommendAddr;
            if (customerMapping[recommendAddr].isValid == 0 || recommendAddr == address(0x0000000000000000000000000000000000000000)) {
                realRec = recieveAccount;
                recommendAddr=realRec;
            }
            uint256 level=1;
            Customer memory parent = customerMapping[realRec];
            if(parent.isValid == 1){
                level=level.add(parent.level);
            }
          
            Customer memory u = Customer(userAddr, realRec, inputAmount, inputAmount, 0, 0, 0, 0, now, 0, 0, level, 1,0,0,0);
            userCount = userCount.add(1);
            customerMapping[userAddr] = u;
            address[] storage upPlayers = teamUserMapping[realRec];
            upPlayers.push(userAddr);
            teamUserMapping[realRec] = upPlayers;
        }
        //获取利率
        uint256 interestRate=getInterestRate(peroid);
        //订单
        uint256 num=  investOrderMapping[userAddr].length;
        uint256 endTime=ONE_DAY * peroid + now;
        InvestOrder memory order = InvestOrder(userAddr,recommendAddr, inputAmount, now, peroid, 0, endTime,interestRate,num,0,0,0,0,peroid);
         //节点
        if(inputAmount>=SUPER_NODE_AMT ){
            superNodeOrders.push(order);
            order.nodeIdx=superNodeOrders.length;
            superNodeCount=superNodeCount.add(1);
         }
          investOrders.push(order);
          investOrderMapping[userAddr].push(order);
         //累计投资
         totalAmount=totalAmount.add(inputAmount);
        //倒计时      
        addToRound(userAddr,inputAmount);       
         //冻结金额
        recieveAccount.transfer(inputAmount); 
        //事件处理
        emit Invest(userAddr,recommendAddr, inputAmount, peroid, 1,interestRate,now,endTime,num,roundNum);  
    }
    function addToRound(address userAddr,uint256 inputAmount) private{
        //倒计时奖金池
         pool=pool.add(inputAmount.mul(5).div(100)); 
         Round memory round=rounds[roundNum];
         round.lasted= userAddr;
         round.qty=round.qty.add(inputAmount);    
         if(round.start>0){
             round.end=round.end+ROUND_PER_TIME;
             if(round.end -now > ROUND_MAX){
                round.end=now+ROUND_MAX;
             }
         }else  if(pool >=DOWNTIME_AMT){
             round.start=now;
             round.end=round.start+ROUND_MAX;
             round.isStart=true;
         }
         rounds[roundNum]= round;  
        
    }
    
    //续约
     function renewContract(address _addr,uint256 _num) public{
          require(msg.sender == _addr,"address is error!");
          InvestOrder[] storage myInvestOrders=investOrderMapping[_addr];
          uint256 len=myInvestOrders.length;
          require(_num <len && _num>=0,"order  num is error!");
          InvestOrder memory order=myInvestOrders[_num];
          //require(order.status == 0  ," order status  is error!");
         // require(now >( order.createTime + 1 days) ,"Order time is wrong!");
         // require(now > order.endTime  ,"Order time is wrong!");
                               
          uint256 newPeroid=order.peroid.add(order.originPeroid);              
          uint256 interestRate=getInterestRate(newPeroid);
          order.interestRate=interestRate;
          order.interest=0;
          order.peroid=newPeroid;        
          order.endTime=ONE_DAY * order.peroid + order.createTime;
          myInvestOrders[_num]=order;
          investOrderMapping[_addr]=myInvestOrders;
          emit RenewContract(_addr,_num,order.createTime, order.endTime, newPeroid,order.interestRate);         
     }
     //违约
   function abolishment(address _addr,uint256 _num) public{
        require(msg.sender == _addr,"address is error!");
        InvestOrder[] storage myInvestOrders=investOrderMapping[_addr];
        uint256 len=myInvestOrders.length;
        require(_num <len && _num>=0,"order  num is error!");
        InvestOrder memory order=myInvestOrders[_num];
        require(order.status == 0  ," order status  is error!");  
   //     require(now >( order.createTime + 1 days) ,"Order time is wrong!");
        uint256  amount=order.amount;
         //扣除罚款
         if(now < order.endTime){
         	uint256  fine=amount.mul(5).div(100);
         	amount=amount.sub(fine);
         }
         
        uint256 interest=order.interest;
        uint256 restAmt=0;
        if(interest>=amount){
            restAmt=0;
        }else{
           // restAmt=amount.sub(interest);
           restAmt=amount;
        }       
         
        //返回给用户
        Customer memory customer = customerMapping[_addr];
        customer.bw=customer.bw.add(restAmt);
        uint256 frozenAmount= customer.frozenAmount.sub(order.amount);
        if(frozenAmount<0){
            frozenAmount=0;
        }
        customer.frozenAmount=frozenAmount;
        customerMapping[_addr] = customer;
        
        //修改订单
        order.status=2;
        order.stopTime=now;
        myInvestOrders[_num]=order;
        investOrderMapping[_addr]=myInvestOrders;
        //修改节点订单
         if(order.amount>=SUPER_NODE_AMT ){
            superNodeOrders[order.nodeIdx]=order;
            superNodeCount=superNodeCount.sub(1);
         }
        //修改累计投资金额        
        totalAmount=totalAmount.sub(order.amount);   
        
        emit Abolishment(_addr,_num);
        
   }
   //买涨买跌
    function buyUpOrDown(address _addr,uint256 _num,uint8 direction ) public{
        require(msg.sender == _addr,"address is error!");
        Customer memory user = customerMapping[_addr];
        require(user.bw >= _num,"bw  is less than num!");
        require(_num > 0,"_num  is less than 0!");
        user.bw=user.bw.sub(_num);
        customerMapping[_addr]=user;        
        GuessOrder memory guessOrder=GuessOrder(_addr,_num,direction,now,0);
        guessOrders.push(guessOrder);
        
        GuessOrder[] storage myGuessOrders= guessOrderMapping[_addr];
        myGuessOrders.push(guessOrder);
        guessOrderMapping[_addr]=myGuessOrders;
        emit Guess(_addr,_num,direction,now);
       
   }   
   
   
    //计算静态奖金
    function computeStaticBonus() public {
         require(msg.sender ==contractAccount,"address is error!");
         //require(isCanStaticBonus(),"check date is error!");         
         uint len=investOrders.length;
         uint totalAmt=0;
         uint num=0;        
         for(uint i=0;i<len;i++){
             InvestOrder memory investOrder=investOrders[i];
             if(investOrder.status!=0 ){
                continue; 
             }
            /* if(investOrder.createTime +1 days > now){
                 continue;
             } 
             */                         
            uint  interest=investOrder.amount.mul(investOrder.interestRate).div(3000);
             //到储备金
             uint tmpInterest=interest.div(10);
             reserveFundPool=reserveFundPool.add(tmpInterest);
             nodeBonusPool=nodeBonusPool.add(tmpInterest);
             uint realInterest=interest.sub(tmpInterest);
             investOrder.interest=investOrder.interest.add(realInterest);
             investOrders[i]=investOrder;
             //修改会员静态奖金
             Customer memory user = customerMapping[investOrder.customerAddr];
             user.staticBonus= user.staticBonus.add(realInterest);
             user.bw=user.bw.add(realInterest);
             customerMapping[investOrder.customerAddr]=user;             
             //累计发放奖金
             totalBonus=totalBonus.add(realInterest);
             totalAmt=totalAmt.add(realInterest);
             num=num.add(1);
             
             //计算上级动态奖    
             executeRecommender(user.recommendAddr, 1, investOrder.amount,investOrder.interestRate);
              
         }
         //修改静态奖金结算时间
          updateStaticLastCheck();
         
          emit Compute(1,num,totalAmt,now);
        
    }
    //计算节点奖
    function computeNodeBonusPool() public{
         require(msg.sender ==contractAccount,"address is error!");
         require(nodeBonusPool>0,"Node bonus  is less 0!");
        // require(isCanNodeBonus(),"check date is error!"); 
         //找到有效的节点订单  
         uint tmpNodeBonusPool=nodeBonusPool; 
         uint totalAmt=0;
         uint len=superNodeOrders.length;
         for(uint i=0;i<len;i++){
             if(superNodeOrders[i].status==0){
                 totalAmt=totalAmt.add(superNodeOrders[i].amount);
             }
         }
         if(totalAmt>0){
            uint rate=nodeBonusPool.mul(1000000).div(totalAmt);
            for(uint i=0;i<len;i++){
                 if(superNodeOrders[i].status==0){
                   uint nodeBonus= superNodeOrders[i].amount.mul(rate);
                   Customer memory user = customerMapping[superNodeOrders[i].customerAddr];
                   user.nodeBonus= user.nodeBonus.add(nodeBonus.div(1000000));
                   user.bw=user.bw.add(nodeBonus.div(1000000));
                   customerMapping[superNodeOrders[i].customerAddr]=user;
                 }
             }
             totalNodeBonus=totalNodeBonus.add(nodeBonusPool);  
              //累计发放奖金
             totalBonus=totalBonus.add(nodeBonusPool);
             //节点奖金清0
             nodeBonusPool=0;
         }
         
           emit Compute(2,len,tmpNodeBonusPool,now);
    }
    
    //分配储备金
     function computeReserveFund() public{
         require(msg.sender ==contractAccount,"address is error!");
         require(reserveFundPool > 0,"reserve bonus  is less 0!");
         require(totalAmount.sub(totalBonus)<1,"total Bonus bonus  is less total input!");
         //最后100的总金额
         uint256 j=0;
         //找到有效的节点订单   
         uint totalAmt=0;//最后100名的累计投资
         uint len=investOrders.length;
         for(uint i=len-1;i>=0;i--){
             if(investOrders[i].status==0){
                 totalAmt=totalAmt.add(investOrders[i].amount);
                 if(j>100){
                     break;
                 }
                 j=j+1;
             }
         }
         j=0;
         if(totalAmt>0){
            uint rate=reserveFundPool.div(totalAmt);
            for(uint i=len-1;i>=0;i--){
                 if(investOrders[i].status==0){
                   uint reserveFund= investOrders[i].amount.mul(rate);
                   Customer memory user = customerMapping[investOrders[i].customerAddr];
                   user.reserveFund= user.reserveFund.add(reserveFund);
                   user.bw=user.bw.add(reserveFund);
                   customerMapping[investOrders[i].customerAddr]=user;
                    if(j>100){
                        break;
                    }
                     j=j+1;
                 }
             }          
             // 储备金清0
             reserveFundPool=0;
             totalAmount=0;
             totalBonus=0;
             
         }
           emit Compute(3,j,totalAmt,now);
    }
    
    // 将上次静态奖金结算时间设置为 ‘现在’
    function updateStaticLastCheck() private {
       staticLastCheck = now;
    }
    //判断上次结算时间与当前是否相差1天，如果是 返回 'true'，否则返回 'false'   
	function isCanStaticBonus() private  view returns (bool) {
	  return (now >= (staticLastCheck + 1 days));
	}
	
	  // 将上次节点分红结算时间设置为 ‘现在’
    function updateNodeBonusLastCheck() private {
       nodeBonusLastCheck = now;
    }
    //判断上次节点分红与当前是否相差1天，如果是 返回 'true'，否则返回 'false'   
	function isCanNodeBonus() private  view returns (bool) {
	  return (now >= (nodeBonusLastCheck + 1 days));
	}
	
    //递归计算推荐人的奖励
    function executeRecommender(address userAddress, uint256 times, uint256 amount,uint256 interestRate) private returns (address, uint256, uint256){
        address tmpAddress=userAddress;
        uint256 tmpAmt=amount;
        uint256 _interestRate=interestRate;
        Customer memory user = customerMapping[userAddress];
        if (user.isValid == 1 && times <= 20) {
            address reAddr = user.recommendAddr;           
            //当前直推的人数，推荐几个，就拿几代
            uint256 len = getValidSubordinateQty(userAddress);
            if (len >= times) {
                //是否有烧伤金额
                if(user.frozenAmount<amount){
                    tmpAmt=user.frozenAmount;
                    customerMapping[tmpAddress].burnAmount = customerMapping[tmpAddress].burnAmount.add(amount).sub(tmpAmt);
                 }
                uint256 rate = getEraRate(times);
                uint256 bonus = tmpAmt.mul(_interestRate).div(3000).mul(rate).div(100);
                uint256 tmpBonus=bonus.div(10);
                reserveFundPool=reserveFundPool.add(tmpBonus);
                uint256 realBonus=bonus.sub(tmpBonus);
                
                customerMapping[tmpAddress].dynamicBonus = customerMapping[tmpAddress].dynamicBonus.add(realBonus);
                customerMapping[tmpAddress].bw = customerMapping[tmpAddress].bw.add(realBonus);
                
                 //累计发放奖金
                totalBonus=totalBonus.add(realBonus);
            }
            return executeRecommender(reAddr, times + 1, amount,interestRate);
        }
        return (address(0), 0, 0);
    }
    
    //获取代数奖，需要除以100
    function getEraRate(uint256 times) private pure returns (uint256){
        if (times == 1) {
            return 50;
        }
        if (times == 2) {
            return 40;
        }
        if (times == 3) {
            return 30;
        }
        if (times == 4) {
            return 20;
        }
        if (times >= 5 && times <= 10) {
            return 10;
        }
        if (times >= 11 && times <= 20) {
            return 5;
        }
        return 0;
    }
    
    //每月利率，要除以100*30
    function getInterestRate(uint256 times) private pure returns (uint256){
        uint256 rate=10;
        if (times < 60) {//10%
            rate= 10;
        }else if (times>=60 && times < 90) {//12%
            rate= 12;
        }else  if (times >=90 && times < 180) {//14%
            rate= 14;
        }else  if (times >= 180) {//16%
            rate= 16;
        }
        return rate;
    }

     //获取会员信息
     function getCustomerByAddr(address _address) public view returns (
         address, address,
         uint256, uint256, uint256, uint256, uint256, uint256, uint256,
       // uint8, uint8, uint256, uint8,
        uint256, uint256,uint256
     ){
         Customer memory customer = customerMapping[_address];
        return (customer.customerAddr,  customer.recommendAddr, 
             customer.totalInput, customer.frozenAmount, customer.staticBonus, customer.dynamicBonus, customer.bw, customer.balance, customer.createTime,
          //  customer.status, customer.membershipLevel, customer.level, customer.isValid, 
            customer.burnAmount, customer.nodeBonus,customer.reserveFund
        );
     }
     
    
     
   //提币到游戏区
    function transferToGame(address addr,uint256 num) public {
        require(msg.sender == addr || msg.sender ==contractAccount,"address is error!");
        require(num >= 0.01 ether ,"num is less than 0.01 Eth!");
        address curAddr = msg.sender;
        Customer memory user = customerMapping[curAddr];
        uint bw=user.bw;       
        require(bw >= num, "balance not enough");    
        user.bw = bw.sub(num);
        customerMapping[curAddr] = user;
        emit TransferToGame(curAddr,num);
    }
    
      function compareStr(string memory _str, string memory str) internal pure returns(bool) {
        if (keccak256(abi.encodePacked(_str)) == keccak256(abi.encodePacked(str))) {
            return true;
        }
        return false;
    }
     function getValidSubordinateQty(address _address) private returns(uint256){
    	uint256 m=0;
    	address[]  memory   addresses= teamUserMapping[_address];
    	uint len=addresses.length;
    	for(uint i=0;i<len;i++){
    	  address addr=addresses[i];
    	  Customer memory user = customerMapping[addr];
    	  if(user.frozenAmount>=AMT){
    	    m=m+1;
    	  }
    	}
    	return m;
    } 
    ////////////////////////////////////倒计时游戏start///////////////////////////////////////////////////////
    function endRound() public returns(uint256,address,uint256 ){
          require(msg.sender ==contractAccount,"address is error!");
          require(pool >=DOWNTIME_AMT,"pool amount is less than 10!");         
          uint256 _roundNum = roundNum;
          Round memory round=rounds[_roundNum];
          require(round.end<=now,"The end time hasn't arrived yet !");
       
          address lasted=round.lasted;
          Customer memory user =customerMapping[lasted];         
          user.bw =user.bw.add(pool);
          customerMapping[lasted] = user;
       
          round.ended=true;   
          rounds[_roundNum]=round;
            
          roundNum=roundNum+1;
          
          Round memory r=Round(address(0),0,false,0,0,false);
          rounds[roundNum]=r;
          
          Winner memory w=Winner(_roundNum,lasted,pool,now);
          winners.push(w);
          
          pool=0;
            
          emit RoundEnd(w.roundNum,w.account,w.qty,round.start,round.end); 
          
          return( w.roundNum,w.account,w.qty);  
    }
    
    function getCurrRound() public view returns(address lasted,uint256 end,bool ended,uint256 start,uint256 qty,bool isStart){
           Round memory round=rounds[roundNum];
           if(roundNum==0){
               return (round.lasted,round.end,round.ended,round.start,round.qty,round.isStart);
           }else{
               uint256 _qty=round.qty;
	           if(_qty==0){
	               uint256 tmpRoundNum=roundNum-1;
	               Round memory tmpRound=rounds[tmpRoundNum];
	                return (tmpRound.lasted,tmpRound.end,tmpRound.ended,tmpRound.start,tmpRound.qty,tmpRound.isStart);
	           }else{
	               return (round.lasted,round.end,round.ended,round.start,round.qty,round.isStart);
	           }
           }
    }
    ////////////////////////////////////倒计时游戏end///////////////////////////////////////////////////////
    
      ////////////////////////////////////获取信息start///////////////////////////////////////////////////////
    
     //获取信息大纲
     function getSummary() public view returns(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256){
         return (superNodeCount,userCount,reserveFundPool,nodeBonusPool,totalNodeBonus,totalAmount,totalBonus,pool);
     }
 
    //获取用户的所有订单
    function findInvestOrders(address addr) public view returns(InvestOrder[]  memory orders){
       InvestOrder[]  memory   myOrders= investOrderMapping[addr];
       return myOrders;
    }
	//获取所有投资订单
	 function findAllInvestOrders() public view returns(InvestOrder[]  memory orders){      
       return  investOrders;
    }
      //获取直推用户
    function findSubordinates(address _address) public view returns(address[]  memory subordinates){
       address[]  memory   addresses= teamUserMapping[_address];
       return addresses;
    }
    //获取所有中奖的
     function findAllWinners() public view returns(Winner[] memory allwinners){  
       return winners;
    } 
      //获取用户的所有游戏订单
    function findGuessOrders(address addr) public view returns(GuessOrder[]  memory orders){
       GuessOrder[]  memory   myGameOrders= guessOrderMapping[addr];
       return myGameOrders;
    }
   //获取所有游戏订单
	 function findAllGuessOrders() public view returns(GuessOrder[]  memory orders){      
       return  guessOrders;
    }
     ////////////////////////////////////获取信息end///////////////////////////////////////////////////////
}
/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
    /**
     * @dev Multiplies two numbers, throws on overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }
    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a / b;
        return c;
    }
    /**
    * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }
    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }

}

