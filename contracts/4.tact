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
    forwardPayload: Slice as remaining; // the same defaults as for task 3
}

message NftWithdrawal {
  queryId: Int as uint64;
  nftAddress: Address;
}

contract Task4 with Deployable {
  seed: Int as uint128;
  timeLockEnds: Int?; // todo: nullable t{timeLockEnds, prevOwner} less gas?
  prevOwner: Address?;
  nftAddress: Address?;

  init(seed: Int) {
      self.seed = seed; // needed to deploy multiple smart contracts copies from one admin address
  }

  receive(msg: OwnershipAssigned) {
      if self.isLocked() {
          self.send(sender(), msg.prevOwner, msg.forwardPayload);
      } else { // LOCK
          self.nftAddress = sender(); // messages are send from nft contract
          self.prevOwner = msg.prevOwner;
          self.timeLockEnds = now() + msg.forwardPayload.loadUint(32);
      }
  }

  receive(msg: NftWithdrawal) {
      require(sender() == self.prevOwner!!, "Invalid sender"); // if sender is not the owner (that came from OwnershipAssigned as prevOwner address) then throw "Invalid sender"

      if self.isLocked() {
          self.reply("NFT is still locked".asComment());
      } else { // UNLOCK
          self.send(msg.nftAddress, msg.prevOwner, msg.forwardPayload);
          // nullify vars
          self.timeLockEnds = null;
          self.prevOwner = null;
          self.nftAddress = null;
      }
  }

  inline fun isLocked(): Bool {
    return self.timeLockEnds != null && (self.timeLockEnds!! > now());
  }

  get fun time(): Int { // get how much lock time is left
      if self.timeLockEnds == null { return 0; }

      let left: Int = self.timeLockEnds!! - now();
      if left > 0 { return self.timeLockEnds!! - now(); } else { return 0; }
  }
  get fun nft(): Address? { return self.nftAddress; }
  get fun owner(): Address? { return self.prevOwner; }

  inline fun send(to: Address, newOwner: Address, fwPayload: Slice) {
     send(SendParameters{
        to: to,
        value: 0,
        mode: SendRemainingValue + SendIgnoreErrors,
        body: Transfer{
          queryId: 0,
          newOwner: newOwner,
          responseDestination: myAddress(),
          customPayload: null,
          forwardAmount: ton("0.01"),
          forwardPayload: fwPayload
        }.toCell()
      });
  }
}