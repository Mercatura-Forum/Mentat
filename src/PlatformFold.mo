/// PlatformFold.mo - the platform operator: a fact of the log, claimed once and handed over in two steps.
///
/// WHO MAY ACT IS THE GATE'S QUESTION, NOT THIS FOLD'S (`Gate.mo`): a claim is let through only while the log
/// names no operator and no company has been brought into existence, an offer only from the operator, and an
/// acceptance only from the principal the standing offer names. What is left here is what the acts write and the
/// two refusals that are about the offer itself rather than about who sent it.
///
/// THE CLAIM is the calendar authority's first-caller rule moved onto the log, with its window closed: once the
/// first company is on the log a claim is refused for good, so a lost race is found at install, never on a
/// contract that holds data. THE HAND-OVER is two steps, as `Ownable2Step` hands over an owner: the operator offers
/// the role to a principal, a new offer replaces the standing one, an offer to nobody withdraws it, and the role
/// moves only when the principal offered accepts in its own name - so a mistyped principal never strands the role.
///
/// The role is not a company role and grants nothing inside any company: the gate's `#platform` holders name the
/// acts it authorises, and none of them is an act on a company's records.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Principal "mo:core/Principal";

import RowStore "mo:kernel/rows/RowStore";

import PR "PlatformRows";

module {

  public type Refusal = {
    /// an offer to the operator itself: it holds the role already
    #offerToSelf : { operator : Principal };
    /// an offer to nobody, with no offer standing to withdraw
    #noOfferToWithdraw;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#offerToSelf { operator }) Principal.toText(operator) # " is the platform operator already";
      case (#noOfferToWithdraw) "no offer of the platform operator's role stands to withdraw";
    }
  };

  public type Stores = {
    var platform : RowStore.Store;
  };

  public func newStores() : Stores {
    { var platform = RowStore.newStore<PR.Platform>(PR.platform) }
  };

  public type Ctx = {
    platform : Stores;
    block : Nat;
    caller : Principal;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  // ── reads ───────────────────────────────────────────────────────────────────

  /// The operator, the block it took the role at and the standing offer; null while the log names none.
  public func current(st : Stores) : ?PR.Platform {
    RowStore.get<PR.Platform>(st.platform, PR.platform, PR.ROW_ID)
  };

  public func isOperator(st : Stores, p : Principal) : Bool {
    switch (current(st)) { case (?x) x.operator == p; case null false }
  };

  /// The principal the standing offer names, if one stands.
  public func offered(st : Stores) : ?Principal {
    switch (current(st)) { case (?x) x.offered; case null null }
  };

  // ── the acts ────────────────────────────────────────────────────────────────

  /// The caller becomes the operator. The gate has let it through only while no operator is named and no
  /// company exists.
  public func claim(c : Ctx) : Outcome {
    RowStore.put<PR.Platform>(c.platform.platform, PR.platform, PR.ROW_ID, {
      operator = c.caller; sinceBlock = c.block; offered = null; offeredBlock = 0; lastBlock = c.block;
    });
    #ok([PR.ROW_ID])
  };

  /// The operator offers the role to `to`, replacing any standing offer; `to = null` withdraws the standing one.
  public func offer(c : Ctx, to : ?Principal) : Outcome {
    let ?x = current(c.platform) else return #err(#noOfferToWithdraw);
    switch (to) {
      case (?p) { if (p == x.operator) return #err(#offerToSelf { operator = x.operator }) };
      case null { if (x.offered == null) return #err(#noOfferToWithdraw) };
    };
    RowStore.put<PR.Platform>(c.platform.platform, PR.platform, PR.ROW_ID, {
      x with offered = to; offeredBlock = c.block; lastBlock = c.block;
    });
    #ok([PR.ROW_ID])
  };

  /// The principal offered takes the role. The gate has let it through only from that principal.
  public func accept(c : Ctx) : Outcome {
    let ?x = current(c.platform) else return #err(#noOfferToWithdraw);
    RowStore.put<PR.Platform>(c.platform.platform, PR.platform, PR.ROW_ID, {
      operator = c.caller; sinceBlock = c.block; offered = null; offeredBlock = c.block; lastBlock = c.block;
    });
    #ok([PR.ROW_ID])
  };
}
