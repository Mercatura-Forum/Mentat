/// RstFold.mo - point of sale, the restaurant: tables and courses over the shop's till session, and a
/// bill split by a recorded rule.
///
/// A TABLE IS A SHOP'S, and holds at most one open TAB. A tab is opened by a member - the waiter - 
/// inside the shop's live till session, for so many covers, no more than the table seats. COURSES
/// are ordered against the tab under their ordinal, each line a category on the shop's list and a
/// quantity, no price (the list prices the bill); a course is SENT to the kitchen once, by a member,
/// and takes no more lines after; a line is voided by any member while its course is unsent - once
/// the kitchen has it, only by somebody other than the one who ordered it, a comp with the second
/// person's name on the block. A tab with nothing the kitchen has standing is cancelled and the table
/// freed; one with cooked lines standing is settled.
///
/// THE BILL IS SPLIT BY A RECORDED RULE. At settlement the lines standing are priced by the shop's
/// list through the till's own pricing, the total is divided into as many shares as there are
/// tenders - evenly, or by the weights stated - by the largest-remainder rule to the minor unit (the
/// whole shares first, the minor units left over to the shares with the largest remainders, ties to
/// the earlier share), every share's tender is held to it with the card never over it, and the whole
/// bill is RUNG UP AS ONE SALE THROUGH THE SHOP FOLD, by the session's cashier, with the sum of the
/// tenders - so the Z report carries it, the goods come off the shelf with it, and the shares are a
/// record of who paid what for one receipt. The reader recomputes every share.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AR "AcctRows";
import E "Enums";
import OR "OrderRows";
import PF "PosFacts";
import PFold "PosFold";
import PR "PosRows";
import RF "RstFacts";
import RR "RstRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #codeDoesNotFit : { code : Text; max : Nat };
    #noSuchShop : { shopId : Nat };
    #shopRetired : { shopId : Nat };
    #seatsBound : { seats : Nat; max : Nat };
    #noSuchTable : { tableId : Nat };
    #tableRetired : { tableId : Nat };
    /// The table has a tab open.
    #tableTaken : { tableId : Nat; tabId : Nat };
    #noSuchSession : { sessionId : Nat };
    #sessionNotOpen : { sessionId : Nat; state : Text };
    /// The table belongs to another shop than the session's.
    #tableNotOfShop : { tableId : Nat; shopId : Nat };
    #notAMember : { subject : Principal };
    #coversBound : { covers : Nat; seats : Nat };
    #noSuchTab : { tabId : Nat };
    #tabNotOpen : { tabId : Nat; state : Text };
    #courseBound : { course : Nat; max : Nat };
    #noLines;
    #tooManyLines : { lines : Nat; max : Nat };
    #lineQuantityZero : { ordinal : Nat };
    #quantityBound : { ordinal : Nat; quantity : Nat; max : Nat };
    #noSuchCategory : { categoryId : Nat };
    /// No live price on the shop's list.
    #notOnTheMenu : { categoryId : Nat };
    #noSuchCourse : { tabId : Nat; course : Nat };
    /// The kitchen has it: no more lines, and no cancelling the tab while any stands.
    #courseSent : { course : Nat };
    /// A line the kitchen has is taken off - a comp - only by somebody other than the one who ordered it.
    #ownLineOnSentCourse : { orderedBy : Principal };
    #courseEmpty : { course : Nat };
    /// A bill is settled only when every course has gone to the kitchen.
    #courseNotSent : { course : Nat };
    #noSuchLine : { lineId : Nat };
    #lineVoided : { lineId : Nat };
    #nothingOrdered : { tabId : Nat };
    #sharesBound : { shares : Nat; max : Nat };
    /// One weight per share, each of something.
    #weightsDisagree : { weights : Nat; shares : Nat };
    #weightBound : { ordinal : Nat; weight : Nat; max : Nat };
    #moneyBound : { what : Text; value : Nat; max : Nat };
    #shareTenderShort : { ordinal : Nat; share : Nat; tendered : Nat };
    #cardOverShare : { ordinal : Nat; share : Nat; card : Nat };
    /// The till's own refusal: of the pricing, or of the sale.
    #pos : PFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#codeDoesNotFit { code; max }) "code \"" # code # "\" is empty or exceeds " # Nat.toText(max) # " bytes";
      case (#noSuchShop { shopId }) "no shop " # Nat.toText(shopId);
      case (#shopRetired { shopId }) "shop " # Nat.toText(shopId) # " is retired";
      case (#seatsBound { seats; max }) Nat.toText(seats) # " seats is not between 1 and " # Nat.toText(max);
      case (#noSuchTable { tableId }) "no table " # Nat.toText(tableId);
      case (#tableRetired { tableId }) "table " # Nat.toText(tableId) # " is retired";
      case (#tableTaken { tableId; tabId }) "table " # Nat.toText(tableId) # " has tab " # Nat.toText(tabId) # " open";
      case (#noSuchSession { sessionId }) "no till session " # Nat.toText(sessionId);
      case (#sessionNotOpen { sessionId; state }) "till session " # Nat.toText(sessionId) # " is " # state # ", not open";
      case (#tableNotOfShop { tableId; shopId }) "table " # Nat.toText(tableId) # " is not shop " # Nat.toText(shopId) # "'s";
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#coversBound { covers; seats }) Nat.toText(covers) # " covers at a table of " # Nat.toText(seats) # " seats";
      case (#noSuchTab { tabId }) "no tab " # Nat.toText(tabId);
      case (#tabNotOpen { tabId; state }) "tab " # Nat.toText(tabId) # " is " # state # ", not open";
      case (#courseBound { course; max }) "course " # Nat.toText(course) # " is not between 1 and " # Nat.toText(max);
      case (#noLines) "a course with no lines";
      case (#tooManyLines { lines; max }) Nat.toText(lines) # " lines exceed the " # Nat.toText(max) # " allowed";
      case (#lineQuantityZero { ordinal }) "line " # Nat.toText(ordinal) # " has no quantity";
      case (#quantityBound { ordinal; quantity; max }) "line " # Nat.toText(ordinal) # " wants " # Nat.toText(quantity) # ", beyond " # Nat.toText(max);
      case (#noSuchCategory { categoryId }) "no category " # Nat.toText(categoryId);
      case (#notOnTheMenu { categoryId }) "category " # Nat.toText(categoryId) # " is not on this shop's list";
      case (#noSuchCourse { tabId; course }) "tab " # Nat.toText(tabId) # " has no course " # Nat.toText(course);
      case (#courseSent { course }) "course " # Nat.toText(course) # " has gone to the kitchen";
      case (#ownLineOnSentCourse { orderedBy }) Principal.toText(orderedBy) # " ordered this line and the kitchen has it; somebody else takes it off";
      case (#courseEmpty { course }) "course " # Nat.toText(course) # " has nothing on it";
      case (#courseNotSent { course }) "course " # Nat.toText(course) # " has not gone to the kitchen";
      case (#noSuchLine { lineId }) "no line " # Nat.toText(lineId);
      case (#lineVoided { lineId }) "line " # Nat.toText(lineId) # " is voided";
      case (#nothingOrdered { tabId }) "tab " # Nat.toText(tabId) # " has nothing on it";
      case (#sharesBound { shares; max }) Nat.toText(shares) # " shares is not between 1 and " # Nat.toText(max);
      case (#weightsDisagree { weights; shares }) Nat.toText(weights) # " weight(s) for " # Nat.toText(shares) # " share(s)";
      case (#weightBound { ordinal; weight; max }) "share " # Nat.toText(ordinal) # " weighs " # Nat.toText(weight) # ", not between 1 and " # Nat.toText(max);
      case (#moneyBound { what; value; max }) what # " of " # Nat.toText(value) # " exceeds " # Nat.toText(max);
      case (#shareTenderShort { ordinal; share; tendered }) "share " # Nat.toText(ordinal) # " of " # Nat.toText(share) # " met with " # Nat.toText(tendered);
      case (#cardOverShare { ordinal; share; card }) "share " # Nat.toText(ordinal) # " of " # Nat.toText(share) # " paid " # Nat.toText(card) # " by card: change is given in cash";
      case (#pos r) PFold.refusalText(r);
    }
  };

  public type Stores = {
    var tables : RowStore.Store;
    var tabs : RowStore.Store;
    var courses : RowStore.Store;
    var lines : RowStore.Store;
    var shares : RowStore.Store;
    var nextTableId : Nat;
    var nextTabId : Nat;
    var nextCourseId : Nat;
    var nextLineId : Nat;
    var nextShareId : Nat;
  };

  public func newStores() : Stores {
    {
      var tables = RowStore.newStore<RR.Table>(RR.table);
      var tabs = RowStore.newStore<RR.Tab>(RR.tab);
      var courses = RowStore.newStore<RR.Course>(RR.course);
      var lines = RowStore.newStore<RR.Line>(RR.line);
      var shares = RowStore.newStore<RR.Share>(RR.share);
      var nextTableId = 1;
      var nextTabId = 1;
      var nextCourseId = 1;
      var nextLineId = 1;
      var nextShareId = 1;
    }
  };

  public type Ctx = {
    rst : Stores;
    pos : PFold.Stores;
    ord : { var categories : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    /// THE BILL, priced by the till's own list through the till's own pricing: nothing written.
    quote : (Nat, Nat, [PF.SaleLineFacts]) -> { #ok : PFold.Priced; #err : PFold.Refusal };
    /// THE SALE, rung up through the shop fold by the session's cashier.
    ringUp : PF.SaleFacts -> PFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_SEATS : Nat = 1_000;
  public let MAX_COURSES : Nat = 12;
  public let MAX_COURSE_LINES : Nat = 50;
  /// Lines standing on one tab: what one sale may carry.
  public let MAX_TAB_LINES : Nat = 200;
  public let MAX_LINE_QUANTITY : Nat = 1_000_000_000;
  public let MAX_SHARES : Nat = 50;
  public let MAX_WEIGHT : Nat = 1_000_000;
  public let MAX_MONEY : Nat = 1_000_000_000_000_000;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func all<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for (row in pg.rows.vals()) List.add(out, row);
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  public func tabStateText(s : E.TabState) : Text { switch (s) { case (#open) "open"; case (#paid) "paid"; case (#cancelled) "cancelled" } };
  public func courseStateText(s : E.CourseState) : Text { switch (s) { case (#ordered) "ordered"; case (#sent) "sent" } };
  public func ruleText(r : E.SplitRule) : Text { switch (r) { case (#evenly) "evenly"; case (#byWeights) "by-weights" } };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  /// THE SPLIT, by the largest-remainder rule: every share its whole part of total × weight over the
  /// weights' sum; the minor units left over, one each, to the shares with the largest remainders,
  /// an earlier share before a later one where they tie. The shares sum to the total. The reader
  /// builds the same.
  public func split(total : Nat, weights : [Nat]) : [Nat] {
    let n = weights.size();
    var sum : Nat = 0;
    for (w in weights.vals()) sum += w;
    if (n == 0 or sum == 0) return [];
    let base = Array.tabulate<Nat>(n, func(i) { total * weights[i] / sum });
    let rem = Array.tabulate<Nat>(n, func(i) { total * weights[i] % sum });
    var given : Nat = 0;
    for (b in base.vals()) given += b;
    var leftover : Nat = total - given;
    let extra = Array.toVarArray<Nat>(Array.repeat<Nat>(0, n));
    while (leftover > 0) {
      var pick = 0;
      var found = false;
      var i = 0;
      while (i < n) {
        if (extra[i] == 0 and (not found or rem[i] > rem[pick])) { pick := i; found := true };
        i += 1;
      };
      extra[pick] := 1;
      leftover -= 1;
    };
    Array.tabulate<Nat>(n, func(i) { base[i] + extra[i] })
  };

  /// The lines standing on a tab, one per category, in order of first appearance: the sale's lines.
  public func billLines(st : Stores, tabId : Nat) : [PF.SaleLineFacts] {
    let out = List.empty<PF.SaleLineFacts>();
    for ((_, l) in linesOf(st, tabId).vals()) {
      if (not l.isVoided) {
        var seen = false;
        var i = 0;
        while (i < List.size(out)) {
          let x = List.at(out, i);
          if (x.categoryId == l.categoryId) { List.put(out, i, { categoryId = x.categoryId; quantity = x.quantity + l.quantity }); seen := true };
          i += 1;
        };
        if (not seen) List.add(out, { categoryId = l.categoryId; quantity = l.quantity });
      };
    };
    List.toArray(out)
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func tableByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, RR.Table) {
    let k = AR.accountCodeKey(companyId, code);
    one<RR.Table>(RowStore.page<RR.Table>(st.tables, RR.table, "by_code_one", k, k, null, 1))
  };

  /// The table's open tab, if there is one.
  public func openTabOf(st : Stores, tableId : Nat) : ?(Nat, RR.Tab) {
    let k = PR.shopKey(tableId);
    one<RR.Tab>(RowStore.page<RR.Tab>(st.tabs, RR.tab, "by_table_open_one", k, k, null, 1))
  };

  public func courseOf(st : Stores, tabId : Nat, ordinal : Nat) : ?(Nat, RR.Course) {
    let k = PR.pairKey(tabId, ordinal);
    one<RR.Course>(RowStore.page<RR.Course>(st.courses, RR.course, "by_tab_ordinal_one", k, k, null, 1))
  };

  public func coursesOf(st : Stores, tabId : Nat) : [(Nat, RR.Course)] {
    let (lo, hi) = PR.pairRange(tabId);
    all<RR.Course>(st.courses, RR.course, "by_tab", lo, hi)
  };

  public func linesOf(st : Stores, tabId : Nat) : [(Nat, RR.Line)] {
    let (lo, hi) = PR.pairRange(tabId);
    all<RR.Line>(st.lines, RR.line, "by_tab", lo, hi)
  };

  public func sharesOf(st : Stores, tabId : Nat) : [(Nat, RR.Share)] {
    let (lo, hi) = PR.pairRange(tabId);
    all<RR.Share>(st.shares, RR.share, "by_tab", lo, hi)
  };

  func activeShop(c : Ctx, companyId : Nat, shopId : Nat) : { #ok : PR.Shop; #err : Refusal } {
    let ?x = RowStore.get<PR.Shop>(c.pos.shops, PR.shop, shopId) else return #err(#noSuchShop { shopId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (not x.isActive) return #err(#shopRetired { shopId });
    #ok(x)
  };

  func activeTable(c : Ctx, companyId : Nat, tableId : Nat) : { #ok : RR.Table; #err : Refusal } {
    let ?t = RowStore.get<RR.Table>(c.rst.tables, RR.table, tableId) else return #err(#noSuchTable { tableId });
    if (t.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = t.companyId });
    if (not t.isActive) return #err(#tableRetired { tableId });
    #ok(t)
  };

  func openTab(c : Ctx, companyId : Nat, tabId : Nat) : { #ok : RR.Tab; #err : Refusal } {
    let ?x = RowStore.get<RR.Tab>(c.rst.tabs, RR.tab, tabId) else return #err(#noSuchTab { tabId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state != #open) return #err(#tabNotOpen { tabId; state = tabStateText(x.state) });
    #ok(x)
  };

  // ── the table ───────────────────────────────────────────────────────────────

  /// Declare, or change, a table by its code. Declared again, a retired table stands again.
  public func declareTable(c : Ctx, f : RF.TableFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (activeShop(c, f.companyId, f.shopId)) { case (#err e) return #err(e); case (#ok _) {} };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "table" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (Text.size(f.code) == 0) return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (f.seats == 0 or f.seats > MAX_SEATS) return #err(#seatsBound { seats = f.seats; max = MAX_SEATS });
    switch (tableByCode(c.rst, f.companyId, code)) {
      case (?(id, t)) {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        RowStore.put<RR.Table>(c.rst.tables, RR.table, id, { t with shopId = f.shopId; name; seats = f.seats; isActive = true; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = c.rst.nextTableId;
        RowStore.put<RR.Table>(c.rst.tables, RR.table, id, { companyId = f.companyId; shopId = f.shopId; code; name; seats = f.seats; isActive = true; lastBlock = c.block });
        c.rst.nextTableId += 1;
        #ok([id])
      };
    }
  };

  /// Retire a table: it takes no tab. One with a tab open is not retired.
  public func retireTable(c : Ctx, companyId : Nat, tableId : Nat) : Outcome {
    let t = switch (activeTable(c, companyId, tableId)) { case (#err e) return #err(e); case (#ok t) t };
    switch (openTabOf(c.rst, tableId)) { case (?(tabId, _)) return #err(#tableTaken { tableId; tabId }); case null {} };
    RowStore.put<RR.Table>(c.rst.tables, RR.table, tableId, { t with isActive = false; lastBlock = c.block });
    #ok([tableId])
  };

  // ── the tab ─────────────────────────────────────────────────────────────────

  /// A member opens a tab at a table of the session's shop, for covers the table seats.
  public func openTabAt(c : Ctx, f : RF.TabFacts) : Outcome {
    let ?s = RowStore.get<PR.Session>(c.pos.sessions, PR.session, f.sessionId) else return #err(#noSuchSession { sessionId = f.sessionId });
    if (s.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = s.companyId });
    if (s.state != #open) return #err(#sessionNotOpen { sessionId = f.sessionId; state = PFold.stateText(s.state) });
    let t = switch (activeTable(c, f.companyId, f.tableId)) { case (#err e) return #err(e); case (#ok t) t };
    if (t.shopId != s.shopId) return #err(#tableNotOfShop { tableId = f.tableId; shopId = s.shopId });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (f.covers == 0 or f.covers > t.seats) return #err(#coversBound { covers = f.covers; seats = t.seats });
    switch (openTabOf(c.rst, f.tableId)) { case (?(tabId, _)) return #err(#tableTaken { tableId = f.tableId; tabId }); case null {} };
    let id = c.rst.nextTabId;
    RowStore.put<RR.Tab>(c.rst.tabs, RR.tab, id, {
      companyId = f.companyId; sessionId = f.sessionId; tableId = f.tableId; state = #open; covers = f.covers; openedBy = c.caller; openedDay = c.day;
      courses = 0; liveLines = 0; saleId = 0; orderId = 0; rule = #evenly; ways = 0; amountTotal = 0; lastBlock = c.block });
    c.rst.nextTabId += 1;
    #ok([id])
  };

  /// Lines ordered against a tab under a course. Each a category on the shop's list, at a quantity;
  /// a course that has gone to the kitchen takes no more.
  public func orderCourse(c : Ctx, f : RF.CourseFacts) : Outcome {
    let x = switch (openTab(c, f.companyId, f.tabId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (f.course == 0 or f.course > MAX_COURSES) return #err(#courseBound { course = f.course; max = MAX_COURSES });
    if (f.lines.size() == 0) return #err(#noLines);
    if (f.lines.size() > MAX_COURSE_LINES) return #err(#tooManyLines { lines = f.lines.size(); max = MAX_COURSE_LINES });
    if (x.liveLines + f.lines.size() > MAX_TAB_LINES) return #err(#tooManyLines { lines = x.liveLines + f.lines.size(); max = MAX_TAB_LINES });
    let ?s = RowStore.get<PR.Session>(c.pos.sessions, PR.session, x.sessionId) else return #err(#noSuchSession { sessionId = x.sessionId });
    var ordinal = 1;
    for (l in f.lines.vals()) {
      if (l.quantity == 0) return #err(#lineQuantityZero { ordinal });
      if (l.quantity > MAX_LINE_QUANTITY) return #err(#quantityBound { ordinal; quantity = l.quantity; max = MAX_LINE_QUANTITY });
      let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, l.categoryId) else return #err(#noSuchCategory { categoryId = l.categoryId });
      if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
      switch (PFold.priceOf(c.pos, s.shopId, l.categoryId)) {
        case (?(_, p)) { if (not p.isActive) return #err(#notOnTheMenu { categoryId = l.categoryId }) };
        case null return #err(#notOnTheMenu { categoryId = l.categoryId });
      };
      ordinal += 1;
    };
    let existing = courseOf(c.rst, f.tabId, f.course);
    switch (existing) { case (?(_, k)) { if (k.state == #sent) return #err(#courseSent { course = f.course }) }; case null {} };
    // nothing left that can refuse
    let ids = List.empty<Nat>();
    List.add(ids, f.tabId);
    for (l in f.lines.vals()) {
      let id = c.rst.nextLineId;
      RowStore.put<RR.Line>(c.rst.lines, RR.line, id, { tabId = f.tabId; course = f.course; categoryId = l.categoryId; quantity = l.quantity; isVoided = false; orderedBy = c.caller; lastBlock = c.block });
      c.rst.nextLineId += 1;
      List.add(ids, id);
    };
    var courses = x.courses;
    switch (existing) {
      case (?(kid, k)) { RowStore.put<RR.Course>(c.rst.courses, RR.course, kid, { k with lines = k.lines + f.lines.size(); lastBlock = c.block }) };
      case null {
        RowStore.put<RR.Course>(c.rst.courses, RR.course, c.rst.nextCourseId, { tabId = f.tabId; ordinal = f.course; state = #ordered; lines = f.lines.size(); sentBy = c.caller; lastBlock = c.block });
        c.rst.nextCourseId += 1;
        courses += 1;
      };
    };
    RowStore.put<RR.Tab>(c.rst.tabs, RR.tab, f.tabId, { x with courses; liveLines = x.liveLines + f.lines.size(); lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  /// A line taken off: by any member before its course went to the kitchen; once the kitchen has it,
  /// only by a member other than the one who ordered it - a comp, with the second person's name on
  /// the block.
  public func voidLine(c : Ctx, companyId : Nat, tabId : Nat, lineId : Nat) : Outcome {
    let x = switch (openTab(c, companyId, tabId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let ?l = RowStore.get<RR.Line>(c.rst.lines, RR.line, lineId) else return #err(#noSuchLine { lineId });
    if (l.tabId != tabId) return #err(#noSuchLine { lineId });
    if (l.isVoided) return #err(#lineVoided { lineId });
    let ?(kid, k) = courseOf(c.rst, tabId, l.course) else return #err(#noSuchCourse { tabId; course = l.course });
    if (k.state == #sent and c.caller == l.orderedBy) return #err(#ownLineOnSentCourse { orderedBy = l.orderedBy });
    RowStore.put<RR.Line>(c.rst.lines, RR.line, lineId, { l with isVoided = true; lastBlock = c.block });
    RowStore.put<RR.Course>(c.rst.courses, RR.course, kid, { k with lines = if (k.lines == 0) 0 else k.lines - 1; lastBlock = c.block });
    RowStore.put<RR.Tab>(c.rst.tabs, RR.tab, tabId, { x with liveLines = if (x.liveLines == 0) 0 else x.liveLines - 1; lastBlock = c.block });
    #ok([lineId])
  };

  /// A course sent to the kitchen, once, with something on it.
  public func sendCourse(c : Ctx, companyId : Nat, tabId : Nat, course : Nat) : Outcome {
    switch (openTab(c, companyId, tabId)) { case (#err e) return #err(e); case (#ok _) {} };
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let ?(kid, k) = courseOf(c.rst, tabId, course) else return #err(#noSuchCourse { tabId; course });
    if (k.state == #sent) return #err(#courseSent { course });
    if (k.lines == 0) return #err(#courseEmpty { course });
    RowStore.put<RR.Course>(c.rst.courses, RR.course, kid, { k with state = #sent; sentBy = c.caller; lastBlock = c.block });
    #ok([kid])
  };

  /// A tab with nothing the kitchen has standing is cancelled; the table is free.
  public func cancelTab(c : Ctx, companyId : Nat, tabId : Nat) : Outcome {
    let x = switch (openTab(c, companyId, tabId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    for ((_, k) in coursesOf(c.rst, tabId).vals()) { if (k.state == #sent and k.lines > 0) return #err(#courseSent { course = k.ordinal }) };
    RowStore.put<RR.Tab>(c.rst.tabs, RR.tab, tabId, { x with state = #cancelled; lastBlock = c.block });
    #ok([tabId])
  };

  /// THE BILL SETTLED: every course sent, the lines standing priced by the list through the till,
  /// the total split by the rule into as many shares as tenders, every share's tender held to it,
  /// and the whole rung up as one sale through the shop fold by the session's cashier.
  public func settleTab(c : Ctx, f : RF.SettleFacts) : Outcome {
    let x = switch (openTab(c, f.companyId, f.tabId)) { case (#err e) return #err(e); case (#ok x) x };
    if (x.liveLines == 0) return #err(#nothingOrdered { tabId = f.tabId });
    for ((_, k) in coursesOf(c.rst, f.tabId).vals()) { if (k.state != #sent and k.lines > 0) return #err(#courseNotSent { course = k.ordinal }) };
    let n = f.tenders.size();
    if (n == 0 or n > MAX_SHARES) return #err(#sharesBound { shares = n; max = MAX_SHARES });
    let weights : [Nat] = switch (f.rule) {
      case (#evenly) Array.tabulate<Nat>(n, func(_) { 1 });
      case (#byWeights) {
        if (f.weights.size() != n) return #err(#weightsDisagree { weights = f.weights.size(); shares = n });
        var i = 0;
        for (w in f.weights.vals()) { if (w == 0 or w > MAX_WEIGHT) return #err(#weightBound { ordinal = i + 1; weight = w; max = MAX_WEIGHT }); i += 1 };
        f.weights
      };
    };
    var totalCash : Nat = 0;
    var totalCard : Nat = 0;
    for (t in f.tenders.vals()) {
      if (t.cash > MAX_MONEY) return #err(#moneyBound { what = "cash tendered"; value = t.cash; max = MAX_MONEY });
      if (t.card > MAX_MONEY) return #err(#moneyBound { what = "a card payment"; value = t.card; max = MAX_MONEY });
      totalCash += t.cash;
      totalCard += t.card;
    };
    let ?s = RowStore.get<PR.Session>(c.pos.sessions, PR.session, x.sessionId) else return #err(#noSuchSession { sessionId = x.sessionId });
    let bill = billLines(c.rst, f.tabId);
    // ── the bill priced by the list, through the till ──
    let priced = switch (c.quote(f.companyId, s.shopId, bill)) { case (#err e) return #err(#pos e); case (#ok p) p };
    let total = priced.untaxed + priced.tax;
    // ── the split, and every share's tender ──
    let shares = split(total, weights);
    var i = 0;
    while (i < n) {
      let t = f.tenders[i];
      if (t.card > shares[i]) return #err(#cardOverShare { ordinal = i + 1; share = shares[i]; card = t.card });
      if (t.cash + t.card < shares[i]) return #err(#shareTenderShort { ordinal = i + 1; share = shares[i]; tendered = t.cash + t.card });
      i += 1;
    };
    // ── THE SALE, through the shop fold, which refuses whole or succeeds whole ──
    let rung = switch (c.ringUp({ companyId = f.companyId; sessionId = x.sessionId; lines = bill; cashTendered = totalCash; cardTendered = totalCard })) {
      case (#err e) return #err(#pos e); case (#ok ids) ids };
    // nothing left that can refuse: the shares and the tab
    let ids = List.empty<Nat>();
    List.add(ids, f.tabId);
    List.add(ids, rung[0]);
    List.add(ids, rung[1]);
    i := 0;
    while (i < n) {
      let t = f.tenders[i];
      let id = c.rst.nextShareId;
      RowStore.put<RR.Share>(c.rst.shares, RR.share, id, { tabId = f.tabId; ordinal = i + 1; weight = weights[i]; amount = shares[i]; cash = t.cash; card = t.card; change = t.cash + t.card - shares[i]; lastBlock = c.block });
      c.rst.nextShareId += 1;
      List.add(ids, id);
      i += 1;
    };
    RowStore.put<RR.Tab>(c.rst.tabs, RR.tab, f.tabId, { x with state = #paid; saleId = rung[0]; orderId = rung[1]; rule = f.rule; ways = n; amountTotal = total; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

}
