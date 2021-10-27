pragma solidity 0.7.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GreenBondSmartContract Ownable {
    using SafeMath for uint256;

    string name;
    uint256 totalDebt; 
    uint256 totalOwed; 
    uint256 parDecimals;
    uint256 bondsNumber;
    uint256 cap;
    uint256 parValue;
    uint256 couponRate;
    uint256 term;
    uint256 timesToRedeem;
    uint256 loopLimit;
    uint256 nonce = 0;
    uint256 couponThreshold = 0;
    uint256 intervalCount = 0;

    mapping(uint256 => address) bonds;
    mapping(uint256 => uint256) maturities;
    mapping(uint256 => uint256) couponsRedeemed;
    mapping(address => uint256) bondsAmount;

    uint256[] noxHistory;

    event TotalOwedUpdated(uint256 totalOwed);

    constructor(
        string memory _name,
        uint256 _par,
        uint256 _parDecimals,
        uint256 _coupon,
        uint256 _term,
        uint256 _cap,
        uint256 _timesToRedeem,
        uint256 _loopLimit,
        name = _name;
        parValue = _par;
        cap = _cap;
        loopLimit = _loopLimit;
        parDecimals = _parDecimals;
        timesToRedeem = _timesToRedeem;
        couponRate = _coupon;
        term = _term;
        couponThreshold = term.div(timesToRedeem);
    )

    function changeLoopLimit(uint256 _loopLimit) public override onlyOwner {
        require(_loopLimit > 0, "Loop limit lower than or equal to 0");
        loopLimit = _loopLimit;
    }
   
    function mintBond(address buyer, uint256 _bondsAmount)
        public
        override
        onlyOwner
    {
        require(buyer != address(0), "Buyer can't be address null");
        require(
            _bondsAmount > 0,
            "Amount of bonds to mint must be higher than 0"
        );
        require(
            _bondsAmount <= loopLimit,
            "Amount of bonds to mint must be lower than the loop limit"
        );

        if (cap > 0) {
            require(
                bondsNumber.add(_bondsAmount) <= cap,
                "Total amount of bonds must be lower or equal to the cap"
            );
        }

        bondsNumber = bondsNumber.add(_bondsAmount);

        nonce = nonce.add(_bondsAmount);

        for (uint256 i = 0; i < _bondsAmount; i++) {
            maturities[nonce.sub(i)] = now.add(term);
            bonds[nonce.sub(i)] = buyer;
            couponsRedeemed[nonce.sub(i)] = 0;
            bondsAmount[buyer] = bondsAmount[buyer].add(_bondsAmount);
        }

        totalDebt = totalDebt.add(parValue.mul(_bondsAmount)).add(
            (parValue.mul(couponRate).div(100)).mul(
                timesToRedeem.mul(_bondsAmount)
            )
        );

        emit MintedBond(buyer, _bondsAmount);
    }

    function redeemCoupons(uint256[] memory _bonds) public override {
        require(_bonds.length > 0, "Array of bonds must not be empty");
        require(
            _bonds.length <= loopLimit
        );
        require(
            _bonds.length <= getBalance(msg.sender)
        );

        uint256 issueDate = 0;
        uint256 lastThresholdRedeemed = 0;
        uint256 toRedeem = 0;

        for (uint256 i = 0; i < _bonds.length; i++) {
            if (
                bonds[_bonds[i]] != msg.sender ||
                couponsRedeemed[_bonds[i]] == timesToRedeem
            ) continue;

            issueDate = maturities[_bonds[i]].sub(term);

            lastThresholdRedeemed = issueDate.add(
                couponsRedeemed[_bonds[i]].mul(couponThreshold)
            );

            if (
                lastThresholdRedeemed.add(couponThreshold) >=
                maturities[_bonds[i]] ||
                now < lastThresholdRedeemed.add(couponThreshold)
            ) continue;

            toRedeem = (now.sub(lastThresholdRedeemed)).div(couponThreshold);

            if (toRedeem == 0) continue;

            couponsRedeemed[_bonds[i]] = couponsRedeemed[_bonds[i]].add(
                toRedeem
            );

            getMoney(
                toRedeem.mul(
                    parValue.mul(couponRate).div(10**(parDecimals.add(2)))
                ),
                msg.sender
            );

            if (couponsRedeemed[_bonds[i]] == timesToRedeem) {
                bonds[_bonds[i]] = address(0);
                maturities[_bonds[i]] = 0;
                bondsAmount[msg.sender]--;

                getMoney(parValue.div((10**parDecimals)), msg.sender);
            }
        }

        emit RedeemedCoupons(msg.sender, _bonds);
    }

    function transfer(address receiver, uint256[] memory _bonds)
        public
        override
    {
        require(_bonds.length > 0, "Array of bonds must not be empty");
        require(receiver != address(0), "Receiver's address cannot be null");
        require(
            _bonds.length <= getBalance(msg.sender)
        );

        for (uint256 i = 0; i < _bonds.length; i++) {
            if (
                bonds[_bonds[i]] != msg.sender ||
                couponsRedeemed[_bonds[i]] == timesToRedeem
            ) continue;

            bonds[_bonds[i]] = receiver;
            bondsAmount[msg.sender] = bondsAmount[msg.sender].sub(1);
            bondsAmount[receiver] = bondsAmount[receiver].add(1);
        }

        emit Transferred(msg.sender, receiver, _bonds);
    }

    function updateTotalOwed(uint256 noxMeasurement) public { 
        noxHistory.push(noxMeasurement);
        totalOwed += noxMeasurement.mul(2).add(bondsNumber.mul(parValue).mul(couponRate).div(100));
        emit TotalOwedUpdated(totalOwed);

    }

    function payTotalDebt() public payable onlyOwner {
		require msg.value is == totalDebt        
        totalDebt -= msg.value;
    }

    receive() external payable {}

    fallback() external payable {}


    function getMoney(uint256 amount, address payable receiver) private {
        if (address(token) == address(0))
            receiver.transfer(amount);
        else
           ERC20(token).transfer(msg.sender, amount);
        receiver.transfer(amount);
        totalDebt = totalDebt.sub(amount); // ?
    }

    //GETTERS


    function getLastTimeRedeemed(uint256 bond)
        public
        override
        view
        returns (uint256)
    {
        uint256 issueDate = maturities[bond].sub(term);

        uint256 lastThresholdRedeemed = issueDate.add(
            couponsRedeemed[bond].mul(couponThreshold)
        );

        return lastThresholdRedeemed;
    }

    function getBondOwner(uint256 bond) public override view returns (address) {
        return bonds[bond];
    }

    function getRemainingCoupons(uint256 bond)
        public
        override
        view
        returns (int256)
    {
        address owner = getBondOwner(bond);

        if (owner == address(0)) return -1;

        uint256 redeemed = getCouponsRedeemed(bond);

        return int256(timesToRedeem - redeemed);
    }

    function getCouponsRedeemed(uint256 bond)
        public
        override
        view
        returns (uint256)
    {
        return couponsRedeemed[bond];
    }

    function getTokenAddress() public override view returns (address) {
        return (address(token));
    }


    function getTimesToRedeem() public override view returns (uint256) {
        return timesToRedeem;
    }


    function getTerm() public override view returns (uint256) {
        return term;
    }

    function getMaturity(uint256 bond) public override view returns (uint256) {
        return maturities[bond];
    }


    function getSimpleInterest() public override view returns (uint256) {
        uint256 rate = getCouponRate();

        uint256 par = getParValue();

        return par.mul(rate).div(100);
    }


    function getCouponRate() public override view returns (uint256) {
        return couponRate;
    }


    function getParValue() public override view returns (uint256) {
        return parValue;
    }

    function getCap() public override view returns (uint256) {
        return cap;
    }

    function getBalance(address who) public override view returns (uint256) {
        return bondsAmount[who];
    }

    function getParDecimals() public override view returns (uint256) {
        return parDecimals;
    }

    function getName() public override view returns (string memory) {
        return name;
    }

    function getTotalDebt() public override view returns (uint256) {
        return totalDebt;
    }
    
    function getTotalOwed() public override view returns (uint256) {
        return totalOwed;
    }

    function getTotalBonds() public override view returns (uint256) {
        return bondsNumber;
    }

    function getNonce() public override view returns (uint256) {
        return nonce;
    }

    function getCouponThreshold() public override view returns (uint256) {
        return couponThreshold;
    }
}
