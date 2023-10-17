import "@stdlib/deploy";

/*
  TASK 4 - NFT locker
  Implement a smart contract that will lock NFT for a period of time specified by the owner.
  Smart conrtact should contain logic to process following messages and getters: 

  Messages: 
  * OwnershipAssigned
   - Recives nft + time (in a forwardPayload message as uint32) for which this nft will be locked + address of the sender of the nft (prevOwner).
   - If the smart contract already holds an nft then return the incoming nft back to the sender
  * NftWithdrawal
   - Request withdrawal of the locked nft
   - If sender is not the owner (that came from OwnershipAssigned as prevOwner address) then throw "Invalid sender" 
   - If time has not passed then send message back to the sender with the comment "NFT is still locked" according to the TON's "message with text comment" standard 
   - Otherwise (all good) send the locked nft back to the owner with all the remaining TON balance
   Note that the order of checks is important
   (in case: "sender is not the owner" and "time has not passed" at the same time, "Invalid sender" error takes priority)

  Getters:
  * time
   - get how much lock time is left
  * nft
   - get the address of the locked nft 
  * owner
   - get the owner of the locked nft (that came from OwnershipAssigned as prevOwner)
*/

message(0x05138d91) OwnershipAssigned {
    queryId: Int as uint64;
    prevOwner: Address;
    forwardPayload: Slice as remaining; 
}

message(0x5fcc3d14) Transfer { 
    queryId: Int as uint64;            
    newOwner: Address; 
    responseDestination: Address; 
    customPayload: Cell?; 
    forwardAmount: Int as coins; 
    forwardPayload: Slice as remaining; 
}

message NftWithdrawal {
  queryId: Int as uint64;
  nftAddress: Address;
}

contract Task4 with Deployable {
  seed: Int as uint128;
  timeTillLockEnds: Int?; // todo: could make just one nullable struct instead
  prevOwner: Address?;


  init(seed: Int) {
    self.seed = seed; // needed to deploy multiple smart contracts copies from one admin address
  }

  receive(msg: OwnershipAssigned) {
    require(sender() == msg.prevOwner, "as per TEP-62 sender() == prevOwner");
    self.timeTillLockEnds = now() + msg.forwardPayload.loadUint(64);
    self.prevOwner = msg.prevOwner;
    self.rejectIfAlreadyHolds(msg);
  }

  receive(msg: NftWithdrawal) {
    require(sender() == self.prevOwner,"sender is not the owner"); // if sender is not the owner (that came from OwnershipAssigned as prevOwner address) then throw "Invalid sender"
    if (now() < self.timeTillLockEnds!!) { self.reply("NFT is still locked".asComment()); }
    self.unlock(msg);
  }

  get fun time(): Int { // get how much lock time is left
    if (self.timeTillLockEnds == null) { return 0; }
    return self.timeTillLockEnds!! - now();
  }

  get fun nft(): Address? { // get the address of the locked nft todo!!!
    if (self.timeTillLockEnds == null) { return null; }
    return myAddress();
  }

  // get the owner of the locked nft (that came from OwnershipAssigned as prevOwner)
  get fun owner(): Address? { return self.prevOwner; }

  inline fun rejectIfAlreadyHolds(msg: OwnershipAssigned) {
    // If the smart contract already holds an nft then return the incoming nft back to the sender
    if (self.timeTillLockEnds != null) {
      send(SendParameters{
        to: sender(),
        value: 0,
        body: Transfer{
          queryId: msg.queryId, // todo: !! get from input
          newOwner: msg.prevOwner,
          responseDestination: msg.prevOwner,
          customPayload: null,
          forwardAmount: 0,
          forwardPayload: msg.forwardPayload
        }.toCell()
      });
    }
  }

  inline fun unlock(msg: NftWithdrawal) {
    send(SendParameters{ // send the locked nft back to the owner with all the remaining TON balance
      to: self.prevOwner!!,
      value: 0,
      mode: SendRemainingBalance + SendIgnoreErrors,
      body: Transfer{
        queryId: msg.queryId,
        newOwner: self.prevOwner!!,
        responseDestination: self.prevOwner!!,
        customPayload: null,
        forwardAmount: 0,
        forwardPayload: emptyCell().asSlice() // todo: think
      }.toCell()
    });
    // nullify vars
    self.timeTillLockEnds = null;
    self.prevOwner = null;
  }

}