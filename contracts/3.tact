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
      require(sender() == self.jettonAddressA || sender() == self.jettonAddressB, "Invalid token");
      if (t.from == self.owner) { // admin can't buy, only deposit
        self.deposit(t.amount);
      } else { // buy collateral with t.amount
        self.buy(t);
    }
  }

  /* Example formula for amountOfAToSend in B->A swap will be
     amountOfAToSend = (amountA * decimal / amountB) * amountOfTokenBToSwap / decimal */
  inline fun buy(t: TokenNotification) {
      let clAddress: Address = self.collateralAddress(sender()); // collateralAddress
      let clPrice: Int = self.price(clAddress); // collateralPrice
      let amountToBuy: Int = clPrice * t.amount / self.decimal;

      if amountToBuy > self.balance(clAddress) { // todo:
          self.send(t.amount, t.from); // refund
      } else {
          self.executeBuy(amountToBuy, t.amount);
      }
  }

  inline fun executeBuy(amountBought: Int, staked: Int) {
      self.send(amountBought, sender());
      if (sender() == self.jettonAddressA) {
          self.aAmount = self.aAmount + staked; // a->b: staked A withdraw B
          self.bAmount = self.bAmount - amountBought;
      } else {
          self.bAmount = self.bAmount + staked; // b->a: staked B withdraw A
          self.aAmount = self.aAmount - amountBought;
      }
  }

  inline fun send(amountToSend: Int, destination: Address) {
      send(SendParameters{
          to: sender(),
          value: 0,
          mode: SendRemainingValue + SendIgnoreErrors,
          bounce: true,
          body: TokenTransfer{
              queryId: 0,
              amount: amountToSend,
              destination: destination,
              responseDestination: destination, // todo: destination?
              customPayload: null,
              forwardTonAmount: ton("0.01"),
              forwardPayload: emptySlice()
          }.toCell()
      });
  }

  // 1a 10b => price_of_b = 0.1a = 1b / 10a = b / a -- NO price_of1_b = 10a
  get fun price(jetton: Address): Int { // price for jetton
    require(self.aAmount != 0 && self.bAmount != 0, "a b != 0");

    if (jetton == self.jettonAddressA) { // then return how much b could get for 1a
      return self.bAmount * self.decimal / self.aAmount;
    } else if (jetton == self.jettonAddressB) { // price for b
      return self.aAmount * self.decimal / self.bAmount;
    } throw(0); return 0;
  }

  get fun balance(jetton: Address): Int {
    if (jetton == self.jettonAddressA) {
      return self.aAmount;
    } else if (jetton == self.jettonAddressB) {
      return self.bAmount;
    } throw(0); return 0;
  }

  // collateral token address: collateralAddress(a) -> b
  inline fun collateralAddress(adr: Address): Address { // to get the price I need collaterall address ; the fun would not be needed if there was ternary operator
    if adr == self.jettonAddressA { return self.jettonAddressB; }
    return self.jettonAddressA;
  }

  inline fun deposit(amount: Int) {
      if (sender() == self.jettonAddressA) { self.aAmount = self.aAmount + amount; }
      else { self.bAmount = self.bAmount + amount; }
  }

}
