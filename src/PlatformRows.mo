/// PlatformRows.mo - the platform operator: one row, the principal the log names as the operator of the whole
/// contract, and the principal it has offered the role to, if any.
///
/// The table holds no row until the operator is claimed, so "no operator" is the empty table every migration
/// fills at genesis, and the row, once written, is always row 1.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import F "Fields";
import W "Widths";

module {

  /// The only row the table ever holds.
  public let ROW_ID : Nat = 1;

  public type Platform = {
    /// the principal that holds the role: the first claimant, or the last principal to accept an offer
    operator : Principal;
    /// the block at which it took the role
    sinceBlock : Nat;
    /// the principal the operator has offered the role to; the role moves only when that principal accepts
    offered : ?Principal;
    /// the block of the standing offer, or of the last one withdrawn or taken; 0 before the first
    offeredBlock : Nat;
    lastBlock : Nat;
  };

  func encodePlatform(x : Platform) : Blob {
    let w = SR.buf();
    F.putPrincipal(w, x.operator);
    SR.putNat(w, x.sinceBlock, W.BLOCK);
    switch (x.offered) {
      case (?p) { SR.putByte(w, 1); F.putPrincipal(w, p) };
      // no offer: the flag says so, and the principal's bytes are the operator's, never read
      case null { SR.putByte(w, 0); F.putPrincipal(w, x.operator) };
    };
    SR.putNat(w, x.offeredBlock, W.BLOCK);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PLATFORM_ROW)
  };

  func decodePlatform(r : [Nat8]) : Platform {
    var o = 0;
    let operator = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let sinceBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let hasOffer = r[o] == 1; o += W.FLAG;
    let offeredP = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let offeredBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { operator; sinceBlock; offered = if (hasOffer) ?offeredP else null; offeredBlock; lastBlock }
  };

  public let platform : RowStore.Decl<Platform> = {
    table = "platform";
    idBytes = W.ID;
    rowBytes = W.PLATFORM_ROW;
    encode = encodePlatform;
    decode = decodePlatform;
    indexes = [];
  };
}
