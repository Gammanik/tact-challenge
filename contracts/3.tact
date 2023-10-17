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

message(0x7362d09c) TokenNotification {
    queryId: Int as uint64;
    amount: Int as coins;
    from: Address;
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
      self.validateToken(t.from);
      if (self.isAdmin()) {
        self.updateLiquidity(t);
      } else {
        self.processBuy(t);
    }
  }

  inline fun updateLiquidity(t: TokenNotification) {
      if (t.from == self.jettonAddressA) {
        self.aAmount = self.aAmount + t.amount;
      } else {
        self.bAmount = self.bAmount + t.amount;
      }
  }

  inline fun processBuy(t: TokenNotification) {
      if (t.from == self.jettonAddressA) { // if send A buy B
          self.buy(self.bAmount, self.aAmount, t); // want to buy B for A  || a -> b
      } else {
          self.buy(self.aAmount, self.bAmount, t); // want to buy A sell B || b -> a
      }
  }

  // 10b 2a ||  aToSend = price_a-b * amount_b_deposited

  /*Example formula for amountOfAToSend in B->A swap will be
  (amountOfAOnContract * decimal / amountOfBOnContract) * amountOfTokenBToSwap / decimal */
  inline fun buy(wantToBuy: Int, give: Int, t: TokenNotification) { // B->A swap
      let amountToSend : Int = (wantToBuy * self.decimal / give) * t.amount / self.decimal; // t.amount - has taken to buy amount

      if (amountToSend > self.balance(t.from)) {
          self.refundTokens(t.amount);
      } else {
          self.executeBuy(t.from, amountToSend, t.amount);
      }
  }

  inline fun refundTokens(amount: Int) {
      self.tokenTransfer(amount, context().sender);
  }

  inline fun executeBuy(buyerAddress: Address, amountToSend: Int, collateral: Int) {
      self.tokenTransfer(amountToSend, buyerAddress);
      if (buyerAddress == self.jettonAddressA) { // if address A then was send to A
          self.aAmount = self.aAmount - amountToSend;
          self.bAmount = self.bAmount + collateral;
      } else {
          self.bAmount = self.bAmount - amountToSend;
          self.aAmount = self.aAmount + collateral;
      }
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

  // priceB = aAmn / bAmn ;; 1btc 10eth pBtc = 10eth / 1btc ;; pa = 1b/10a
  get fun price(jetton: Address): Int {
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

  inline fun validateToken(tokenAddress: Address) {
    require(tokenAddress == self.jettonAddressA || tokenAddress == self.jettonAddressB, "Invalid token");
  }
  inline fun isAdmin(): Bool { return context().sender == self.owner; }

}

// 10b 1a pa = 10b, pb = 0.1a
// 5a : 10 * 5a = 50b
