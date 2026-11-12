/// RstRows.mo - the restaurant tables: the tables of a shop, the tabs opened at them, the courses of
/// a tab, the lines of a course, and the shares a settled bill was split into.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  // ════════════════════════════════════════════════════════════════════════════
  //  The table
  // ════════════════════════════════════════════════════════════════════════════

  public type Table = {
    companyId : Nat;
    shopId : Nat;
    code : Blob;
    name : TA.Ref;
    seats : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeTable(x : Table) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.shopId, W.ID);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    SR.putNat(w, x.seats, W.ID);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RST_TABLE_ROW)
  };

  func decodeTable(r : [Nat8]) : Table {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let shopId = SR.getNat(r, o, W.ID); o += W.ID;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let seats = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; shopId; code; name; seats; isActive; lastBlock }
  };

  public let table : RowStore.Decl<Table> = {
    table = "rst_table";
    idBytes = W.ID;
    rowBytes = W.RST_TABLE_ROW;
    encode = encodeTable;
    decode = decodeTable;
    indexes = [
      { name = "by_code_one"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Table) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_shop"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Table) : ?Blob { ?PR.pairKey(x.shopId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The tab
  // ════════════════════════════════════════════════════════════════════════════

  public type Tab = {
    companyId : Nat;
    sessionId : Nat;
    tableId : Nat;
    state : E.TabState;
    covers : Nat;
    openedBy : Principal;
    openedDay : Nat;
    /// Courses ordered, and lines standing (ordered and not voided).
    courses : Nat;
    liveLines : Nat;
    /// The sale the settled bill became at the till, and its order; 0 until paid.
    saleId : Nat;
    orderId : Nat;
    /// The rule the bill was split by, into so many shares; the bill's total as rung up.
    rule : E.SplitRule;
    ways : Nat;
    amountTotal : Nat;
    lastBlock : Nat;
  };

  func encodeTab(x : Tab) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.sessionId, W.ID);
    SR.putNat(w, x.tableId, W.ID);
    SR.putByte(w, E.tabStateByte(x.state));
    SR.putNat(w, x.covers, W.ID);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.openedDay, W.DAY);
    SR.putNat(w, x.courses, W.ID);
    SR.putNat(w, x.liveLines, W.ID);
    SR.putNat(w, x.saleId, W.ID);
    SR.putNat(w, x.orderId, W.ID);
    SR.putByte(w, E.splitRuleByte(x.rule));
    SR.putNat(w, x.ways, W.ID);
    SR.putNat(w, x.amountTotal, W.MONEY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RST_TAB_ROW)
  };

  func decodeTab(r : [Nat8]) : Tab {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let sessionId = SR.getNat(r, o, W.ID); o += W.ID;
    let tableId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.tabStateOf(r[o]) else Runtime.trap("rst_tab: unknown state byte"); o += W.ENUM;
    let covers = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let openedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let courses = SR.getNat(r, o, W.ID); o += W.ID;
    let liveLines = SR.getNat(r, o, W.ID); o += W.ID;
    let saleId = SR.getNat(r, o, W.ID); o += W.ID;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?rule = E.splitRuleOf(r[o]) else Runtime.trap("rst_tab: unknown rule byte"); o += W.ENUM;
    let ways = SR.getNat(r, o, W.ID); o += W.ID;
    let amountTotal = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; sessionId; tableId; state; covers; openedBy; openedDay; courses; liveLines; saleId; orderId; rule; ways; amountTotal; lastBlock }
  };

  public let tab : RowStore.Decl<Tab> = {
    table = "rst_tab";
    idBytes = W.ID;
    rowBytes = W.RST_TAB_ROW;
    encode = encodeTab;
    decode = decodeTab;
    indexes = [
      { name = "by_session"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Tab) : ?Blob { ?PR.pairKey(x.sessionId, id) } },
      // ONE OPEN TAB PER TABLE: a paid or cancelled tab frees it
      { name = "by_table_open_one"; keyBytes = PR.SHOP_KEY_BYTES;
        keyOf = func(_id : Nat, x : Tab) : ?Blob { if (x.state == #open) ?PR.shopKey(x.tableId) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The course
  // ════════════════════════════════════════════════════════════════════════════

  public type Course = {
    tabId : Nat;
    ordinal : Nat;
    state : E.CourseState;
    /// Lines standing under it.
    lines : Nat;
    sentBy : Principal;
    lastBlock : Nat;
  };

  func encodeCourse(x : Course) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.tabId, W.ID);
    SR.putNat(w, x.ordinal, W.ID);
    SR.putByte(w, E.courseStateByte(x.state));
    SR.putNat(w, x.lines, W.ID);
    F.putPrincipal(w, x.sentBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RST_COURSE_ROW)
  };

  func decodeCourse(r : [Nat8]) : Course {
    var o = 0;
    let tabId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.courseStateOf(r[o]) else Runtime.trap("rst_course: unknown state byte"); o += W.ENUM;
    let lines = SR.getNat(r, o, W.ID); o += W.ID;
    let sentBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { tabId; ordinal; state; lines; sentBy; lastBlock }
  };

  public let course : RowStore.Decl<Course> = {
    table = "rst_course";
    idBytes = W.ID;
    rowBytes = W.RST_COURSE_ROW;
    encode = encodeCourse;
    decode = decodeCourse;
    indexes = [
      { name = "by_tab_ordinal_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : Course) : ?Blob { ?PR.pairKey(x.tabId, x.ordinal) } },
      { name = "by_tab"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Course) : ?Blob { ?PR.pairKey(x.tabId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The line
  // ════════════════════════════════════════════════════════════════════════════

  public type Line = {
    tabId : Nat;
    course : Nat;
    categoryId : Nat;
    quantity : Nat;
    /// Taken off before its course was sent; charged no more.
    isVoided : Bool;
    orderedBy : Principal;
    lastBlock : Nat;
  };

  func encodeLine(x : Line) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.tabId, W.ID);
    SR.putNat(w, x.course, W.ID);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putBool(w, x.isVoided);
    F.putPrincipal(w, x.orderedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RST_LINE_ROW)
  };

  func decodeLine(r : [Nat8]) : Line {
    var o = 0;
    let tabId = SR.getNat(r, o, W.ID); o += W.ID;
    let course = SR.getNat(r, o, W.ID); o += W.ID;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let isVoided = SR.getBool(r, o); o += W.FLAG;
    let orderedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { tabId; course; categoryId; quantity; isVoided; orderedBy; lastBlock }
  };

  public let line : RowStore.Decl<Line> = {
    table = "rst_line";
    idBytes = W.ID;
    rowBytes = W.RST_LINE_ROW;
    encode = encodeLine;
    decode = decodeLine;
    indexes = [
      { name = "by_tab"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Line) : ?Blob { ?PR.pairKey(x.tabId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The share
  // ════════════════════════════════════════════════════════════════════════════

  /// One share of a settled bill: its weight under the rule, what it came to, and how it was paid.
  public type Share = {
    tabId : Nat;
    ordinal : Nat;
    weight : Nat;
    amount : Nat;
    cash : Nat;
    card : Nat;
    change : Nat;
    lastBlock : Nat;
  };

  func encodeShare(x : Share) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.tabId, W.ID);
    SR.putNat(w, x.ordinal, W.ID);
    SR.putNat(w, x.weight, W.ID);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.cash, W.MONEY);
    SR.putNat(w, x.card, W.MONEY);
    SR.putNat(w, x.change, W.MONEY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RST_SHARE_ROW)
  };

  func decodeShare(r : [Nat8]) : Share {
    var o = 0;
    let tabId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ID); o += W.ID;
    let weight = SR.getNat(r, o, W.ID); o += W.ID;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let cash = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let card = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let change = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { tabId; ordinal; weight; amount; cash; card; change; lastBlock }
  };

  public let share : RowStore.Decl<Share> = {
    table = "rst_share";
    idBytes = W.ID;
    rowBytes = W.RST_SHARE_ROW;
    encode = encodeShare;
    decode = decodeShare;
    indexes = [
      { name = "by_tab"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Share) : ?Blob { ?PR.pairKey(x.tabId, id) } },
    ];
  };

}
