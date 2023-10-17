import "@stdlib/deploy";

/*
  TASK 3 - DEX
  Create a simple jetton dex contract that trades one pair of jettons: A and B.
  The price of jettons depends on the amount of jettons that smart contract has.
  Therefore, the smart contract needs to keep track of how much jettons it has.
  
  Price for the jetton A in swap B->A should be calculated by formula:
    "amountOfJettonAOnContract * decimal / amountOfJettonBOnContract".
  Token prices must be decimalized for accuracy, so it is the prices that must be adjusted to decimal 1e9.
  Decimals are only needed for price accuracy. It should be set as 1e9.
  So, if smart contract has 10 of jetton A and 2 of jetton B, then after sending 1 jetton B you should receive 5 of jettons A.

  Example formula for amountOfAJettonToSend in B->A swap will be
  (amountOfJettonAOnContract * decimal / amountOfJettonBOnContract) * amountOfTokenBToSwap / decimal

  If smart contract pool doesn't have enough jettons to trade,
  then it should send incoming jettons back to the user. For a clearer explanation,
  let's look at the example we described above (smart contract has 10 of jetton A and 2 of jetton B).
  If user will send 3 jettons B, smart contract should reject the message (because contract does not have 3 * 5 = 15 jettons A)
  and send 3 jettons B back to the user.

  If smart contract receives a different jetton (neither A nor B) then throw an error.

  Implement a getter that returns the number of jettons in the pool and
  one more to get the price of jetton A or jetton B.
  Getters' behavior with incorrect parameter (address other than that of jetton A or B)
  is undefined (there are no such tests).
  
  Note:
  Admin can add jettons A and B just by sending them to the smart contract (we need to add initial supply to the pool for it to be functional).
  To be exact: any jettons (A or B) received from the admin are "added". Admin can't swap.
*/

message(0x7362d09c) TokenNotification { // the sender() is always A or B but .from is prevOwner
    queryId: Int as uint64;
    amount: Int as coins;
    from: Address; // or from is A || B?
    forwardPayload: Slice as remaining;
}

// To simplify the testing process and the specificity of the messages being sent, we decided to add clear default values in this transaction
message(0xf8a7ea5) TokenTransfer {
     queryId: Int as uint64; // should be 0
     amount: Int as coins; // should be amount of jettons to send
     destination: Address; // should be user address / TokenNotification.from
     responseDestination: Address?; // should be myAddress()
     customPayload: Cell?; // should be null
     forwardTonAmount: Int as coins; // should be ton("0.01")
     forwardPayload: Slice as remaining; // should be emptySlice()
}

contract Task3 with Deployable {
  owner: Address;

  aAmount: Int; // refactor make: a{amount, address}, b{amount, address}
  bAmount: Int;
  jettonAddressA: Address;
  jettonAddressB: Address;
  decimal: Int;

  init(admin: Address, newJettonAddressA: Address, newJettonAddressB: Address) {
    self.owner = admin;
    self.jettonAddressA = newJettonAddressA;
    self.jettonAddressB = newJettonAddressB;
    self.aAmount = 0;
    self.bAmount = 0;
    self.decimal = 1000000000;
  }

  /* MAIN LOGIC */
  receive(t: TokenNotification) {
      require(sender() == self.jettonAddressA || sender() == self.jettonAddressB, "Invalid token");
      if (t.from == self.owner) { // admin can't buy | only deposit
        self.deposit(t.amount);
      } else { // buy collateral with t.amount
        self.buy(t);
    }
  }

  inline fun deposit(amount: Int) {
      if (sender() == self.jettonAddressA) { // sender() == a.addr check means admin is A contract
        self.aAmount = self.aAmount + amount;
      } else {
        self.bAmount = self.bAmount + amount;
      }
  }

  /*
    amounts: 10b 2a || aToSend = price_a * amount_b_deposited
      -got 2a for change:
        b_to_return = 10 = (10/2) * 2 = price_(b) * deposited
    Example formula for amountOfAToSend in B->A swap will be
    amountOfAToSend = (amountA * decimal / amountB) * amountOfTokenBToSwap / decimal
  */
  inline fun buy(t: TokenNotification) { // A->B swap ; swapAm: f.from == a.addr ? b.price * t.am : a.price * t.am
      let clAddress: Address = self.collateralAddress(t.from); // collateralAddress
      let clPrice: Int = self.price(clAddress); // collateralPrice
      let amountWantToBuy: Int = clPrice * t.amount / self.decimal;

      if (amountWantToBuy > self.balance(self.collateralAddress(sender()))) { // todo:
          self.refundTokens(t.amount);
      } else {
          self.executeBuy(amountWantToBuy, t.amount, t.from);
      }
  }

  // collateral token address: collateralAddress(a) -> b
  inline fun collateralAddress(adr: Address): Address { // to get the price I need collaterall address ; the fun would not be needed if there was ternary operator
    if adr == self.jettonAddressA { return self.jettonAddressB; }
    return self.jettonAddressA;
  }

  inline fun executeBuy(amountBought: Int, staked: Int, buyerAddress: Address) {
      self.tokenTransfer(amountBought, buyerAddress);
      if (buyerAddress == self.jettonAddressA) { // if message came from A
          self.aAmount = self.aAmount + staked; // a->b: staked A withdraw B
          self.bAmount = self.bAmount - amountBought;
      } else {
          self.bAmount = self.bAmount + staked; // b->a: staked B withdraw A
          self.aAmount = self.aAmount - amountBought;
      }
  }

  inline fun refundTokens(amount: Int) {
      self.tokenTransfer(amount, context().sender);
  }

  inline fun tokenTransfer(amountToSend: Int, destination: Address) {
      send(SendParameters{
          to: destination,
          value: 0,
          mode: SendRemainingValue,
          bounce: true,
          body: TokenTransfer{
              queryId: 0,
              amount: amountToSend,
              destination: destination,
              responseDestination: myAddress(),
              customPayload: null,
              forwardTonAmount: ton("0.01"),
              forwardPayload: emptySlice()
          }.toCell()
      });
  }

  /*
      todo: optimise getters for them not to work with div as it's heavy?
      b.price_to_a = a.amount / b.amount ;;
  */
  // 1a 10b => price_of_b_to_a = 0.1a = 1b / 10a =
  // priceOf(jetton: Address)
  get fun price(jetton: Address): Int { // is it the price for address? like if I'm sending from `a` I should get `a` price in `b`?
    if (jetton == self.jettonAddressA) {
      require(self.bAmount == 0, "div by 0");
      return self.aAmount * self.decimal / self.bAmount;
    } else if (jetton == self.jettonAddressB) {
      require(self.aAmount == 0, "div by 0");
      return self.bAmount * self.decimal / self.aAmount;
    }
    throw(0); return 0;
  }

  get fun balance(jetton: Address): Int {
    if (jetton == self.jettonAddressA) {
      return self.aAmount;
    } else if (jetton == self.jettonAddressB) {
      return self.bAmount;
    }
    throw(0); return 0;
  }

}

// 10b 1a pa = 10b, pb = 0.1a
// 5a : 10 * 5a = 50b
