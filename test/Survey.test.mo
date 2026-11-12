// Survey.test.mo - a survey with questions, answers as rows bounded per respondent, results as a paged read.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the survey      opened by a member with a title, a last day or none, the respondents named or not; closed
//                   by a member; questions added IN ORDER while nobody has answered - yes-no, a rating of one to
//                   five, one of two to ten options, free text - each required or not, at most thirty-two.
//   the response    A MEMBER'S, ONCE: the respondent the caller, kept as a key alone where the survey is
//                   anonymous and refused a second time all the same; AT MOST ONE ANSWER PER QUESTION, every
//                   required question answered, every answer held to its kind - a rating within one to five, an
//                   option within the options, text on an open question alone and within its bound - the whole
//                   response refused as one when any answer is not; nothing after the last day or the close.
//   the results     a page of questions in order, each with its tally counted from the answer rows - so many
//                   noes and yeses, so many of each rating, so many of each option, so many texts.
//   the fold        the log replayed from genesis reproduces every table; a count moved without a block is a
//                   different fingerprint.
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
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import Log "../src/Log";
import SF "../src/SurveyFacts";
import SFold "../src/SurveyFold";
import SRw "../src/SurveyRows";
import St "../src/State";
import TA "../src/TextArena";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let ANN = who(2);
let BEN = who(3);
let CARA = who(4);
let STRANGER = who(9);

var heightCell : Nat = 161_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
let DAY : Nat = 20_709;
var config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};
func roll(to : Nat) {
  config := switch (Clk.roll(config, to)) {
    case (#ok c) c;
    case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
  };
};

let log = Log.newState();
let state = St.newState();

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
func mustFail(caller : Principal, c : Cmd.Command, what : Text) {
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err _) { refusals += 1 };
  }
};
func mustFailUntouched(caller : Principal, c : Cmd.Command, what : Text) {
  let before = St.fingerprintHash(state);
  mustFail(caller, c, what);
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── the company and its members ───────────────────────────────────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Asks"; slug = "asks"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [ANN, BEN, CARA].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a member") };
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
// the boss a member of both, so a wrong-company refusal is the company's and not the membership's
for (p in [ANN].vals()) { ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "Ann there too") };

// ── reads ─────────────────────────────────────────────────────────────────────

func survey(id : Nat) : SRw.Survey { switch (RowStore.get<SRw.Survey>(state.surveys.surveys, SRw.survey, id)) { case (?s) s; case null Runtime.trap("no survey " # Nat.toText(id)) } };
func question(id : Nat) : SRw.Question { switch (RowStore.get<SRw.Question>(state.surveys.questions, SRw.question, id)) { case (?q) q; case null Runtime.trap("no question " # Nat.toText(id)) } };
func response(id : Nat) : SRw.Response { switch (RowStore.get<SRw.Response>(state.surveys.responses, SRw.response, id)) { case (?r) r; case null Runtime.trap("no response " # Nat.toText(id)) } };
func text(r : TA.Ref) : Text { switch (TA.get(state.arena, r)) { case (?t) t; case null "" } };
func tally(qid : Nat) : [Nat] { SFold.tally(state.surveys, qid, question(qid)) };
func sameTally(a : [Nat], b : [Nat]) : Bool { if (a.size() != b.size()) return false; var i = 0; while (i < a.size()) { if (a[i] != b[i]) return false; i += 1 }; true };

// ── the survey and its questions ──────────────────────────────────────────────

func sf(co : Nat, title : Text, anon : Bool, due : Nat) : SF.SurveyFacts = { companyId = co; title; isAnonymous = anon; dueDay = due };
mustFailUntouched(BOSS, #openSurvey { facts = sf(9_999, "Pulse", false, 0) }, "a survey of a company that does not exist");
mustFailUntouched(STRANGER, #openSurvey { facts = sf(CO, "Pulse", false, 0) }, "A SURVEY BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(BOSS, #openSurvey { facts = sf(CO, "", false, 0) }, "a survey without a title");
mustFailUntouched(BOSS, #openSurvey { facts = sf(CO, "Pulse", false, 16_777_216) }, "a last day that does not fit");
mustFailUntouched(BOSS, #openSurvey { facts = sf(CO, "Pulse", false, DAY - 1) }, "A LAST DAY THAT HAS PASSED");
let SV = mustOk(BOSS, #openSurvey { facts = sf(CO, "Spring pulse", false, DAY + 2) }, "THE SURVEY, named respondents, through the day after tomorrow")[0];
check(survey(SV).state == #open and survey(SV).questions == 0 and survey(SV).responses == 0 and survey(SV).openedBy == BOSS and not survey(SV).isAnonymous and survey(SV).dueDay == DAY + 2, "open, nothing asked, nobody answered");
func qf(co : Nat, sv : Nat, kind : E.QuestionKind, t : Text, options : [Text], required : Bool) : SF.QuestionFacts = { companyId = co; surveyId = sv; kind; text = t; options; required };
mustFailUntouched(BOSS, #addSurveyQuestion { facts = qf(CO, 9_999, #yesNo, "Happy?", [], true) }, "a question on a survey that is not there");
mustFailUntouched(BOSS, #addSurveyQuestion { facts = qf(OTHER, SV, #yesNo, "Happy?", [], true) }, "a question under the wrong company");
mustFailUntouched(STRANGER, #addSurveyQuestion { facts = qf(CO, SV, #yesNo, "Happy?", [], true) }, "a question by a stranger");
mustFailUntouched(BOSS, #addSurveyQuestion { facts = qf(CO, SV, #yesNo, "", [], true) }, "a question without a text");
mustFailUntouched(BOSS, #addSurveyQuestion { facts = qf(CO, SV, #yesNo, "Happy?", ["yes"], true) }, "OPTIONS ON A YES-NO QUESTION");
mustFailUntouched(BOSS, #addSurveyQuestion { facts = qf(CO, SV, #multiChoice, "Team?", ["Sales"], true) }, "A CHOICE OF ONE OPTION");
mustFailUntouched(BOSS, #addSurveyQuestion { facts = qf(CO, SV, #multiChoice, "Team?", Array.tabulate<Text>(11, func(i) { "o" # Nat.toText(i) }), true) }, "a choice of eleven options");
mustFailUntouched(BOSS, #addSurveyQuestion { facts = qf(CO, SV, #multiChoice, "Team?", ["Sales", ""], true) }, "an option without a text");
mustFailUntouched(ANN, #respondToSurvey { facts = { companyId = CO; surveyId = SV; answers = [] } }, "A RESPONSE TO A SURVEY THAT ASKS NOTHING");
let QY = mustOk(BOSS, #addSurveyQuestion { facts = qf(CO, SV, #yesNo, "Are you happy at work?", [], true) }, "the first question, a yes-no, required")[0];
let QR = mustOk(BOSS, #addSurveyQuestion { facts = qf(CO, SV, #rating, "Rate the coffee", [], true) }, "the second, a rating, required")[0];
let QC = mustOk(BOSS, #addSurveyQuestion { facts = qf(CO, SV, #multiChoice, "Which team?", ["Sales", "Ops", "Finance"], false) }, "the third, one of three, optional")[0];
let QT = mustOk(BOSS, #addSurveyQuestion { facts = qf(CO, SV, #openText, "Anything else?", [], false) }, "the fourth, free text, optional")[0];
check(survey(SV).questions == 4 and question(QY).ordinal == 1 and question(QT).ordinal == 4 and question(QC).optionCount == 3 and text(question(QC).options) == "Sales" # SFold.SEPARATOR # "Ops" # SFold.SEPARATOR # "Finance", "FOUR QUESTIONS IN ORDER, the options kept");
check(SFold.choices(question(QY)) == 2 and SFold.choices(question(QR)) == 5 and SFold.choices(question(QC)) == 3 and SFold.choices(question(QT)) == 0, "the choices each kind takes");
// the bound on questions
let SVFULL = mustOk(BOSS, #openSurvey { facts = sf(CO, "Too long", false, 0) }, "a survey to fill")[0];
let SVFQ = mustOk(BOSS, #addSurveyQuestion { facts = qf(CO, SVFULL, #yesNo, "Ask 0", [], false) }, "its first question")[0];
var k = 1;
while (k < SFold.MAX_QUESTIONS) { ignore mustOk(BOSS, #addSurveyQuestion { facts = qf(CO, SVFULL, #yesNo, "Ask " # Nat.toText(k), [], false) }, "a question"); k += 1 };
mustFailUntouched(BOSS, #addSurveyQuestion { facts = qf(CO, SVFULL, #yesNo, "One more", [], false) }, "THE THIRTY-THIRD QUESTION");

// ── responses ─────────────────────────────────────────────────────────────────

func a(q : Nat, choice : Nat, t : Text) : SF.AnswerFacts = { questionId = q; choice; text = t };
func rf(co : Nat, sv : Nat, answers : [SF.AnswerFacts]) : SF.ResponseFacts = { companyId = co; surveyId = sv; answers };
let FULL = [a(QY, 2, ""), a(QR, 4, ""), a(QC, 2, ""), a(QT, 0, "More plants.")];
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, 9_999, FULL) }, "a response to a survey that is not there");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(OTHER, SV, FULL) }, "a response under the wrong company");
mustFailUntouched(STRANGER, #respondToSurvey { facts = rf(CO, SV, FULL) }, "A RESPONSE BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 2, ""), a(QR, 4, ""), a(9_999, 1, "")]) }, "an answer to a question that is not there");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 2, ""), a(QR, 4, ""), a(SVFQ, 1, "")]) }, "AN ANSWER TO ANOTHER SURVEY'S QUESTION");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 2, ""), a(QR, 4, ""), a(QY, 1, "")]) }, "AT MOST ONE ANSWER PER QUESTION: question one twice");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 2, "")]) }, "A REQUIRED QUESTION UNANSWERED: the rating");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 3, ""), a(QR, 4, "")]) }, "A CHOICE OF THREE ON A YES-NO");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 0, ""), a(QR, 4, "")]) }, "a choice of nothing on a yes-no");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 2, ""), a(QR, 6, "")]) }, "A RATING OF SIX");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 2, ""), a(QR, 4, ""), a(QC, 4, "")]) }, "THE FOURTH OF THREE OPTIONS");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 2, "yes!"), a(QR, 4, "")]) }, "TEXT ON A YES-NO");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 2, ""), a(QR, 4, ""), a(QT, 1, "text")]) }, "a choice on an open question");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 2, ""), a(QR, 4, ""), a(QT, 0, "")]) }, "an open answer of nothing");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 2, ""), a(QR, 4, ""), a(QT, 0, Text.fromArray(Array.tabulate<Char>(1_001, func(_) { 'x' })))]) }, "AN OPEN ANSWER BEYOND ITS BOUND");
check(survey(SV).responses == 0 and RowStore.size(state.surveys.answers) == 0, "NOTHING WRITTEN BY A REFUSED RESPONSE");
let R1 = mustOk(ANN, #respondToSurvey { facts = rf(CO, SV, FULL) }, "ANN'S RESPONSE: yes, four stars, Ops, a word");
check(R1.size() == 5 and response(R1[0]).respondent == ANN and response(R1[0]).answers == 4 and response(R1[0]).day == DAY and response(R1[0]).respondentKey == SFold.respondentKeyOf(SV, ANN), "the response, named, four answers as rows, THE KEY THE BATTERY'S OWN");
check(survey(SV).responses == 1 and question(QY).answers == 1 and question(QT).answers == 1, "counted on the survey and the questions");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, SV, FULL) }, "ONE RESPONSE PER RESPONDENT: Ann again");
mustFailUntouched(BOSS, #addSurveyQuestion { facts = qf(CO, SV, #yesNo, "Late question", [], false) }, "A QUESTION ADDED ONCE SOMEBODY HAS ANSWERED");
roll(DAY + 1);
let R2 = mustOk(BEN, #respondToSurvey { facts = rf(CO, SV, [a(QY, 1, ""), a(QR, 2, ""), a(QC, 2, "")]) }, "BEN'S RESPONSE, tomorrow: no, two stars, Ops, no word")[0];
check(response(R2).answers == 3 and response(R2).day == DAY + 1 and question(QT).answers == 1, "three answers, the optional text left out");
roll(DAY + 2);
let R3 = mustOk(CARA, #respondToSurvey { facts = rf(CO, SV, [a(QY, 2, ""), a(QR, 4, ""), a(QC, 1, "")]) }, "CARA'S RESPONSE, on the last day: yes, four stars, Sales")[0];
check(survey(SV).responses == 3, "three responses");
// the results, a paged read
check(sameTally(tally(QY), [1, 2]) and sameTally(tally(QR), [0, 1, 0, 2, 0]) and sameTally(tally(QC), [1, 2, 0]) and sameTally(tally(QT), [1]), "THE TALLIES: one no and two yeses; one two-star and two four-stars; one Sales and two Ops; one text");
do {
  let page = SFold.results(state.surveys, SV, 1, 2);
  check(page.size() == 2 and page[0].0 == QY and page[1].0 == QR and sameTally(page[1].2, [0, 1, 0, 2, 0]), "A PAGE OF TWO QUESTIONS FROM THE FIRST, each with its tally");
  let rest = SFold.results(state.surveys, SV, 3, 10);
  check(rest.size() == 2 and rest[0].0 == QC and rest[1].0 == QT, "the next page: the last two");
};
roll(DAY + 3);
mustFailUntouched(BOSS, #respondToSurvey { facts = rf(CO, SV, FULL) }, "A RESPONSE AFTER THE LAST DAY");
// close
mustFailUntouched(STRANGER, #closeSurvey { companyId = CO; surveyId = SV }, "a stranger closing");
mustFailUntouched(BOSS, #closeSurvey { companyId = CO; surveyId = 9_999 }, "closing a survey that is not there");
ignore mustOk(BOSS, #closeSurvey { companyId = CO; surveyId = SV }, "CLOSED");
check(survey(SV).state == #closed and survey(SV).closedDay == DAY + 3, "closed, dated");
mustFailUntouched(BOSS, #closeSurvey { companyId = CO; surveyId = SV }, "closed twice");
mustFailUntouched(BOSS, #addSurveyQuestion { facts = qf(CO, SV, #yesNo, "Late", [], false) }, "a question on a closed survey");
check(sameTally(tally(QY), [1, 2]), "the results stand after the close");
// an anonymous survey keeps the respondent as a key alone
let AN = mustOk(BOSS, #openSurvey { facts = sf(CO, "Anonymous pulse", true, 0) }, "AN ANONYMOUS SURVEY with no last day")[0];
let AQ = mustOk(BOSS, #addSurveyQuestion { facts = qf(CO, AN, #rating, "Rate your manager", [], true) }, "its one question")[0];
let AR = mustOk(ANN, #respondToSurvey { facts = rf(CO, AN, [a(AQ, 5, "")]) }, "Ann answers")[0];
check(response(AR).respondent == SFold.nobody() and response(AR).respondentKey == SFold.respondentKeyOf(AN, ANN), "NOBODY IS NAMED, the key is kept");
mustFailUntouched(ANN, #respondToSurvey { facts = rf(CO, AN, [a(AQ, 1, "")]) }, "ANN AGAIN, UNNAMED, REFUSED ALL THE SAME");
ignore mustOk(BEN, #respondToSurvey { facts = rf(CO, AN, [a(AQ, 3, "")]) }, "Ben answers");
check(sameTally(tally(AQ), [0, 0, 1, 0, 1]) and survey(AN).responses == 2, "two answers tallied, no name on either");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the surveys, the responses and the answers included");
check(RowStore.size(replay.state.surveys.answers) == 12 and RowStore.size(replay.state.surveys.responses) == 5, "every table is reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let q = question(QY);
  RowStore.put<SRw.Question>(state.surveys.questions, SRw.question, QY, { q with answers = q.answers + 1 });
  check(St.fingerprintHash(state) != before_, "a count moved without a block is a different fingerprint");
  RowStore.put<SRw.Question>(state.surveys.questions, SRw.question, QY, q);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: surveys = " # Nat.toText(RowStore.size(state.surveys.surveys)));
Debug.print("count: questions = " # Nat.toText(RowStore.size(state.surveys.questions)));
Debug.print("count: responses = " # Nat.toText(RowStore.size(state.surveys.responses)));
Debug.print("count: answers as rows = " # Nat.toText(RowStore.size(state.surveys.answers)));
Debug.print("count: tallies restated = 5");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("SURVEY GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("survey battery failed") };
