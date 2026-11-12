/// Query.mo - the read side: every list is a page, and an over-large request is told so.
///
/// The kernel's `Page.clampLimit` clamps a request to the maximum the row store will serve. That is
/// the right behaviour for the kernel - a store must never be asked to do unbounded work - but it
/// is the wrong behaviour at a product's edge: a caller that asked for 1,000,000 rows and silently
/// received 1,000 has been given a *wrong answer*, not a smaller one, because nothing in the reply
/// says the request was narrowed. The received tree's list methods have the same shape in a worse
/// form: 967 of them materialise a whole store and return it, and 12 of 1,034 take a limit at all.
///
/// So this module refuses at the edge and clamps nowhere. A caller asking past the maximum gets a
/// typed refusal naming the maximum, and a caller asking within it gets exactly what it asked for.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";
import Result "mo:core/Result";

import Page "mo:kernel/rows/Page";

module {

  public type Refusal = {
    #limitTooLarge : { requested : Nat; maximum : Nat };
    #limitIsZero;
    #store : Page.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#limitTooLarge { requested; maximum }) {
        "a page of " # Nat.toText(requested) # " was asked for; the maximum is " # Nat.toText(maximum)
      };
      case (#limitIsZero) "a page of zero rows is not a page";
      case (#store p) Page.describe(p);
    }
  };

  public func maximum() : Nat { Page.MAX_LIMIT };

  public func defaultLimit() : Nat { Page.DEFAULT_LIMIT };

  /// The limit to serve, or the reason the request is refused. Never a narrowed number.
  public func limit(requested : Nat) : Result.Result<Nat, Refusal> {
    if (requested == 0) return #err(#limitIsZero);
    if (requested > Page.MAX_LIMIT) return #err(#limitTooLarge { requested; maximum = Page.MAX_LIMIT });
    #ok(requested)
  };

}
