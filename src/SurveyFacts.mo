/// SurveyFacts.mo - the payloads the survey commands carry: a survey opened, a question added, a response
/// with its answers.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A survey: its title, whether responses are kept without the respondent's name, and the last day it
  /// takes responses (0 for no end).
  public type SurveyFacts = {
    companyId : Nat;
    title : Text;
    isAnonymous : Bool;
    dueDay : Nat;
  };

  /// A question added to a survey nobody has answered yet: its kind, its text, its options (for a choice),
  /// and whether every response must answer it.
  public type QuestionFacts = {
    companyId : Nat;
    surveyId : Nat;
    kind : E.QuestionKind;
    text : Text;
    options : [Text];
    required : Bool;
  };

  /// One answer: the question, a choice (1 or 2 for no or yes, 1 to 5 for a rating, the option's number
  /// for a choice, 0 for text) and the text (for an open question).
  public type AnswerFacts = {
    questionId : Nat;
    choice : Nat;
    text : Text;
  };

  /// A response: the respondent is the caller; the answers at most one per question.
  public type ResponseFacts = {
    companyId : Nat;
    surveyId : Nat;
    answers : [AnswerFacts];
  };

}
