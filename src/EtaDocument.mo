/// EtaDocument.mo - the tax document as the Egyptian Tax Authority's SDK specifies it, its
/// canonical serialisation, and the digest a seal is made over.
///
/// THE SOURCE IS THE AUTHORITY'S OWN SPECIFICATION, read from its SDK portal on 2026-09-20: the document
/// type version 1.0 for the invoice, the credit note and the debit note; the serialisation page
/// that says how a document is turned into the bytes a seal is computed over; and the signature
/// page that says the seal is a CAdES-BES over the SHA-256 of those bytes. The serialisation is
/// checked against the authority's own published example in the gate: the example document
/// serialised by this rule hashes to the `messageDigest` inside the authority's own seal.
///
/// THE SERIALISATION, AS THE AUTHORITY STATES IT. Walk the document from its root. Every property
/// name is written upper-cased in double quotes. Every simple value is written in double quotes,
/// as it is in the document, with no reformatting - so `0.0` stays `0.0`. An object's members are
/// written in document order. An array is written as its upper-cased name, then, for each
/// element, the upper-cased name again followed by the element's serialisation. The `signatures`
/// member is not part of the document that is serialised, because it is what the serialisation
/// is signed into.
///
/// The document is built here as a JSON tree whose numbers are TEXT (the kernel's `JsonTree`
/// keeps them so), which is what makes "the value as it is in the document" a property of the
/// emitter and not of a printer: the text serialised is the text emitted, and the Python twin
/// reads the emitted body preserving the same text.
///
/// MONEY IS FORMATTED FROM MINOR UNITS AT THE CURRENCY'S EXPONENT, quantities from thousandths,
/// rates from hundredths of a basis point, each by one function that keeps the sign and pads the
/// fraction - the class of defect the received tree's `etaAmountToText` had (−0.50 printed as
/// `0.50`) cannot recur here because there is no division that drops a sign.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Text "mo:core/Text";

import CivilDate "mo:kernel/num/CivilDate";
import Json "mo:kernel/codec/JsonTree";
import H "mo:kernel/hash/Sha256Hex";

module {

  public type Address = {
    branchId : Text;   // the issuer's branch as registered; empty for a receiver
    country : Text;
    governate : Text;
    regionCity : Text;
    street : Text;
    buildingNumber : Text;
    postalCode : Text;
  };

  public type Party = {
    /// B for a business in Egypt, P for a natural person, F for a foreigner.
    partyType : Text;
    id : Text;
    name : Text;
    address : Address;
  };

  public type Line = {
    description : Text;
    /// GS1 or EGS.
    itemType : Text;
    itemCode : Text;
    unitType : Text;
    /// Thousandths of a unit.
    quantity : Nat;
    internalCode : Text;
    /// Minor units at the currency's exponent.
    unitPrice : Nat;
    salesTotal : Nat;
    /// The tax type code (T1 for VAT) and its sub-type (V009 and so on), from the item's profile.
    taxType : Text;
    taxSubType : Text;
    /// Hundredths of a basis point: 14% is 140_000.
    taxRate : Nat;
    taxAmount : Nat;
  };

  public type Document = {
    /// "I", "C" or "D".
    documentType : Text;
    documentTypeVersion : Text;
    issuer : Party;
    receiver : Party;
    issueDay : Nat;
    activityCode : Text;
    internalId : Text;
    /// A credit or debit note names the authority's identifiers of the documents it amends.
    references : [Text];
    currency : Text;
    exponent : Nat;
    lines : [Line];
  };

  // ── formatting ──────────────────────────────────────────────────────────────

  /// `value / 10^scale` as decimal text with exactly `scale` fraction digits, sign kept.
  public func dec(value : Int, scale : Nat) : Text {
    let neg = value < 0;
    let mag = Int.abs(value);
    var p = 1;
    var i = 0;
    while (i < scale) { p *= 10; i += 1 };
    let whole = mag / p;
    let frac = mag % p;
    var fracText = Nat.toText(frac);
    while (Text.size(fracText) < scale) { fracText := "0" # fracText };
    (if (neg) "-" else "") # Nat.toText(whole) # (if (scale == 0) "" else "." # fracText)
  };

  func num(value : Int, scale : Nat) : Json.Json { #number(dec(value, scale)) };
  func str(t : Text) : Json.Json { #string(t) };

  /// The issue timestamp: the business day at the start of the day, in UTC, as the authority's
  /// `Date` type wants it.
  public func issuedAt(day : Nat) : Text { CivilDate.toText(day) # "T00:00:00Z" };

  // ── the document tree ───────────────────────────────────────────────────────

  func address(a : Address, withBranch : Bool) : Json.Json {
    let ms = List.empty<(Text, Json.Json)>();
    if (withBranch) List.add(ms, ("branchID", str(a.branchId)));
    List.add(ms, ("country", str(a.country)));
    List.add(ms, ("governate", str(a.governate)));
    List.add(ms, ("regionCity", str(a.regionCity)));
    List.add(ms, ("street", str(a.street)));
    List.add(ms, ("buildingNumber", str(a.buildingNumber)));
    if (Text.size(a.postalCode) > 0) List.add(ms, ("postalCode", str(a.postalCode)));
    #object_(List.toArray(ms))
  };

  func party(p : Party, isIssuer : Bool) : Json.Json {
    #object_([
      ("address", address(p.address, isIssuer)),
      ("type", str(p.partyType)),
      ("id", str(p.id)),
      ("name", str(p.name)),
    ])
  };

  func line(l : Line, currency : Text, exponent : Nat) : Json.Json {
    let net = l.salesTotal;   // no line discount in this system
    #object_([
      ("description", str(l.description)),
      ("itemType", str(l.itemType)),
      ("itemCode", str(l.itemCode)),
      ("unitType", str(l.unitType)),
      ("quantity", num(l.quantity, 3)),
      ("internalCode", str(l.internalCode)),
      ("salesTotal", num(l.salesTotal, exponent)),
      ("total", num(net + l.taxAmount, exponent)),
      ("valueDifference", num(0, exponent)),
      ("totalTaxableFees", num(0, exponent)),
      ("netTotal", num(net, exponent)),
      ("itemsDiscount", num(0, exponent)),
      ("unitValue", #object_([
        ("currencySold", str(currency)),
        ("amountEGP", num(l.unitPrice, exponent)),
      ])),
      ("discount", #object_([
        ("rate", num(0, 2)),
        ("amount", num(0, exponent)),
      ])),
      ("taxableItems", #array([
        #object_([
          ("taxType", str(l.taxType)),
          ("amount", num(l.taxAmount, exponent)),
          ("subType", str(l.taxSubType)),
          ("rate", num(l.taxRate, 4)),
        ])
      ])),
    ])
  };

  /// The totals per tax type, in order of first appearance.
  func taxTotals(d : Document) : Json.Json {
    let types = List.empty<Text>();
    let sums = List.empty<Nat>();
    for (l in d.lines.vals()) {
      var found = false;
      var i = 0;
      while (i < List.size(types)) {
        if (List.at(types, i) == l.taxType) { List.put(sums, i, List.at(sums, i) + l.taxAmount); found := true };
        i += 1;
      };
      if (not found) { List.add(types, l.taxType); List.add(sums, l.taxAmount) };
    };
    let out = List.empty<Json.Json>();
    var i = 0;
    while (i < List.size(types)) {
      List.add(out, #object_([("taxType", str(List.at(types, i))), ("amount", num(List.at(sums, i), d.exponent))]));
      i += 1;
    };
    #array(List.toArray(out))
  };

  /// The document without its signatures: what is serialised and sealed.
  public func tree(d : Document) : Json.Json {
    var sales = 0;
    var tax = 0;
    for (l in d.lines.vals()) { sales += l.salesTotal; tax += l.taxAmount };
    let ms = List.empty<(Text, Json.Json)>();
    List.add(ms, ("issuer", party(d.issuer, true)));
    List.add(ms, ("receiver", party(d.receiver, false)));
    List.add(ms, ("documentType", str(d.documentType)));
    List.add(ms, ("documentTypeVersion", str(d.documentTypeVersion)));
    List.add(ms, ("dateTimeIssued", str(issuedAt(d.issueDay))));
    List.add(ms, ("taxpayerActivityCode", str(d.activityCode)));
    List.add(ms, ("internalID", str(d.internalId)));
    if (d.references.size() > 0) {
      List.add(ms, ("references", #array(Array.map<Text, Json.Json>(d.references, func(r) { str(r) }))));
    };
    List.add(ms, ("invoiceLines", #array(Array.map<Line, Json.Json>(d.lines, func(l) { line(l, d.currency, d.exponent) }))));
    List.add(ms, ("totalDiscountAmount", num(0, d.exponent)));
    List.add(ms, ("totalSalesAmount", num(sales, d.exponent)));
    List.add(ms, ("netAmount", num(sales, d.exponent)));
    List.add(ms, ("taxTotals", taxTotals(d)));
    List.add(ms, ("totalAmount", num(sales + tax, d.exponent)));
    List.add(ms, ("extraDiscountAmount", num(0, d.exponent)));
    List.add(ms, ("totalItemsDiscountAmount", num(0, d.exponent)));
    #object_(List.toArray(ms))
  };

  /// The total the document states, in minor units, for comparison with the ledger.
  public func totalAmount(d : Document) : Nat {
    var t = 0;
    for (l in d.lines.vals()) { t += l.salesTotal + l.taxAmount };
    t
  };

  // ── the serialisation ───────────────────────────────────────────────────────

  func quoted(t : Text) : Text { "\"" # t # "\"" };

  /// The authority's serialisation of a tree, exactly as its page states it.
  public func serialize(j : Json.Json) : Text {
    switch (j) {
      case (#string s) quoted(s);
      case (#number n) quoted(n);
      case (#bool b) quoted(if (b) "true" else "false");
      case (#null_) quoted("");
      case (#array xs) {
        // an array reached here without its name is not a document the authority defines
        var out = "";
        for (x in xs.vals()) { out #= serialize(x) };
        out
      };
      case (#object_ ms) {
        var out = "";
        for ((k, v) in ms.vals()) {
          let name = quoted(Text.toUpper(k));
          switch (v) {
            case (#array xs) {
              out #= name;
              for (x in xs.vals()) { out #= name # serialize(x) };
            };
            case _ { out #= name # serialize(v) };
          };
        };
        out
      };
    }
  };

  /// The bytes a seal is made over, and their digest.
  public func canonical(d : Document) : Blob { Text.encodeUtf8(serialize(tree(d))) };
  public func digest(d : Document) : Blob { H.sha256(canonical(d)) };

  // ── the submission body ─────────────────────────────────────────────────────

  /// The document with its issuer seal, inside the submission the API takes:
  /// `{"documents":[ { …, "signatures":[{"signatureType":"I","value":"<base64 CAdES-BES>"}] } ]}`.
  public func submission(d : Document, sealBase64 : Text) : Text {
    let #object_(ms) = tree(d) else return "";
    let signed = #object_(Array.concat<(Text, Json.Json)>(ms, [
      ("signatures", #array([#object_([("signatureType", str("I")), ("value", str(sealBase64))])]))
    ]));
    Json.emit(#object_([("documents", #array([signed]))]))
  };
}
