/// RstFacts.mo - the payloads the restaurant commands carry: a table of a shop, a tab opened at it
/// inside the shop's till session, a course ordered against the tab, and the bill settled by a rule.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";
import PF "PosFacts";

module {

  /// A table of a shop: one per code per company, with the covers it seats. Declared again, changed.
  public type TableFacts = {
    companyId : Nat;
    shopId : Nat;
    code : Text;
    name : Text;
    seats : Nat;
  };

  /// A tab opened at a table inside a live till session of the table's shop, for so many covers.
  public type TabFacts = {
    companyId : Nat;
    sessionId : Nat;
    tableId : Nat;
    covers : Nat;
  };

  /// A course of a tab: lines added under its ordinal. A course already sent takes no more.
  public type CourseFacts = {
    companyId : Nat;
    tabId : Nat;
    course : Nat;
    lines : [PF.SaleLineFacts];
  };

  /// What one share of a split bill was paid with. Change is given in cash, so the card may not
  /// exceed the share.
  public type TenderFacts = {
    cash : Nat;
    card : Nat;
  };

  /// The bill settled: the rule it is split by, the weights where the rule takes them (one per
  /// share, in order), and the tender of every share. The number of shares is the number of tenders.
  public type SettleFacts = {
    companyId : Nat;
    tabId : Nat;
    rule : E.SplitRule;
    weights : [Nat];
    tenders : [TenderFacts];
  };

}
