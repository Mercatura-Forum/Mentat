/// SurveyRows.mo - the survey tables: the surveys, their questions in order, the responses one per
/// respondent, and every answer as a row of its own.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  /// (survey, respondent key): one response per respondent per survey - ALWAYS keyed.
  public func respondentKey(surveyId : Nat, key : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, surveyId, W.ID);
    SR.putBlob(w, key, W.HASH);
    SR.done(w, RESPONDENT_KEY_BYTES)
  };
  public let RESPONDENT_KEY_BYTES : Nat = 38;   // ID + HASH

  // ── the survey ──────────────────────────────────────────────────────────────

  public type Survey = {
    companyId : Nat;
    title : TA.Ref;
    isAnonymous : Bool;
    /// The last day a response is taken; 0 for no end.
    dueDay : Nat;
    state : E.SurveyState;
    questions : Nat;
    responses : Nat;
    openedBy : Principal;
    closedDay : Nat;
    lastBlock : Nat;
  };

  func encodeSurvey(x : Survey) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.title);
    SR.putBool(w, x.isAnonymous);
    SR.putNat(w, x.dueDay, W.DAY);
    SR.putByte(w, E.surveyStateByte(x.state));
    SR.putNat(w, x.questions, W.ID);
    SR.putNat(w, x.responses, W.ID);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.closedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SURVEY_ROW)
  };

  func decodeSurvey(r : [Nat8]) : Survey {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let isAnonymous = SR.getBool(r, o); o += W.FLAG;
    let dueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.surveyStateOf(r[o]) else Runtime.trap("survey: unknown state byte"); o += W.ENUM;
    let questions = SR.getNat(r, o, W.ID); o += W.ID;
    let responses = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let closedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; title; isAnonymous; dueDay; state; questions; responses; openedBy; closedDay; lastBlock }
  };

  public let survey : RowStore.Decl<Survey> = {
    table = "survey";
    idBytes = W.ID;
    rowBytes = W.SURVEY_ROW;
    encode = encodeSurvey;
    decode = decodeSurvey;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Survey) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the question ────────────────────────────────────────────────────────────

  public type Question = {
    companyId : Nat;
    surveyId : Nat;
    ordinal : Nat;
    kind : E.QuestionKind;
    text : TA.Ref;
    /// The options of a choice, joined by the unit separator; empty otherwise.
    options : TA.Ref;
    optionCount : Nat;
    required : Bool;
    answers : Nat;
    lastBlock : Nat;
  };

  func encodeQuestion(x : Question) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.surveyId, W.ID);
    SR.putNat(w, x.ordinal, W.ID);
    SR.putByte(w, E.questionKindByte(x.kind));
    TA.putRef(w, x.text);
    TA.putRef(w, x.options);
    SR.putNat(w, x.optionCount, W.ID);
    SR.putBool(w, x.required);
    SR.putNat(w, x.answers, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SURVEY_QUESTION_ROW)
  };

  func decodeQuestion(r : [Nat8]) : Question {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let surveyId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.questionKindOf(r[o]) else Runtime.trap("question: unknown kind byte"); o += W.ENUM;
    let text = TA.getRef(r, o); o += W.ARENA_REF;
    let options = TA.getRef(r, o); o += W.ARENA_REF;
    let optionCount = SR.getNat(r, o, W.ID); o += W.ID;
    let required = SR.getBool(r, o); o += W.FLAG;
    let answers = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; surveyId; ordinal; kind; text; options; optionCount; required; answers; lastBlock }
  };

  public let question : RowStore.Decl<Question> = {
    table = "survey_question";
    idBytes = W.ID;
    rowBytes = W.SURVEY_QUESTION_ROW;
    encode = encodeQuestion;
    decode = decodeQuestion;
    indexes = [
      { name = "by_survey_ordinal_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : Question) : ?Blob { ?PR.pairKey(x.surveyId, x.ordinal) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Question) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the response ────────────────────────────────────────────────────────────

  public type Response = {
    companyId : Nat;
    surveyId : Nat;
    /// The respondent as a key - the survey and the principal hashed - so a second response is refused
    /// even where the name is not kept.
    respondentKey : Blob;
    /// The respondent, or nobody when the survey is anonymous.
    respondent : Principal;
    day : Nat;
    answers : Nat;
    lastBlock : Nat;
  };

  func encodeResponse(x : Response) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.surveyId, W.ID);
    SR.putBlob(w, x.respondentKey, W.HASH);
    F.putPrincipal(w, x.respondent);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.answers, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SURVEY_RESPONSE_ROW)
  };

  func decodeResponse(r : [Nat8]) : Response {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let surveyId = SR.getNat(r, o, W.ID); o += W.ID;
    let respondentKey = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let respondent = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let answers = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; surveyId; respondentKey; respondent; day; answers; lastBlock }
  };

  public let response : RowStore.Decl<Response> = {
    table = "survey_response";
    idBytes = W.ID;
    rowBytes = W.SURVEY_RESPONSE_ROW;
    encode = encodeResponse;
    decode = decodeResponse;
    indexes = [
      { name = "by_respondent_one"; keyBytes = RESPONDENT_KEY_BYTES;
        keyOf = func(_id : Nat, x : Response) : ?Blob { ?respondentKey(x.surveyId, x.respondentKey) } },
      { name = "by_survey"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Response) : ?Blob { ?PR.pairKey(x.surveyId, id) } },
    ];
  };

  // ── the answer ──────────────────────────────────────────────────────────────

  public type Answer = {
    companyId : Nat;
    responseId : Nat;
    questionId : Nat;
    kind : E.QuestionKind;
    /// 1 or 2 for no or yes; 1 to 5 for a rating; the option's number for a choice; 0 for text.
    choice : Nat;
    text : TA.Ref;
    lastBlock : Nat;
  };

  func encodeAnswer(x : Answer) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.responseId, W.ID);
    SR.putNat(w, x.questionId, W.ID);
    SR.putByte(w, E.questionKindByte(x.kind));
    SR.putNat(w, x.choice, W.ID);
    TA.putRef(w, x.text);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SURVEY_ANSWER_ROW)
  };

  func decodeAnswer(r : [Nat8]) : Answer {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let responseId = SR.getNat(r, o, W.ID); o += W.ID;
    let questionId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.questionKindOf(r[o]) else Runtime.trap("answer: unknown kind byte"); o += W.ENUM;
    let choice = SR.getNat(r, o, W.ID); o += W.ID;
    let text = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; responseId; questionId; kind; choice; text; lastBlock }
  };

  public let answer : RowStore.Decl<Answer> = {
    table = "survey_answer";
    idBytes = W.ID;
    rowBytes = W.SURVEY_ANSWER_ROW;
    encode = encodeAnswer;
    decode = decodeAnswer;
    indexes = [
      // the tally: every answer to one question
      { name = "by_question"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Answer) : ?Blob { ?PR.pairKey(x.questionId, id) } },
      { name = "by_response"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Answer) : ?Blob { ?PR.pairKey(x.responseId, id) } },
    ];
  };

}
