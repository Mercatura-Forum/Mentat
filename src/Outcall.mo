/// Outcall.mo - the shape of an outbound HTTPS request, and the one rule every one of them obeys.
///
/// EVERY OUTBOUND REQUEST THIS PRODUCT MAKES IS UNREPLICATED. In the substrate's
/// replicated mode - which is what `is_replicated = null` selects - every node of the subnet issues
/// the request independently and the provider receives one copy per validator. The received tree
/// passes `null` at both of its outcall sites: `crm.mo:923`, which SENDS MAIL, and `erp.mo:1182`,
/// which FILES A TAX DOCUMENT. Every validator of the subnet therefore sends the campaign
/// and files the invoice, once each.
///
/// The type lives here so both builders share it and `tools/outcall_and_secrets.sh` has one shape
/// to check rather than two.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Char "mo:core/Char";
import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Nat32 "mo:core/Nat32";
import Nat64 "mo:core/Nat64";
import Text "mo:core/Text";

module {

  public type Header = { name : Text; value : Text };

  public type Method = { #get; #head; #post };

  /// The substrate's `http_request` argument, minus `transform` - the transform is a
  /// closure over the actor's own query function and cannot be built outside it. Every other field
  /// is decided by the builder.
  public type Request = {
    url : Text;
    max_response_bytes : ?Nat64;
    method : Method;
    headers : [Header];
    body : ?Blob;
    is_replicated : ?Bool;
  };

  public func bodyBytes(r : Request) : Nat {
    switch (r.body) { case null 0; case (?b) Blob.toArray(b).size() }
  };

  // ── JSON ────────────────────────────────────────────────────────────────────

  /// A JSON string literal. Every control character is escaped, not dropped: a subject line or a
  /// description with a quote or a newline in it must produce a request the provider can parse, and
  /// a body that silently lost a character is a body nobody wrote.
  public func str(t : Text) : Text {
    var out = "\"";
    for (c in t.chars()) {
      out #= switch (c) {
        case ('\"') "\\\"";
        case ('\\') "\\\\";
        case ('\n') "\\n";
        case ('\r') "\\r";
        case ('\t') "\\t";
        case (other) {
          let n = Char.toNat32(other);
          if (n < 0x20) "\\u" # hex4(n) else Text.fromChar(other)
        };
      };
    };
    out # "\""
  };

  func hex4(n : Nat32) : Text {
    let digits = "0123456789abcdef";
    var out = "";
    var i : Nat32 = 3;
    loop {
      let nibble = Nat32.toNat((n >> (i * 4)) & 0xF);
      var k = 0;
      for (d in digits.chars()) {
        if (k == nibble) out #= Text.fromChar(d);
        k += 1;
      };
      if (i == 0) return out;
      i -= 1;
    }
  };

  // ── scaled decimals ─────────────────────────────────────────────────────────

  /// A signed minor-unit amount as a decimal string at a declared scale.
  ///
  /// THE RECEIVED VERSION LOSES THE SIGN. `erp.mo:1006` is
  ///
  ///     let whole = minorUnits / 100;
  ///     let frac  = Int.abs(minorUnits % 100);
  ///     Int.toText(whole) # "." # fracStr
  ///
  /// Motoko's integer division truncates toward zero, so for any amount between −0.99 and −0.01 the
  /// whole part is `0`, `Int.toText(0)` is `"0"`, and the minus sign is in neither part: −0.50 and
  /// +0.50 both format as `"0.50"`. Compiled and run, the received function prints
  /// `-50 -> 0.50`, `-99 -> 0.99`, `50 -> 0.50`. Every small negative line of a credit note is
  /// filed to the revenue authority as a charge. `etaQuantityToText` and `etaRateToText` are the
  /// same three lines at different scales with the same defect.
  ///
  /// And the scale is the CURRENCY'S, not a hard-coded 100: a currency with no minor unit and one
  /// with three decimal places are both filed correctly.
  public func scaled(value : Int, exponent : Nat) : Text {
    let sign = if (value < 0) "-" else "";
    let magnitude = Int.abs(value);
    if (exponent == 0) return sign # Nat.toText(magnitude);
    var divisor = 1;
    var i = 0;
    while (i < exponent) { divisor *= 10; i += 1 };
    let whole = magnitude / divisor;
    let frac = magnitude % divisor;
    sign # Nat.toText(whole) # "." # padded(frac, exponent)
  };

  /// The fractional part, zero-padded to the scale. `0` at two places is `"00"`, not `"0"`.
  public func padded(frac : Nat, places : Nat) : Text {
    var s = Nat.toText(frac);
    var have = Text.size(s);
    while (have < places) { s := "0" # s; have += 1 };
    s
  };

}
