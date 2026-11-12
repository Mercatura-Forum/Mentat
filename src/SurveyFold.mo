/// SurveyFold.mo - a survey with questions, answers as rows bounded per respondent, results as a paged read.
///
/// A SURVEY IS A SET OF QUESTIONS THE COMPANY ASKS ITS MEMBERS: opened by a member with a title, a last day
/// for responses (or none) and whether the respondents are named; QUESTIONS ADDED IN ORDER while nobody has
/// answered - yes or no, a rating of one to five, one option of up to ten, or free text - each required or
/// not, at most thirty-two; A RESPONSE IS A MEMBER'S, ONCE: the respondent is the caller and nobody a form
/// names, kept as a key alone where the survey is anonymous so a second response is refused all the same;
/// its answers AT MOST ONE PER QUESTION, every required question answered, every answer held to its
/// question's kind - a rating within one to five, an option within the options, text on an open question
/// alone and within its bound - the whole response refused as one when any answer is not; nothing answered
/// after the last day or once closed; RESULTS A PAGED READ: the questions in order with their tallies - so
/// many of each answer - counted from the answer rows, a page of so many questions at a time. The received
/// survey is a record with its questions inside it, its results a count made on every read.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import Sha256 "mo:sha2/Sha256";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import E "Enums";
import F "Fields";
import PR "PosRows";
import SF "SurveyFacts";
import SRw "SurveyRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #titleRequired;
    #dayTooLarge : { day : Nat };
    /// A last day for responses is today or later.
    #dayPassed : { day : Nat; today : Nat };
    #noSuchSurvey : { surveyId : Nat };
    #surveyClosed : { surveyId : Nat };
    /// Questions are added while nobody has answered.
    #alreadyAnswered : { surveyId : Nat; responses : Nat };
    #tooManyQuestions : { max : Nat };
    #noQuestions : { surveyId : Nat };
    #textRequired;
    #optionsRequired : { min : Nat };
    #tooManyOptions : { max : Nat };
    #optionsNotForKind : { kind : E.QuestionKind };
    #optionEmpty;
    #noSuchQuestion : { questionId : Nat };
    #questionNotOfSurvey : { questionId : Nat; surveyId : Nat };
    /// AT MOST ONE ANSWER PER QUESTION.
    #answeredTwice : { questionId : Nat };
    /// Every required question answered.
    #requiredUnanswered : { questionId : Nat };
    #choiceInvalid : { questionId : Nat; choice : Nat };
    #textNotForKind : { questionId : Nat };
    #textTooLong : { max : Nat };
    /// ONE RESPONSE PER RESPONDENT.
    #respondedAlready : { surveyId : Nat };
    /// Nothing answered after the last day.
    #surveyOverdue : { surveyId : Nat; dueDay : Nat; today : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#titleRequired) "a survey needs a title";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit";
      case (#dayPassed { day; today }) "day " # Nat.toText(day) # " has passed: today is " # Nat.toText(today);
      case (#noSuchSurvey { surveyId }) "no survey " # Nat.toText(surveyId);
      case (#surveyClosed { surveyId }) "survey " # Nat.toText(surveyId) # " is closed";
      case (#alreadyAnswered { surveyId; responses }) "survey " # Nat.toText(surveyId) # " has " # Nat.toText(responses) # " response(s): its questions stand";
      case (#tooManyQuestions { max }) "a survey asks at most " # Nat.toText(max) # " questions";
      case (#noQuestions { surveyId }) "survey " # Nat.toText(surveyId) # " asks nothing yet";
      case (#textRequired) "a question has a text";
      case (#optionsRequired { min }) "a choice has at least " # Nat.toText(min) # " options";
      case (#tooManyOptions { max }) "a choice has at most " # Nat.toText(max) # " options";
      case (#optionsNotForKind { kind }) "a " # E.questionKindText(kind) # " question has no options";
      case (#optionEmpty) "an option has a text";
      case (#noSuchQuestion { questionId }) "no question " # Nat.toText(questionId);
      case (#questionNotOfSurvey { questionId; surveyId }) "question " # Nat.toText(questionId) # " is not survey " # Nat.toText(surveyId) # "'s";
      case (#answeredTwice { questionId }) "question " # Nat.toText(questionId) # " answered twice in one response";
      case (#requiredUnanswered { questionId }) "question " # Nat.toText(questionId) # " is required and unanswered";
      case (#choiceInvalid { questionId; choice }) "question " # Nat.toText(questionId) # " takes no choice " # Nat.toText(choice);
      case (#textNotForKind { questionId }) "question " # Nat.toText(questionId) # " takes no text";
      case (#textTooLong { max }) "an answer's text exceeds " # Nat.toText(max) # " characters";
      case (#respondedAlready { surveyId }) "survey " # Nat.toText(surveyId) # " already has this respondent's response";
      case (#surveyOverdue { surveyId; dueDay; today }) "survey " # Nat.toText(surveyId) # " took responses through day " # Nat.toText(dueDay) # ", and today is " # Nat.toText(today);
      case (#textDoesNotFit { field; max }) field # " exceeds " # Nat.toText(max) # " bytes";
    }
  };

  public type Stores = {
    var surveys : RowStore.Store;
    var questions : RowStore.Store;
    var responses : RowStore.Store;
    var answers : RowStore.Store;
    var nextSurveyId : Nat;
    var nextQuestionId : Nat;
    var nextResponseId : Nat;
    var nextAnswerId : Nat;
  };

  public func newStores() : Stores {
    {
      var surveys = RowStore.newStore<SRw.Survey>(SRw.survey);
      var questions = RowStore.newStore<SRw.Question>(SRw.question);
      var responses = RowStore.newStore<SRw.Response>(SRw.response);
      var answers = RowStore.newStore<SRw.Answer>(SRw.answer);
      var nextSurveyId = 1; var nextQuestionId = 1; var nextResponseId = 1; var nextAnswerId = 1;
    }
  };

  public type Ctx = {
    surveys : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_QUESTIONS : Nat = 32;
  public let MIN_OPTIONS : Nat = 2;
  public let MAX_OPTIONS : Nat = 10;
  public let RATING_MAX : Nat = 5;
  public let MAX_TEXT : Nat = 1_000;
  /// The unit separator between a choice's options in the arena.
  public let SEPARATOR : Text = "\u{1F}";

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) { case (#err _) null; case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] } }
  };

  func all<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) { for (row in pg.rows.vals()) List.add(out, row); switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } } };
      };
    };
    List.toArray(out)
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };
  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };
  func natBytes(n : Nat, width : Nat) : [Nat8] { Array.tabulate<Nat8>(width, func(i) { Nat8.fromNat((n / F.pow256(width - 1 - i)) % 256) }) };
  /// Nobody: the principal a response carries when the survey is anonymous.
  public func nobody() : Principal { Principal.fromBlob(Blob.fromArray([])) };

  /// THE RESPONDENT AS A KEY: the survey and the principal hashed under a domain tag - one response per
  /// respondent even where the name is not kept. The independent reader computes the same key.
  public func respondentKeyOf(surveyId : Nat, p : Principal) : Blob {
    var b : [Nat8] = Blob.toArray(Text.encodeUtf8("MENTAT-SURVEY-RESPONDENT-v1"));
    b := Array.concat(b, natBytes(surveyId, W.ID));
    b := Array.concat(b, Blob.toArray(Principal.toBlob(p)));
    Sha256.fromArray(#sha256, b)
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func questionAt(st : Stores, surveyId : Nat, ordinal : Nat) : ?(Nat, SRw.Question) {
    let k = PR.pairKey(surveyId, ordinal);
    one<SRw.Question>(RowStore.page<SRw.Question>(st.questions, SRw.question, "by_survey_ordinal_one", k, k, null, 1))
  };

  public func questionsOf(st : Stores, surveyId : Nat) : [(Nat, SRw.Question)] {
    all<SRw.Question>(st.questions, SRw.question, "by_survey_ordinal_one", PR.pairKey(surveyId, 0), PR.pairKey(surveyId, MAX_QUESTIONS))
  };

  public func responseOf(st : Stores, surveyId : Nat, p : Principal) : ?(Nat, SRw.Response) {
    let k = SRw.respondentKey(surveyId, respondentKeyOf(surveyId, p));
    one<SRw.Response>(RowStore.page<SRw.Response>(st.responses, SRw.response, "by_respondent_one", k, k, null, 1))
  };

  public func answersOf(st : Stores, questionId : Nat) : [(Nat, SRw.Answer)] {
    all<SRw.Answer>(st.answers, SRw.answer, "by_question", PR.pairKey(questionId, 0), PR.pairKey(questionId, F.pow256(W.ID) - 1))
  };

  /// How many choices a question takes: two for yes-no, five for a rating, its options for a choice, none for text.
  public func choices(q : SRw.Question) : Nat {
    switch (q.kind) { case (#yesNo) 2; case (#rating) RATING_MAX; case (#multiChoice) q.optionCount; case (#openText) 0 }
  };

  /// THE TALLY of one question: so many of each choice, from the answer rows - for text, the count alone.
  public func tally(st : Stores, questionId : Nat, q : SRw.Question) : [Nat] {
    let n = choices(q);
    let counts = Array.toVarArray<Nat>(Array.repeat<Nat>(0, if (n == 0) 1 else n));
    for ((_, a) in answersOf(st, questionId).vals()) {
      if (n == 0) counts[0] += 1 else if (a.choice >= 1 and a.choice <= n) counts[a.choice - 1] += 1;
    };
    Array.fromVarArray(counts)
  };

  /// RESULTS, A PAGE AT A TIME: the questions from an ordinal on, so many of them, each with its tally.
  public func results(st : Stores, surveyId : Nat, fromOrdinal : Nat, limit : Nat) : [(Nat, SRw.Question, [Nat])] {
    let n = Nat.min(Nat.max(limit, 1), MAX_QUESTIONS);
    let page = switch (Lookup.upTo<SRw.Question>(st.questions, SRw.question, "by_survey_ordinal_one", PR.pairKey(surveyId, fromOrdinal), PR.pairKey(surveyId, MAX_QUESTIONS), n)) {
      case (#err _) []; case (#ok pg) pg.rows };
    Array.map<(Nat, SRw.Question), (Nat, SRw.Question, [Nat])>(page, func((id, q)) { (id, q, tally(st, id, q)) })
  };

  // ── the survey ──────────────────────────────────────────────────────────────

  public func open(c : Ctx, f : SF.SurveyFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (Text.size(f.title) == 0) return #err(#titleRequired);
    if (not dayFits(f.dueDay)) return #err(#dayTooLarge { day = f.dueDay });
    if (f.dueDay != 0 and f.dueDay < c.day) return #err(#dayPassed { day = f.dueDay; today = c.day });
    let title = switch (put(c.arena, "title", f.title)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.surveys.nextSurveyId;
    RowStore.put<SRw.Survey>(c.surveys.surveys, SRw.survey, id, {
      companyId = f.companyId; title; isAnonymous = f.isAnonymous; dueDay = f.dueDay; state = #open; questions = 0; responses = 0; openedBy = c.caller; closedDay = 0; lastBlock = c.block });
    c.surveys.nextSurveyId += 1;
    #ok([id])
  };

  func openSurvey(c : Ctx, companyId : Nat, surveyId : Nat) : { #ok : SRw.Survey; #err : Refusal } {
    let ?s = RowStore.get<SRw.Survey>(c.surveys.surveys, SRw.survey, surveyId) else return #err(#noSuchSurvey { surveyId });
    if (s.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = s.companyId });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (s.state != #open) return #err(#surveyClosed { surveyId });
    #ok(s)
  };

  /// ADD A QUESTION, in order, while nobody has answered.
  public func addQuestion(c : Ctx, f : SF.QuestionFacts) : Outcome {
    let s = switch (openSurvey(c, f.companyId, f.surveyId)) { case (#err e) return #err(e); case (#ok s) s };
    if (s.responses > 0) return #err(#alreadyAnswered { surveyId = f.surveyId; responses = s.responses });
    if (s.questions >= MAX_QUESTIONS) return #err(#tooManyQuestions { max = MAX_QUESTIONS });
    if (Text.size(f.text) == 0) return #err(#textRequired);
    if (Text.size(f.text) > TA.maxLength()) return #err(#textDoesNotFit { field = "text"; max = TA.maxLength() });
    switch (f.kind) {
      case (#multiChoice) {
        if (f.options.size() < MIN_OPTIONS) return #err(#optionsRequired { min = MIN_OPTIONS });
        if (f.options.size() > MAX_OPTIONS) return #err(#tooManyOptions { max = MAX_OPTIONS });
        for (o in f.options.vals()) { if (Text.size(o) == 0 or Text.contains(o, #text SEPARATOR)) return #err(#optionEmpty) };
      };
      case (kind) { if (f.options.size() > 0) return #err(#optionsNotForKind { kind }) };
    };
    let text = switch (put(c.arena, "text", f.text)) { case (#ok r) r; case (#err e) return #err(e) };
    let joined = Text.join(f.options.vals(), SEPARATOR);
    let options = switch (put(c.arena, "options", joined)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.surveys.nextQuestionId;
    RowStore.put<SRw.Question>(c.surveys.questions, SRw.question, id, {
      companyId = f.companyId; surveyId = f.surveyId; ordinal = s.questions + 1; kind = f.kind; text; options; optionCount = f.options.size(); required = f.required; answers = 0; lastBlock = c.block });
    c.surveys.nextQuestionId += 1;
    RowStore.put<SRw.Survey>(c.surveys.surveys, SRw.survey, f.surveyId, { s with questions = s.questions + 1; lastBlock = c.block });
    #ok([id])
  };

  public func close(c : Ctx, companyId : Nat, surveyId : Nat) : Outcome {
    let s = switch (openSurvey(c, companyId, surveyId)) { case (#err e) return #err(e); case (#ok s) s };
    RowStore.put<SRw.Survey>(c.surveys.surveys, SRw.survey, surveyId, { s with state = #closed; closedDay = c.day; lastBlock = c.block });
    #ok([surveyId])
  };

  // ── the response ────────────────────────────────────────────────────────────

  /// Whether an answer fits its question: the choice within the choices, text on an open question alone.
  func fits(q : SRw.Question, questionId : Nat, a : SF.AnswerFacts) : ?Refusal {
    let n = choices(q);
    switch (q.kind) {
      case (#openText) {
        if (a.choice != 0) return ?#choiceInvalid { questionId; choice = a.choice };
        if (Text.size(a.text) == 0) return ?#textRequired;
        if (Text.size(a.text) > MAX_TEXT) return ?#textTooLong { max = MAX_TEXT };
      };
      case (_) {
        if (a.choice < 1 or a.choice > n) return ?#choiceInvalid { questionId; choice = a.choice };
        if (Text.size(a.text) > 0) return ?#textNotForKind { questionId };
      };
    };
    null
  };

  /// RESPOND: a member, once; the answers at most one per question, every required question answered, every
  /// answer held to its kind; the whole response decided before any row is written.
  public func respond(c : Ctx, f : SF.ResponseFacts) : Outcome {
    let s = switch (openSurvey(c, f.companyId, f.surveyId)) { case (#err e) return #err(e); case (#ok s) s };
    if (s.questions == 0) return #err(#noQuestions { surveyId = f.surveyId });
    if (s.dueDay != 0 and c.day > s.dueDay) return #err(#surveyOverdue { surveyId = f.surveyId; dueDay = s.dueDay; today = c.day });
    switch (responseOf(c.surveys, f.surveyId, c.caller)) { case (?_) return #err(#respondedAlready { surveyId = f.surveyId }); case null {} };
    // every answer, decided
    let checked = List.empty<(Nat, SRw.Question, SF.AnswerFacts)>();
    for (a in f.answers.vals()) {
      let ?q = RowStore.get<SRw.Question>(c.surveys.questions, SRw.question, a.questionId) else return #err(#noSuchQuestion { questionId = a.questionId });
      if (q.surveyId != f.surveyId) return #err(#questionNotOfSurvey { questionId = a.questionId; surveyId = f.surveyId });
      for ((prior, _, _) in List.values(checked)) { if (prior == a.questionId) return #err(#answeredTwice { questionId = a.questionId }) };
      switch (fits(q, a.questionId, a)) { case (?r) return #err(r); case null {} };
      List.add(checked, (a.questionId, q, a));
    };
    // every required question answered
    for ((qid, q) in questionsOf(c.surveys, f.surveyId).vals()) {
      if (q.required) {
        var answered = false;
        for ((id, _, _) in List.values(checked)) { if (id == qid) answered := true };
        if (not answered) return #err(#requiredUnanswered { questionId = qid });
      };
    };
    // nothing left that can refuse
    let rid = c.surveys.nextResponseId;
    RowStore.put<SRw.Response>(c.surveys.responses, SRw.response, rid, {
      companyId = f.companyId; surveyId = f.surveyId; respondentKey = respondentKeyOf(f.surveyId, c.caller);
      respondent = if (s.isAnonymous) nobody() else c.caller; day = c.day; answers = List.size(checked); lastBlock = c.block });
    c.surveys.nextResponseId += 1;
    let ids = List.empty<Nat>();
    List.add(ids, rid);
    for ((qid, q, a) in List.values(checked)) {
      let text = switch (put(c.arena, "answer", a.text)) { case (#ok r) r; case (#err _) TA.EMPTY };
      let aid = c.surveys.nextAnswerId;
      RowStore.put<SRw.Answer>(c.surveys.answers, SRw.answer, aid, { companyId = f.companyId; responseId = rid; questionId = qid; kind = q.kind; choice = a.choice; text; lastBlock = c.block });
      c.surveys.nextAnswerId += 1;
      RowStore.put<SRw.Question>(c.surveys.questions, SRw.question, qid, { q with answers = q.answers + 1; lastBlock = c.block });
      List.add(ids, aid);
    };
    RowStore.put<SRw.Survey>(c.surveys.surveys, SRw.survey, f.surveyId, { s with responses = s.responses + 1; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

}
