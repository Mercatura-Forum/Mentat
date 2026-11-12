/// Log.mo - Mentat's domain block log: the codec, the event, and the tip.
///
/// A block records one accepted command together with the business date it was accepted on. The
/// log's own `timestamp` field carries the **block height** the Clock read, not a wall-clock
/// instant: under the product's rule on time the calendar authority is this product's only
/// selected time source, and nothing here reads `Time.now()`. The received tree calls it 432 times
/// (`main.mo` 430, `crm.mo` 2); this tree calls it zero times and
/// `tools/no_direct_clock.sh` is what keeps that true.
///
/// The event carries the command's **encoding version**. That is rule 3 of the encoding freeze made
/// structural: anything re-deriving a command's hash takes the version from the block that recorded
/// it, and it is in the block because it was written there, not because a reader assumed `current`.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";

import C "mo:kernel/codec/Canonical";
import DL "mo:kernel/domain/DomainLog";
import KE "mo:kernel/domain/Encoding";

import Cmd "Command";
import Enc "Encoding";

module {

  public type Command = Cmd.Command;

  /// What one block records.
  public type Event = {
    /// The business date the command was accepted on, as days since 1970-01-01, from the Clock.
    day : Nat;
    /// The command encoding version these bytes were written under.
    version : Nat8;
    command : Command;
  };

  public let DOMAIN : Text = "QORZA-BLOCK-v1";

  func write(w : C.Writer, e : Event) {
    w.nat(e.day);
    w.nat8(e.version);
    switch (Enc.bytesAt(e.version, e.command)) {
      case (?b) { w.blob(b) };
      // A version that cannot represent the command is a programming fault at the edge, not here:
      // the accept path binds the command to a version before it ever reaches the log, so this
      // arm writes an empty body and the block fails to decode - loudly - rather than writing
      // bytes that decode to something else.
      case null { w.blob(Blob.fromArray([])) };
    };
  };

  func read(r : C.Reader) : ?Event {
    let ?day = r.nat() else return null;
    let ?version = r.nat8() else return null;
    let ?body = r.blob() else return null;
    let ?command = Enc.read(version, body) else return null;
    ?{ day; version; command }
  };

  public let codec : DL.Codec<Event> = {
    version = 1;
    supports = func(v : Nat8) : Bool { v == 1 };
    domain = DOMAIN;
    write;
    read;
  };

  public func newState() : DL.State { DL.newState() };

  /// Bind a command to the current encoding version, ready to be appended. `null` means the current
  /// version cannot represent it - which for a family added in a later version is the right answer,
  /// and which the caller must refuse rather than encode some other way.
  public func bind(day : Nat, c : Command) : ?Event {
    switch (KE.bindCurrent(Enc.registry, c)) {
      case (?b) ?{ day; version = b.version; command = c };
      case null null;
    }
  };

  /// The hash a checker approves and an execution re-derives, under the version the block recorded.
  public func commandHash(e : Event) : ?Blob { Enc.hashAt(e.version, e.command) };

}
