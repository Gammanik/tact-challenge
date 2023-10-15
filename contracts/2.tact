import "@stdlib/deploy";
import "@stdlib/ownable";

/*
  TASK 2 - Proxy 
  Create a contract that forwards all received TONs to the admin contract (whose address is set in init_store).
  Message from this proxy contract to the admin contract should contain:
    - Address of user who sent original message (should be stored in the outcoming body's data/bits)
    - Original message that proxy smart contract received from user (should be stored in the outcoming body's first ref)

  Also, if admin contract decides to reject message (if it sends to the proxy "Refund" message with opcode=0x44),
  proxy contract needs to forward all TONs (attached to Refund message) back to the user.
  User address will be provided in Refund message body as "sender".
  In refund transaction, it is important to have a check that the refund message came from the admin address
*/

// todo: store map of usersForReturn?

message(0x44) Refund {
  queryId: Int as uint64;
  sender: Address;
}

contract Task2 with Deployable, Ownable { // todo: could add OwnableTransferable as it's admin but not owner
  owner: Address;

  init(owner: Address) {
    self.owner = owner;
  }
  
  receive(msg: Refund) {
    self.requireOwner();
    // todo: add check that the amount of returned message (SendRemainingValue) is the same it was??

    let body: Cell = beginCell() // todo less vars for less gas consuming
        //.storeRef(beginCell().)
        .storeAddress(msg.sender)
    .endCell();

    send(SendParameters{
        to: msg.sender,
        value: 0,
        mode: SendRemainingValue + SendIgnoreErrors, // todo: forward all TONs (attached to Refund message) back to the user
        bounce: true,
        body: body
    });
  }

  receive(msg: Slice) {
    let body: Cell = beginCell()
        .storeRef(beginCell().storeAddress(sender()).endCell())
        .storeSlice(msg)
    .endCell(); // todo: null body if msg is empty?

    send(SendParameters{
        to: self.owner,
        value: 0,
        mode: SendRemainingBalance + SendIgnoreErrors,
        bounce: true,
        body: body
    });
  }
}
