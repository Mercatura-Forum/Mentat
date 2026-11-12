/// Boundary.mo - what a contract's front door decides, in one place, for every product that has one.
///
/// A product's contract is its own: its own log, its own fold, its own calendar, its own principal
/// that may move it. What is NOT its own is what happens to a submission between the wire and
/// `Contract.accept` - the bytes are decoded under a declared encoding version, the command is
/// accepted or refused, and the refusal is put into words. Two products that wrote that themselves
/// would be two front doors, and the day one of them named a refusal differently, the same command
/// would be rejected in two different languages by two systems that share a ledger.
///
/// So the front door is written once, here, and each contract calls it. The contract keeps what is
/// genuinely its own: the state it holds and the substrate it runs on.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";

import DL "mo:kernel/domain/DomainLog";

import Clk "ClockWiring";
import Con "Contract";
import Enc "Encoding";
import St "State";

module {

  /// What a caller is told. `kind` is the class and `reason` is what the product's own
  /// `refusedText` says about it: a caller that wants to branch should not have to parse prose,
  /// and a caller that wants to report should not have to carry a table.
  public type Outcome = {
    #ok : { block : Nat; day : Nat; height : Nat; effects : [Nat] };
    #err : { kind : Text; reason : Text };
  };

  /// The class of a refusal, as one word. It is derived from the refusal itself rather than
  /// written out at each call site, because a class that is written out is a class that can be
  /// written out differently.
  public func kindOf(r : Con.Refused) : Text {
    switch (r) {
      case (#clock _) "clock";
      case (#unrepresentable _) "unrepresentable";
      case (#refused _) "refused";
    }
  };

  /// THE ONE ROUTE FROM BYTES TO THE LOG.
  ///
  /// The command arrives as its own canonical bytes and is decoded by `Encoding.read`, never as a
  /// Candid variant of the command type: a generated encoding beside the frozen one would be two
  /// encodings of one thing, and the day they drifted a command a caller signed and a command the
  /// log recorded would differ with nothing to say so.
  public func submit(
    log : DL.State,
    state : St.State,
    config : Clk.Config,
    source : Clk.Source,
    caller : Principal,
    version : Nat8,
    bytes : Blob,
  ) : Outcome {
    let ?command = Enc.read(version, bytes) else {
      return #err({
        kind = "undecodable";
        reason = "no command of version " # Nat.toText(Nat8.toNat(version)) # " reads back from those "
                 # Nat.toText(bytes.size()) # " bytes";
      });
    };
    switch (Con.accept(log, state, config, source, caller, command)) {
      case (#ok a) #ok({ block = a.block; day = a.day; height = a.height; effects = a.effects });
      case (#err r) #err({ kind = kindOf(r); reason = Con.refusedText(r) });
    }
  };
}
