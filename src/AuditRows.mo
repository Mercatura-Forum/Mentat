/// AuditRows.mo - the index of the log by caller and by company: two tables, each one entry per accepted block.
///
/// THE BLOCK IS THE RECORD. An entry carries what finds a block - whose act it was, in which company, which family
/// - and its height; what the act said is in the block, read by `blockBytes(height)` and checked against the
/// certified tip. So the index is a finding aid and never the evidence.
///
/// THE KEY IS THE ORDER. An entry's id is its key read as one big-endian number: the caller's principal field
/// then the block's height, or the company's id then the height. One caller's entries, or one company's, are
/// therefore one contiguous range of ids in height order, and a page of them is a range read from a cursor.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import F "Fields";
import W "Widths";

module {

  /// An entry under its caller: the command's tag and the company it acted in (0 for an act of no company).
  public type CallerEntry = { tag : Nat; company : Nat };
  /// An entry under its company: the command's tag and its caller.
  public type CompanyEntry = { tag : Nat; caller : Principal };

  /// How many heights a key's height field holds: 256 to the power of `W.BLOCK` (six bytes), a constant because a
  /// module's values are static; the audit battery holds the two to each other.
  public let HEIGHTS : Nat = 281_474_976_710_656;

  /// The largest height a key holds.
  public let MAX_HEIGHT : Nat = 281_474_976_710_655;

  func natOf(bytes : [Nat8]) : Nat {
    var n = 0;
    for (b in bytes.vals()) { n := n * 256 + Nat8.toNat(b) };
    n
  };

  /// The id of the entry of `caller`'s act at `height`.
  public func callerKey(caller : Principal, height : Nat) : Nat {
    natOf(Blob.toArray(F.principalField(caller))) * HEIGHTS + height
  };

  /// The id of the entry of an act in `company` at `height`.
  public func companyKey(company : Nat, height : Nat) : Nat { company * HEIGHTS + height };

  /// The height an entry's id names, under either table.
  public func heightOf(id : Nat) : Nat { id % HEIGHTS };

  /// The caller an entry under its caller names.
  public func callerOf(id : Nat) : Principal {
    var n = id / HEIGHTS;
    let field = Array.tabulate<Nat8>(W.PRINCIPAL, func(_) { 0 });
    let bytes = Array.toVarArray<Nat8>(field);
    var i = W.PRINCIPAL;
    while (i > 0) { i -= 1; bytes[i] := Nat8.fromNat(n % 256); n /= 256 };
    F.getPrincipal(Array.fromVarArray<Nat8>(bytes), 0)
  };

  func encodeCaller(x : CallerEntry) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.tag, W.COMMAND_TAG);
    SR.putNat(w, x.company, W.COMPANY);
    SR.done(w, W.AUDIT_CALLER_ROW)
  };

  func decodeCaller(r : [Nat8]) : CallerEntry {
    { tag = SR.getNat(r, 0, W.COMMAND_TAG); company = SR.getNat(r, W.COMMAND_TAG, W.COMPANY) }
  };

  func encodeCompany(x : CompanyEntry) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.tag, W.COMMAND_TAG);
    F.putPrincipal(w, x.caller);
    SR.done(w, W.AUDIT_COMPANY_ROW)
  };

  func decodeCompany(r : [Nat8]) : CompanyEntry {
    { tag = SR.getNat(r, 0, W.COMMAND_TAG); caller = F.getPrincipal(r, W.COMMAND_TAG) }
  };

  public let byCaller : RowStore.Decl<CallerEntry> = {
    table = "audit_by_caller";
    idBytes = W.AUDIT_CALLER_KEY;
    rowBytes = W.AUDIT_CALLER_ROW;
    encode = encodeCaller;
    decode = decodeCaller;
    indexes = [];
  };

  public let byCompany : RowStore.Decl<CompanyEntry> = {
    table = "audit_by_company";
    idBytes = W.AUDIT_COMPANY_KEY;
    rowBytes = W.AUDIT_COMPANY_ROW;
    encode = encodeCompany;
    decode = decodeCompany;
    indexes = [];
  };
}
