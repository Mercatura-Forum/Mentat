// Platform.test.mo - the platform operator: a fact of the log, claimed once and handed over in two steps.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the claim       ACCEPTED ONCE, while the log names no operator AND no company exists: a second claim refused,
//                   by anyone; a claim on a log that holds a company refused for good, though no operator was ever
//                   named (a second state, its first act a company).
//   the hand-over   an offer FROM THE OPERATOR ONLY (anyone else's refused, a company's administrator's included);
//                   an offer to the operator itself refused; A SECOND OFFER REPLACES THE FIRST, so the first
//                   principal offered can no longer accept; an offer TO NOBODY WITHDRAWS the standing one, and
//                   with none standing is refused; an acceptance BY THE PRINCIPAL OFFERED ONLY; after it the old
//                   operator can no longer offer and the new one can.
//   the authority   the platform's acts - the statutory schedules every company's payroll reads - from the
//                   operator only: from a company's administrator, from a member and from a stranger refused; a
//                   membership naming a platform role is refused, so no membership can claim to be one.
//   the fold        every refusal byte-neutral; the one-row table read back as the log made it.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import DL "mo:kernel/domain/DomainLog";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import Log "../src/Log";
import PFold "../src/PlatformFold";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let OPERATOR = who(1);
let SECOND = who(2);
let THIRD = who(3);
let ADMIN = who(4);
let MEMBER = who(5);
let STRANGER = who(9);

var heightCell : Nat = 600_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-11-11
let DAY : Nat = 20_768;
let config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};

var log = Log.newState();
var state = St.newState();

func send(caller : Principal, c : Cmd.Command) : { #ok : Con.Accepted; #err : Con.Refused } {
  heightCell += 1;
  Con.accept(log, state, config, source, caller, c)
};
func mustOk(caller : Principal, c : Cmd.Command, what : Text) : [Nat] {
  switch (send(caller, c)) {
    case (#ok a) a.effects;
    case (#err r) { check(false, what # ": " # Con.refusedText(r)); [] };
  }
};
var refusals = 0;
/// REFUSED FOR ITS OWN REASON, with nothing written: the refusal's words carry `reason`, and the state's
/// fingerprint and the log's length are the ones before the act.
func mustRefuse(caller : Principal, c : Cmd.Command, reason : Text, what : Text) {
  let before = St.fingerprintHash(state);
  let height = DL.length(log);
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err r) {
      refusals += 1;
      let said = Con.refusedText(r);
      check(Text.contains(said, #text reason), what # ": refused as \"" # said # "\", not for \"" # reason # "\"");
    };
  };
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
  check(DL.length(log) == height, what # ": refused with nothing appended to the log");
};
let GATE = "not entitled";

func operatorIs(p : Principal) : Bool { PFold.isOperator(state.platform, p) };
func offeredIs(p : ?Principal) : Bool { PFold.offered(state.platform) == p };

// ── the claim's window, closed by the first company ──────────────────────────

ignore mustOk(ADMIN, #bootstrapCompany { facts = { name = "First"; slug = "first"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "a company before any operator");
check(PFold.current(state.platform) == null, "no operator is named on a log that never claimed one");
mustRefuse(OPERATOR, #claimPlatformOperator {}, GATE, "A CLAIM ON A LOG THAT HOLDS A COMPANY");
mustRefuse(ADMIN, #claimPlatformOperator {}, GATE, "a claim by the company's own administrator, on a log that holds a company");
check(PFold.current(state.platform) == null, "the closed window names nobody");

// ── a fresh log: the claim ───────────────────────────────────────────────────

log := Log.newState();
state := St.newState();

mustRefuse(OPERATOR, #offerPlatformOperator { to = ?SECOND }, GATE, "an offer while no operator is named");
mustRefuse(SECOND, #acceptPlatformOperator {}, GATE, "an acceptance while no operator is named");
let claimed = mustOk(OPERATOR, #claimPlatformOperator {}, "THE CLAIM");
check(claimed == [1], "the claim writes the one row");
check(operatorIs(OPERATOR), "the claimant is the operator");
check(offeredIs(null), "no offer stands after a claim");
switch (PFold.current(state.platform)) {
  case (?p) { check(p.sinceBlock == 0, "the operator holds the role from the block of its claim, the log's first") };
  case null { check(false, "the claim is read back") };
};
mustRefuse(SECOND, #claimPlatformOperator {}, GATE, "A SECOND CLAIM, by another principal");
mustRefuse(OPERATOR, #claimPlatformOperator {}, GATE, "a second claim, by the operator itself");

ignore mustOk(ADMIN, #bootstrapCompany { facts = { name = "Tenant"; slug = "tenant"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "a company");
let CO = 1;
ignore mustOk(ADMIN, #admitMember { companyId = CO; subject = MEMBER; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a member");
mustRefuse(ADMIN, #admitMember { companyId = CO; subject = STRANGER; companyRole = #Employee; platformRole = #PlatformAdmin; managerId = 0 }, "accepted only as None", "A MEMBERSHIP NAMING A PLATFORM ROLE");
mustRefuse(ADMIN, #admitMember { companyId = CO; subject = STRANGER; companyRole = #Employee; platformRole = #PlatformSupport; managerId = 0 }, "accepted only as None", "a membership naming platform support");

// ── the hand-over ────────────────────────────────────────────────────────────

mustRefuse(ADMIN, #offerPlatformOperator { to = ?ADMIN }, GATE, "AN OFFER BY A COMPANY'S ADMINISTRATOR");
mustRefuse(STRANGER, #offerPlatformOperator { to = ?STRANGER }, GATE, "an offer by a stranger");
mustRefuse(OPERATOR, #offerPlatformOperator { to = ?OPERATOR }, "is the platform operator already", "AN OFFER TO THE OPERATOR ITSELF");
mustRefuse(OPERATOR, #offerPlatformOperator { to = null }, "no offer", "A WITHDRAWAL WITH NO OFFER STANDING");

ignore mustOk(OPERATOR, #offerPlatformOperator { to = ?SECOND }, "the role offered to the second principal");
check(offeredIs(?SECOND), "the offer stands, naming the second principal");
check(operatorIs(OPERATOR), "an offer moves nothing: the operator holds the role");
mustRefuse(THIRD, #acceptPlatformOperator {}, GATE, "AN ACCEPTANCE BY A PRINCIPAL NOT OFFERED");
mustRefuse(OPERATOR, #acceptPlatformOperator {}, GATE, "an acceptance by the operator itself");

ignore mustOk(OPERATOR, #offerPlatformOperator { to = ?THIRD }, "A SECOND OFFER");
check(offeredIs(?THIRD), "the second offer replaces the first");
mustRefuse(SECOND, #acceptPlatformOperator {}, GATE, "THE FIRST PRINCIPAL OFFERED, after the offer was replaced");

ignore mustOk(OPERATOR, #offerPlatformOperator { to = null }, "THE OFFER WITHDRAWN");
check(offeredIs(null), "a withdrawn offer names nobody");
mustRefuse(THIRD, #acceptPlatformOperator {}, GATE, "an acceptance of a withdrawn offer");
check(operatorIs(OPERATOR), "a withdrawal moves nothing: the operator holds the role");

ignore mustOk(OPERATOR, #offerPlatformOperator { to = ?SECOND }, "the role offered again");
ignore mustOk(SECOND, #acceptPlatformOperator {}, "THE ACCEPTANCE");
check(operatorIs(SECOND), "the principal offered is the operator");
check(not operatorIs(OPERATOR), "the old operator holds the role no longer");
check(offeredIs(null), "the offer is spent");
mustRefuse(OPERATOR, #offerPlatformOperator { to = ?OPERATOR }, GATE, "AN OFFER BY THE OLD OPERATOR");
mustRefuse(SECOND, #acceptPlatformOperator {}, GATE, "an acceptance with the offer spent");
ignore mustOk(SECOND, #offerPlatformOperator { to = ?OPERATOR }, "the new operator offers");
ignore mustOk(SECOND, #offerPlatformOperator { to = null }, "and withdraws");

// ── the platform's acts ──────────────────────────────────────────────────────

func profile() : Cmd.Command {
  #declareStatutoryProfile { facts = { jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP"; socialEmployeeRate = 110_000; socialEmployerRate = 187_500; socialCeiling = 1_290_000; socialFloor = 200_000; personalAllowance = 2_000_000 } }
};
mustRefuse(ADMIN, profile(), GATE, "A STATUTORY SCHEDULE FROM A COMPANY'S ADMINISTRATOR");
mustRefuse(MEMBER, profile(), GATE, "a statutory schedule from a member");
mustRefuse(STRANGER, profile(), GATE, "a statutory schedule from a stranger");
mustRefuse(OPERATOR, profile(), GATE, "a statutory schedule from the old operator");
let PROFILE = mustOk(SECOND, profile(), "THE STATUTORY SCHEDULE FROM THE OPERATOR")[0];
mustRefuse(ADMIN, #declareTaxBracket { facts = { profileId = PROFILE; ordinal = 1; fromAmount = 0; toAmount = 0; rate = 100_000 } }, GATE, "a bracket from a company's administrator");
ignore mustOk(SECOND, #declareTaxBracket { facts = { profileId = PROFILE; ordinal = 1; fromAmount = 0; toAmount = 0; rate = 100_000 } }, "the bracket from the operator");
mustRefuse(ADMIN, #declareOvertimePremiums { facts = { profileId = PROFILE; regular = 1_500_000; weekend = 2_000_000; holiday = 2_000_000; callIn = 1_500_000 } }, GATE, "premiums from a company's administrator");
mustRefuse(ADMIN, #retireStatutoryProfile { profileId = PROFILE; reason = "x" }, GATE, "a retirement from a company's administrator");
ignore mustOk(SECOND, #retireStatutoryProfile { profileId = PROFILE; reason = "superseded" }, "the retirement from the operator");

// ── the result ────────────────────────────────────────────────────────────────

Debug.print("count: platform refusals, each byte-neutral = " # Nat.toText(refusals));
Debug.print("count: blocks on the hand-over's log = " # Nat.toText(DL.length(log)));
if (failures == 0) Debug.print("PLATFORM GREEN") else Runtime.trap(Nat.toText(failures) # " failure(s)");
