/// Pacs008.mo - the supplier payment as an ISO 20022 `pacs.008` the messaging hub accepts, built
/// from rows and nothing else.
///
/// The hub (the Thebes ISO 20022 example, `motoko/ISO20022.mo` and `ISO20022Xml.mo`) reads a
/// pacs.008 in a compact, deterministic subset shape and validates it against its usage guideline - 
/// for Egypt: a Business Application Header, a UETR in the RFC 4122 version-4 shape, one transaction
/// per message, settlement by clearing, an IBAN of the country and a BIC of the country at both ends,
/// amounts in an enabled currency with two fraction digits, every text in SWIFT character set X and
/// within its length. This module writes exactly that shape, element for element as the hub's own
/// writer does, so the message the fold records is the message the hub's decoder reads back; the
/// payment battery holds every message to the hub's validator, imported as a package, and the
/// Python twin rebuilds the bytes from the log and requires the fingerprint to agree.
///
/// Nothing here reads a clock: the creation time is the block's business day at midnight, and the
/// UETR is derived from the payment's own identity so a replay writes the same message. Nothing
/// here is a credential.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Text "mo:core/Text";

import CivilDate "mo:kernel/num/CivilDate";
import H "mo:kernel/hash/Sha256Hex";

module {

  public let MESSAGE_DEFINITION : Text = "pacs.008.001.08";
  public let PACS008_NS : Text = "urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08";
  public let HEAD001_NS : Text = "urn:iso:std:iso:20022:tech:xsd:head.001.001.02";
  /// The hub's guideline: one transaction, settled by clearing, a supplier payment by category.
  public let SETTLEMENT_METHOD : Text = "CLRG";
  public let CATEGORY_PURPOSE : Text = "SUPP";
  public let MAX_TEXT : Nat = 140;
  public let MAX_ID : Nat = 35;

  /// What a message is built from. Every field is a row's, resolved by the fold.
  public type Instruction = {
    messageId : Text;
    endToEndId : Text;
    uetr : Blob;
    businessDay : Nat;
    currency : Text;
    minorUnits : Nat;
    debtorName : Text;
    debtorIban : Text;
    debtorBic : Text;
    creditorName : Text;
    creditorIban : Text;
    creditorBic : Text;
    remittance : Text;
    creditorReference : Text;
  };

  // ── the characters, the identifiers, the accounts ───────────────────────────

  func bytes(t : Text) : [Nat8] { Blob.toArray(Text.encodeUtf8(t)) };
  func isDigit(b : Nat8) : Bool { b >= 48 and b <= 57 };
  func isUpper(b : Nat8) : Bool { b >= 65 and b <= 90 };
  func isLower(b : Nat8) : Bool { b >= 97 and b <= 122 };
  func isAlphaNumUpper(b : Nat8) : Bool { isUpper(b) or isDigit(b) };

  /// SWIFT character set X, as the hub enforces it on every text: letters, digits, space, newline
  /// and carriage return, and `' ( ) + , - . / : ?`.
  public func isSwiftX(t : Text) : Bool {
    for (b in bytes(t).vals()) {
      let n = Nat8.toNat(b);
      let ok = isUpper(b) or isLower(b) or isDigit(b)
        or n == 10 or n == 13 or n == 32
        or n == 39 or n == 40 or n == 41 or n == 43 or n == 44 or n == 45
        or n == 46 or n == 47 or n == 58 or n == 63;
      if (not ok) return false;
    };
    true
  };

  /// A text the hub accepts in a field of this width: present, within the width, and in set X.
  public func textFits(t : Text, max : Nat) : Bool { Text.size(t) > 0 and Text.size(t) <= max and isSwiftX(t) };

  func mod97Step(rem : Nat, b : Nat8) : ?Nat {
    if (isDigit(b)) ?((rem * 10 + (Nat8.toNat(b) - 48)) % 97)
    else if (isUpper(b)) ?((rem * 100 + (Nat8.toNat(b) - 55)) % 97)
    else null
  };

  /// ISO 13616: two upper letters, two digits, 15 to 34 characters, and the MOD 97-10 check over
  /// the rearranged string equal to 1.
  public func validIban(iban : Text) : Bool {
    let bs = bytes(iban);
    if (bs.size() < 15 or bs.size() > 34) return false;
    if (not isUpper(bs[0]) or not isUpper(bs[1]) or not isDigit(bs[2]) or not isDigit(bs[3])) return false;
    var rem : Nat = 0;
    var i = 4;
    while (i < bs.size()) {
      switch (mod97Step(rem, bs[i])) { case (?r) { rem := r }; case null return false };
      i += 1;
    };
    i := 0;
    while (i < 4) {
      switch (mod97Step(rem, bs[i])) { case (?r) { rem := r }; case null return false };
      i += 1;
    };
    rem == 1
  };

  /// An Egyptian IBAN is 29 characters: EG, two check digits, 25 digits. The hub refuses any other
  /// shape under EG.
  public func validEgyptianIbanShape(iban : Text) : Bool {
    let bs = bytes(iban);
    if (bs.size() != 29) return false;
    if (bs[0] != 69 or bs[1] != 71) return false;
    var i = 2;
    while (i < bs.size()) { if (not isDigit(bs[i])) return false; i += 1 };
    true
  };

  /// The country an IBAN names: its first two letters.
  public func ibanCountry(iban : Text) : Text {
    let bs = bytes(iban);
    if (bs.size() < 2) return "";
    switch (Text.decodeUtf8(Blob.fromArray([bs[0], bs[1]]))) { case (?t) t; case null "" }
  };

  /// ISO 9362: four upper letters, two upper letters of country, two upper letters or digits, and
  /// an optional branch of three.
  public func validBic(bic : Text) : Bool {
    let bs = bytes(bic);
    if (bs.size() != 8 and bs.size() != 11) return false;
    var i = 0;
    while (i < 4) { if (not isUpper(bs[i])) return false; i += 1 };
    if (not isUpper(bs[4]) or not isUpper(bs[5])) return false;
    if (not isAlphaNumUpper(bs[6]) or not isAlphaNumUpper(bs[7])) return false;
    i := 8;
    while (i < bs.size()) { if (not isAlphaNumUpper(bs[i])) return false; i += 1 };
    true
  };

  public func bicCountry(bic : Text) : Text {
    let bs = bytes(bic);
    if (bs.size() < 6) return "";
    switch (Text.decodeUtf8(Blob.fromArray([bs[4], bs[5]]))) { case (?t) t; case null "" }
  };

  public func validCurrencyCode(code : Text) : Bool {
    let bs = bytes(code);
    bs.size() == 3 and isUpper(bs[0]) and isUpper(bs[1]) and isUpper(bs[2])
  };

  // ── the UETR ────────────────────────────────────────────────────────────────

  /// The sixteen bytes of a payment's UETR, derived from its identity: SHA-256 over a domain tag,
  /// the company and the payment id, with the version nibble set to 4 and the variant to RFC 4122,
  /// which is the shape the hub requires. Derived, so a replay writes the same message; unique per
  /// payment under the hash.
  public func deriveUetr(companyId : Nat, paymentId : Nat) : Blob {
    let seed = Text.encodeUtf8("MENTAT-UETR-v1:" # Nat.toText(companyId) # ":" # Nat.toText(paymentId));
    let h = Blob.toArray(H.sha256(seed));
    Blob.fromArray(Array.tabulate<Nat8>(16, func(i) {
      if (i == 6) (h[6] & 0x0F) | 0x40
      else if (i == 8) (h[8] & 0x3F) | 0x80
      else h[i]
    }))
  };

  let HEX : [Char] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];

  /// The UUID text of sixteen bytes: 8-4-4-4-12 lower-case hex.
  public func uetrText(u : Blob) : Text {
    let bs = Blob.toArray(u);
    if (bs.size() != 16) return "";
    var out = "";
    var i = 0;
    for (b in bs.vals()) {
      if (i == 4 or i == 6 or i == 8 or i == 10) out #= "-";
      let n = Nat8.toNat(b);
      out #= Text.fromChar(HEX[n / 16]) # Text.fromChar(HEX[n % 16]);
      i += 1;
    };
    out
  };

  /// Is this text a UETR in the version-4 shape the hub requires?
  public func validUetr(uetr : Text) : Bool {
    let bs = bytes(uetr);
    if (bs.size() != 36) return false;
    var i = 0;
    while (i < bs.size()) {
      let hyphen = i == 8 or i == 13 or i == 18 or i == 23;
      if (hyphen) { if (bs[i] != 45) return false }
      else if (not (isDigit(bs[i]) or (bs[i] >= 97 and bs[i] <= 102) or (bs[i] >= 65 and bs[i] <= 70))) return false;
      i += 1;
    };
    if (bs[14] != 52) return false;
    let v = Nat8.toNat(bs[19]);
    v == 56 or v == 57 or v == 65 or v == 66 or v == 97 or v == 98
  };

  // ── the time, the amount, the escaping ──────────────────────────────────────

  func two(n : Nat) : Text { (if (n < 10) "0" else "") # Nat.toText(n) };

  /// The business day at midnight, in the ISO 8601 shape the hub reads. No clock is read: the day
  /// is the block's.
  public func isoDateTime(day : Nat) : Text {
    let (y, m, d) = CivilDate.toCivil(day);
    Nat.toText(y) # "-" # two(m) # "-" # two(d) # "T00:00:00Z"
  };

  /// Minor units as the hub writes an amount: the whole units, a point, two fraction digits.
  public func amountText(minorUnits : Nat) : Text {
    Nat.toText(minorUnits / 100) # "." # two(minorUnits % 100)
  };

  public func escape(value : Text) : Text {
    var out = Text.replace(value, #text "&", "&amp;");
    out := Text.replace(out, #text "<", "&lt;");
    out := Text.replace(out, #text ">", "&gt;");
    out := Text.replace(out, #text "\"", "&quot;");
    Text.replace(out, #text "'", "&apos;")
  };

  // ── the message ─────────────────────────────────────────────────────────────

  func spaces(n : Nat) : Text { var out = ""; var i = 0; while (i < n) { out #= " "; i += 1 }; out };
  func elem(indent : Nat, tag : Text, value : Text) : Text { spaces(indent) # "<" # tag # ">" # escape(value) # "</" # tag # ">\n" };

  func agentXml(indent : Nat, tag : Text, bic : Text) : Text {
    spaces(indent) # "<" # tag # "><FinInstnId>\n"
    # elem(indent + 2, "BICFI", bic)
    # spaces(indent) # "</FinInstnId></" # tag # ">\n"
  };
  func partyXml(indent : Nat, tag : Text, name : Text) : Text {
    spaces(indent) # "<" # tag # ">\n" # elem(indent + 2, "Nm", name) # spaces(indent) # "</" # tag # ">\n"
  };
  func accountXml(indent : Nat, tag : Text, iban : Text, currency : Text) : Text {
    spaces(indent) # "<" # tag # ">\n"
    # "  " # spaces(indent) # "<Id>\n"
    # elem(indent + 4, "IBAN", iban)
    # "  " # spaces(indent) # "</Id>\n"
    # elem(indent + 2, "Ccy", currency)
    # spaces(indent) # "</" # tag # ">\n"
  };

  /// The message: a Business Application Header from the debtor's bank to the creditor's, then the
  /// Document - group header, one transaction, both parties, both accounts, both agents, the
  /// remittance with the bill's reference - in the hub's compact shape, element for element.
  public func build(i : Instruction) : Text {
    let created = isoDateTime(i.businessDay);
    let uetr = uetrText(i.uetr);
    "<AppHdr xmlns=\"" # HEAD001_NS # "\">\n"
    # "  <Fr><FIId><FinInstnId><BICFI>" # escape(i.debtorBic) # "</BICFI></FinInstnId></FIId></Fr>\n"
    # "  <To><FIId><FinInstnId><BICFI>" # escape(i.creditorBic) # "</BICFI></FinInstnId></FIId></To>\n"
    # elem(2, "BizMsgIdr", i.messageId)
    # elem(2, "MsgDefIdr", MESSAGE_DEFINITION)
    # elem(2, "CreDt", created)
    # elem(2, "UETR", uetr)
    # "</AppHdr>\n"
    # "<Document xmlns=\"" # PACS008_NS # "\">\n"
    # "  <FIToFICstmrCdtTrf>\n"
    # "    <GrpHdr>\n"
    # elem(6, "MsgId", i.messageId)
    # elem(6, "CreDtTm", created)
    # elem(6, "NbOfTxs", "1")
    # "      <SttlmInf>\n"
    # elem(8, "SttlmMtd", SETTLEMENT_METHOD)
    # "      </SttlmInf>\n"
    # "    </GrpHdr>\n"
    # "    <CdtTrfTxInf>\n"
    # "      <PmtId>\n"
    # elem(8, "EndToEndId", i.endToEndId)
    # elem(8, "UETR", uetr)
    # "      </PmtId>\n"
    # "      <PmtTpInf>\n"
    # elem(8, "CtgyPurp", CATEGORY_PURPOSE)
    # "      </PmtTpInf>\n"
    # "      <Amt><InstdAmt Ccy=\"" # escape(i.currency) # "\">" # amountText(i.minorUnits) # "</InstdAmt></Amt>\n"
    # agentXml(6, "DbtrAgt", i.debtorBic)
    # partyXml(6, "Dbtr", i.debtorName)
    # accountXml(6, "DbtrAcct", i.debtorIban, i.currency)
    # agentXml(6, "CdtrAgt", i.creditorBic)
    # partyXml(6, "Cdtr", i.creditorName)
    # accountXml(6, "CdtrAcct", i.creditorIban, i.currency)
    # "      <RmtInf>\n"
    # elem(8, "Ustrd", i.remittance)
    # "        <Strd><CdtrRefInf>" # elem(0, "Ref", i.creditorReference) # "</CdtrRefInf></Strd>\n"
    # "      </RmtInf>\n"
    # "    </CdtTrfTxInf>\n"
    # "  </FIToFICstmrCdtTrf>\n"
    # "</Document>\n"
  };

  /// The fingerprint the hub computes over a payload: SHA-256 of its bytes.
  public func digest(message : Text) : Blob { H.sha256(Text.encodeUtf8(message)) };

}
