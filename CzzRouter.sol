
pragma solidity =0.6.6;

import './IERC20.sol';
import './IWETH.sol';
import './ISwapFactory.sol';
import './IUniswapV2Router02.sol';

abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface ICzzSwap is IERC20 {
    function mint(address _to, uint256 _amount) external;
    function burn(address _account, uint256 _amount) external;
    function transferOwnership(address newOwner) external;
}

contract CzzRouter is Ownable {
    
    address czzToken;
    uint private _ntype;

    mapping (address => uint8) private managers;
    mapping (address => uint8) private routerAddrs;

    event MintToken(
        address indexed to,
        uint256 amount,
        uint256 mid,
        uint256 amountIn
    );
    event BurnToken(
        address     indexed to,
        uint256     amount,
        uint256     ntype,
        address[]   toPath,
        bytes       Extra
    );
    event SwapToken(
        address indexed to,
        uint256 inAmount,
        uint256 outAmount,
        string   flag
    );
    event TransferToken(
        address  indexed to,
        uint256  amount
    );

    modifier isManager {
        require(
            msg.sender == owner() || managers[msg.sender] == 1);
        _;
    }

    constructor(address _token) public {
        czzToken = _token;
        minSignatures = MIN_SIGNATURES;
    }
    
    receive() external payable {}
    
    function addManager(address manager) public onlyOwner{
        managers[manager] = 1;
    }
    
    function removeManager(address manager) public onlyOwner{
        managers[manager] = 0;
    }

    function addRouterAddr(address routerAddr) public isManager{
        routerAddrs[routerAddr] = 1;
    }
    
    function removeRouterAddr(address routerAddr) public isManager{
        routerAddrs[routerAddr] = 0;
    }

    function HasRegistedRouteraddress(address routerAddr) public view isManager returns(uint8 ){
        return routerAddrs[routerAddr];
    }
   
    function approve(address token, address spender, uint256 _amount) public virtual returns (bool) {
        require(address(token) != address(0), "approve token is the zero address");
        require(address(spender) != address(0), "approve spender is the zero address");
        require(_amount != 0, "approve _amount is the zero ");
        require(routerAddrs[spender] == 1, "spender is not router address ");        
        IERC20(token).approve(spender,_amount);
        return true;
    }
    
    function _swapMint(
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address to,
        address routerAddr,
        uint deadline
        ) internal {
        uint256 _amount = IERC20(path[0]).allowance(address(this),routerAddr);
        if(_amount < amountIn) {
            approve(path[0], routerAddr,uint256(-1));
        }
        IUniswapV2Router02(routerAddr).swapExactTokensForTokens(amountIn, amountOutMin,path,to,deadline);

    }

    function _swapBurn(
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address to,
        address routerAddr,
        uint deadline
        ) internal {
        uint256 _amount = IERC20(path[0]).allowance(address(this),routerAddr);
        if(_amount < amountIn) {
            approve(path[0], routerAddr,uint256(-1));
        }
        TransferHelper.safeTransferFrom(path[0], msg.sender, address(this), amountIn);
        IUniswapV2Router02(routerAddr).swapExactTokensForTokens(amountIn, amountOutMin,path,to,deadline);
    }

    function _swapEthBurn(
        uint amountInMin,
        address[] memory path,
        address to, 
        address routerAddr,
        uint deadline
        ) internal {
        uint256 _amount = IERC20(path[0]).allowance(address(this),routerAddr);
        if(_amount < msg.value) {
            approve(path[0], routerAddr,uint256(-1));
        }
        IWETH(path[0]).deposit{value: msg.value}();
        IUniswapV2Router02(routerAddr).swapExactTokensForTokens(msg.value,amountInMin,path,to,deadline);
    }
    
    function _swapEthMint(
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address to, 
        address routerAddr,
        uint deadline
        ) internal {
      
        uint256 _amount = IERC20(path[0]).allowance(address(this),routerAddr);
        if(_amount < amountIn) {
            approve(path[0], routerAddr,uint256(-1));
        }
        IUniswapV2Router02(routerAddr).swapExactTokensForETH(amountIn, amountOutMin,path,to,deadline);
    }
    
    function swap_burn_get_getReserves(address factory, address tokenA, address tokenB) public view isManager returns (uint reserveA, uint reserveB){
        require(address(0) != factory);
        return  ISwapFactory(factory).getReserves(tokenA, tokenB);
    }
    
    function swapGetAmount(uint amountIn, address[] memory path,address routerAddr) public view returns (uint[] memory amounts){
        require(address(0) != routerAddr); 
        return IUniswapV2Router02(routerAddr).getAmountsOut(amountIn,path);
    }
    
    function swapAndMintTokenWithPath(address _to, uint _amountIn, uint _amountInMin, uint256 mid, uint256 gas, address routerAddr, address[] memory userPath, uint deadline) payable public isManager {
        require(address(0) != _to);
        require(address(0) != routerAddr); 
        require(_amountIn > 0);
        require(_amountIn > gas, "ROUTER: transfer amount exceeds gas");
        require(userPath[0] == czzToken, "userPath 0 is not czz");

        ICzzSwap(czzToken).mint(address(this), _amountIn);    // mint to contract address   
        uint[] memory amounts = swapGetAmount(_amountIn, userPath, routerAddr);
        if(gas > 0){
            bool success = true;
            (success) = ICzzSwap(czzToken).transfer(msg.sender, gas); 
            require(success, 'swapAndMintTokenWithPath gas Transfer error');
        }
        _swapMint(_amountIn-gas, _amountInMin, userPath, _to, routerAddr, deadline);
        emit MintToken(_to, amounts[amounts.length - 1], mid, _amountIn);
    }
    
    function swapAndMintTokenForEthWithPath(address _to, uint _amountIn, uint _amountInMin, uint256 mid, uint256 gas, address routerAddr, address[] memory userPath, uint deadline) payable public isManager {
        require(address(0) != _to);
        require(address(0) != routerAddr); 
        require(_amountIn > 0);
        require(_amountIn > gas, "ROUTER: transfer amount exceeds gas");
        require(path[0] == czzToken, "path 0 is not czz");

        ICzzSwap(czzToken).mint(address(this), _amountIn);    // mint to contract address   
        uint[] memory amounts = swapGetAmount(_amountIn, path, routerAddr);
        if(gas > 0){
            bool success = true;
            (success) = ICzzSwap(czzToken).transfer(msg.sender, gas); 
            require(success, 'swapAndMintTokenForEthWithPath gas Transfer error');
        }
        _swapEthMint(_amountIn - gas, _amountInMin, userPath, _to, routerAddr, deadline);
        emit MintToken(_to, amounts[amounts.length - 1], mid, _amountIn);
    }
    
    function swapAndBurnWithPath(uint _amountIn, uint _amountInMin, uint256 ntype, address routerAddr, address[] memory path, uint deadline, address[] memory toPath, bytes extradata) payable public
    {
        require(address(0) != routerAddr); 
        require(path[path.length - 1] == czzToken, "last path is not czz"); 

        uint[] memory amounts = swapGetAmount(_amountIn, path, routerAddr);
        _swapBurn(_amountIn, _amountOutMin, path, msg.sender, routerAddr, deadline);
        if(ntype != _ntype){
            ICzzSwap(czzToken).burn(msg.sender, amounts[amounts.length - 1]);
            emit BurnToken(msg.sender, amounts[amounts.length - 1], ntype, toToken, toPath, extradata);
        }
    }
    
    function swapAndBurnEthWithPath(uint _amountInMin, uint256 ntype, address routerAddr, address[] memory path, uint deadline, address[] memory toPath, bytes extradata) payable public
    {
        require(address(0) != routerAddr); 
        require(path[path.length - 1] == czzToken, "last path is not czz"); 
        require(msg.value > 0);
        uint[] memory amounts = swapGetAmount(msg.value, path, routerAddr);
        _swapEthBurn(_amountInMin, path, msg.sender, routerAddr, deadline);
        if(ntype != _ntype){
            ICzzSwap(czzToken).burn(msg.sender, amounts[amounts.length - 1]);
            emit BurnToken(msg.sender, amounts[amounts.length - 1], ntype, toToken, toPath, extradata);
        }
    }
    
    function setMinSignatures(uint8 value) public isManager {
        minSignatures = value;
    }

    function getMinSignatures() public view isManager returns(uint256){
        return minSignatures;
    }

    function setCzzTonkenAddress(address addr) public isManager {
        czzToken = addr;
    }

    function getCzzTonkenAddress() public view isManager returns(address ){
        return czzToken;
    }

    function burn( uint _amountIn, uint256 ntype, string memory toToken) payable public 
    {
        ICzzSwap(czzToken).burn(msg.sender, _amountIn);
        emit BurnToken(msg.sender, _amountIn, ntype, toToken);
    }
    
    function mintWithGas(uint256 mid, address _to, uint256 _amountIn, uint256 gas, address routerAddr)  payable public isManager 
    {
        require(address(0) != routerAddr); 
        require(_amountIn > 0);
        require(_amountIn >= gas, "ROUTER: transfer amount exceeds gas");

        bool success = true;   
        if(gas > 0){
           (success) = ICzzSwap(czzToken).mint(msg.sender, gas);
            require(success, 'mintWithGas gas Transfer error');
        }
        (success) = ICzzSwap(czzToken).mint(_to, _amountIn-gas);
        require(success, 'mintWithGas amountIn Transfer error');
        emit MintToken(_to, _amountIn-gas, mid,_amountIn);
    }

    function mint(uint256 mid, address _to, uint256 _amountIn)  payable public isManager 
    {
        ICzzSwap(czzToken).mint(_to, _amountIn);
        emit MintToken(_to, 0, mid,_amountIn);
    }
}

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}
