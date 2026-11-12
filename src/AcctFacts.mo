/// AcctFacts.mo - the payloads accounting's commands carry.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  public type AccountFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    accountType : E.AccountType;
    parentId : Nat;
    reconcilable : Bool;
    currency : Text;
  };

  public type JournalFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    journalType : E.JournalType;
    defaultAccountId : Nat;
  };

  /// One line of a proposed move. The account is an id and is resolved by the fold; the received
  /// tree takes it and never looks it up.
  public type LineFacts = {
    accountId : Nat;
    partnerId : Nat;
    name : Text;
    debit : Nat;
    credit : Nat;
    /// The amount in the move's currency where it differs from the company's; 0 when they are the
    /// same. Settable, unlike the received row's, whose only writer wrote the literal 0.
    amountCurrency : Nat;
    taxId : Nat;
  };

  /// A whole move, proposed in one command.
  ///
  /// Lines are not added one at a time. The received tree has `createMove` then `addMoveLine`
  /// then `postMove`, so a move exists in a state where it is neither balanced nor refused, and
  /// what happens to it depends on whether the caller came back. Here a move arrives whole: its
  /// lines balance or the command is refused, and there is no half-built move to find later.
  public type MoveFacts = {
    companyId : Nat;
    journalId : Nat;
    businessDay : Nat;
    moveType : E.MoveType;
    currency : Text;
    partnerId : Nat;
    ref : Text;
    lines : [LineFacts];
  };

  /// The close of a period: its days, the journal the sweep posts to, and the equity account that
  /// receives the period's result.
  public type CloseFacts = {
    companyId : Nat;
    fromDay : Nat;
    throughDay : Nat;
    journalId : Nat;
    retainedEarningsAccountId : Nat;
  };

  /// A statement to publish: its kind and its window. The trial balance and the balance sheet are
  /// cumulative and carry no start (`fromDay` is 0); the income statement is a period's.
  public type StatementFacts = {
    companyId : Nat;
    kind : E.StatementKind;
    fromDay : Nat;
    throughDay : Nat;
  };

  /// A deferral: the amount held on the deferred account (an asset for a prepaid expense, a liability
  /// for unearned revenue), the account it is recognised to, the journal the recognitions post to,
  /// the posted move that put it there (0 if none is named), and the months from the first day's
  /// month over which it is recognised in equal parts, the residue in the last.
  public type DeferralFacts = {
    companyId : Nat;
    kind : E.DeferralKind;
    deferredAccountId : Nat;
    targetAccountId : Nat;
    journalId : Nat;
    sourceMoveId : Nat;
    amount : Nat;
    firstDay : Nat;
    months : Nat;
  };

  /// The revaluation policy: the functional currency every book amount is in, and the income and
  /// expense accounts the unrealised gain and loss on foreign-currency balances go to.
  public type RevaluationPolicyFacts = {
    companyId : Nat;
    functionalCurrency : Text;
    gainAccountId : Nat;
    lossAccountId : Nat;
  };

  /// A fixed asset entering the register: the account its cost stands on, the account its
  /// accumulated depreciation is credited to, the expense its charges go to, the journal they post
  /// in, the posted move that put the cost on the asset account (0 if none is named), its cost and
  /// salvage value, the day it entered service and its useful life in civil months.
  public type AssetFacts = {
    companyId : Nat;
    name : Text;
    assetAccountId : Nat;
    accumulatedAccountId : Nat;
    expenseAccountId : Nat;
    journalId : Nat;
    sourceMoveId : Nat;
    cost : Nat;
    salvage : Nat;
    firstDay : Nat;
    months : Nat;
  };

  /// An impairment: the amount the asset's carrying value is written down by on a day, and the
  /// expense account that takes the loss.
  public type ImpairmentFacts = {
    companyId : Nat;
    assetId : Nat;
    day : Nat;
    amount : Nat;
    lossAccountId : Nat;
    reason : Text;
  };

  /// A disposal: the proceeds (0 for a scrapping) and the monetary account that receives them, and
  /// the income and expense accounts the gain or the loss against the carrying value goes to.
  public type DisposalFacts = {
    companyId : Nat;
    assetId : Nat;
    day : Nat;
    proceeds : Nat;
    proceedsAccountId : Nat;
    gainAccountId : Nat;
    lossAccountId : Nat;
    reason : Text;
  };

}
