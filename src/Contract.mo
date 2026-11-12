/// Contract.mo - the accept path: the one route by which a command reaches the log.
///
/// Four things happen here and nowhere else, in this order, and the order is the point:
///
///   1. **The Clock is read once.** One reading gives the business date and the height, so a
///      decision cannot straddle a block boundary. No caller supplies a time.
///   2. **The command is bound to an encoding version.** The bytes and their hash are fixed before
///      anything is written; a family the current version cannot represent is refused here rather
///      than encoded some other way.
///   3. **The fold is tried against a copy of nothing** - there is no copy. `State.apply` is
///      written so that everything that can refuse refuses before anything is written, and the
///      battery injects a fault at each of its steps to prove it.
///   4. **The block is appended, then the fold is applied to it.** The log is the record; the store
///      is the fold. If the order were reversed a store could hold a row no block explains.
///
/// Step 3 is what makes step 4 safe, and it is the difference between this and the received tree's
/// `validatePicking`, which applies each stock move in turn and returns an error from inside the
/// loop with the earlier moves already applied.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Result "mo:core/Result";
import Runtime "mo:core/Runtime";

import DL "mo:kernel/domain/DomainLog";

import AuditIndex "AuditIndex";
import Clk "ClockWiring";
import Cmd "Command";
import Log "Log";
import RK "ReadKinds";
import RS "ReadSurface";
import St "State";

module {

  public type Refused = {
    /// The Clock could not answer - no business date rolled, or an authority that cannot answer.
    #clock : Clk.Error;
    /// The current encoding version cannot represent this command family.
    #unrepresentable : { family : Text; version : Text };
    /// The fold refused it.
    #refused : St.Refusal;
  };

  public func refusedText(r : Refused) : Text {
    switch (r) {
      case (#clock e) "clock: " # Clk.errorText(e);
      case (#unrepresentable { family; version }) "encoding version " # version # " cannot represent " # family;
      case (#refused f) St.refusalText(f);
    }
  };

  public type Accepted = {
    block : Nat;
    day : Nat;
    height : Nat;
    effects : St.Effects;
  };

  /// Accept one command: read the clock, bind the bytes, fold, append.
  public func accept(
    log : DL.State,
    state : St.State,
    config : Clk.Config,
    source : Clk.Source,
    caller : Principal,
    command : Cmd.Command,
  ) : Result.Result<Accepted, Refused> {

    let reading = switch (Clk.read(config, source)) {
      case (#err e) { return #err(#clock e) };
      case (#ok r) r;
    };

    let event = switch (Log.bind(reading.day, command)) {
      case (?e) e;
      case null {
        return #err(#unrepresentable { family = Cmd.family(command); version = Nat.toText(1) });
      };
    };

    // The block index this command WILL have. `State.apply` writes it into the row's `lastBlock`,
    // so the row names the block that made it before that block exists - which is sound because
    // the append below is the very next thing that happens and cannot fail: `DL.append` asserts
    // its own agreement with the stable log rather than returning an error.
    let index = DL.length(log);

    // The fold is tried FIRST. A refusal here writes nothing, and no block is appended: the log is
    // the record of what happened, and a refused command did not happen.
    let effects = switch (St.apply(state, index, caller, reading.day, DL.tipHash(log), command)) {
      case (#err f) { return #err(#refused f) };
      case (#ok e) e;
    };

    let block = DL.append<Log.Event>(log, Log.codec, Clk.stamp(reading), caller, event, null);

    #ok({ block = block.index; day = reading.day; height = reading.height; effects })
  };

  // ── replay ──────────────────────────────────────────────────────────────────

  /// A replay in progress: the state being rebuilt, and every block whose command the fold refused.
  ///
  /// That second field is not bookkeeping. A block on the log is a command that was ACCEPTED, so
  /// its fold succeeded once; if the same fold refuses it on replay, the two runs disagree about
  /// what the state is, and the fingerprint comparison will say so without saying WHICH block
  /// caused it. Recording the refusals turns a mismatch into a diagnosis. The battery asserts this
  /// list is empty on every clean replay, and non-empty on a replay deliberately fed a log a
  /// smaller arena cannot hold.
  public type Replay = {
    state : St.State;
    var refusals : [(Nat, Text)];
  };

  public func newReplay() : Replay { { state = St.newState(); var refusals = [] } };

  /// Re-apply a block during a replay. The same fold, driven from the log rather than from a
  /// caller - which is what makes "the state is a pure function of the log" true rather than
  /// asserted: there is one `State.apply` and both paths go through it.
  public func replayBlock(r : Replay, b : DL.Block<Log.Event>) {
    switch (St.apply(r.state, b.index, b.caller, b.event.day, b.parentHash, b.event.command)) {
      case (#ok _) {};
      case (#err f) {
        let n = r.refusals.size();
        let old = r.refusals;
        r.refusals := Array.tabulate<(Nat, Text)>(n + 1, func(i) {
          if (i < n) old[i] else (b.index, St.refusalText(f))
        });
      };
    };
  };

  public func replayFingerprint(r : Replay) : Blob { St.fingerprintHash(r.state) };

  /// THE AUDIT INDEX CAUGHT UP FROM THE LOG. A layout retired before the index existed arrives at an upgrade with
  /// a log and no entries; this writes the entries of every block from the first the index does not hold, as the
  /// live path writes them (`State.indexBlock`), and returns how many it wrote. A state whose index is current
  /// writes nothing. A founding act is indexed under the company it brought into existence: companies are
  /// numbered from 1 in the order they were founded, and every founding on the log was accepted, so the company a
  /// founding block made is one more than the number of founding blocks below it.
  ///
  /// THE BOUND is the log: one decode and two writes per block not yet indexed, in the upgrade that lands the
  /// index - the same bound as the retired layouts' other rebuilds (`Migration.mo`).
  /// ONE BLOCK'S BYTES, exactly as stored, to a reader `St.mayReadBlock` serves; otherwise the reason it is not.
  public func blockFor(log : DL.State, s : St.State, reader : Principal, index : Nat) : { #ok : Blob; #err : Text } {
    let ?raw = DL.rawBlock(log, index) else return #err("no block at height " # Nat.toText(index) # "; the log holds " # Nat.toText(DL.length(log)));
    let ?b = DL.get<Log.Event>(log, Log.codec, index) else Runtime.trap("blockFor: block " # Nat.toText(index) # " does not decode");
    switch (St.mayReadBlock(s, reader, index, b.caller, b.event.command)) { case (?why) #err(why); case null #ok(raw) }
  };

  /// THE READ METHOD: a page of one kind of record in one company, or
  /// one record, to a reader its kind's class serves (`ReadSurface`, `ReadKinds`), named with the log's height and
  /// tip it was read at; otherwise the reason it is not served. Deny by default: a kind no class names is no kind.
  public func read(log : DL.State, s : St.State, reader : Principal, version : Nat8, request : Blob) : { #ok : Blob; #err : Text } {
    let ?req = RS.request(version, request) else return #err("the bytes are no read request under version " # Nat.toText(Nat8.toNat(version)));
    let (kind, companyId, lo, hi, limit) = switch (req) {
      case (#page p) (p.kind, p.companyId, (switch (p.after) { case (?a) a + 1; case null 0 }), Nat.pow(2, 64), p.limit);
      case (#record r) (r.kind, r.companyId, r.id, r.id, 1);
    };
    let ?holders = RK.holders(kind) else return #err("no kind of record is called " # kind);
    // the platform's own tables are the platform operator's as well as the companies' (the proposal's "platform rows
    // are read by the operator"); the operator holds no standing in a company and reads nothing else here
    let cut = if (holders == #platform and St.gateView(s).isOperator(reader)) #all
      else switch (RS.cutFor(holders, St.standingRole(s, companyId, reader), reader)) {
        case (#ok c) c;
        case (#err why) return #err("the read of " # kind # " in company " # Nat.toText(companyId) # " is refused: " # why);
      };
    let ?rows = RK.rows(s, kind, companyId, lo, hi, limit, cut) else return #err("no kind of record is called " # kind);
    #ok(RS.pageBytes(DL.length(log), DL.tipHash(log), kind, companyId, rows))
  };

  public func catchUpAudit(log : DL.State, s : St.State) : Nat {
    let from = AuditIndex.indexed(s.audit);
    let length = DL.length(log);
    var founded = 0;
    var h = 0;
    var wrote = 0;
    while (h < length) {
      let ?b = DL.get<Log.Event>(log, Log.codec, h) else Runtime.trap("catchUpAudit: block " # Nat.toText(h) # " does not decode");
      if (Cmd.family(b.event.command) == "bootstrapCompany") founded += 1;
      if (h >= from) { St.indexBlock(s, h, b.caller, b.event.command, founded); wrote += 1 };
      h += 1;
    };
    wrote
  };

}
