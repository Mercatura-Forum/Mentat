/// ReadRules.mo - the read method's rules per record: the kinds whose rows are read row by row, each by whom another
/// row names. `ReadSurface.cutFor` admits a
/// member in standing in a role that acts to a kind of the class `rule`; each function here then decides one row for
/// that reader, from the row, the rows it names and the role the reader holds. `tools/read_surface.py` holds every kind
/// of the class to a function of its name here, and the Read battery holds each rule to its rows.
///
///   channel           a public channel, to every member who acts; a private one, to those in it now
///   channel_member    who is in a channel, to whoever reads the channel
///   channel_message   what is said in a public channel, to every member who acts; in a private one, to those in it
///                     now; a deleted message to nobody, its words being kept in the row
///   notification      to the person it is addressed to, and to nobody else - the administrator included
///   survey_response   a named survey's response, to its respondent, the member who opened the survey, HR and the
///                     administrator; an anonymous survey's, to nobody row by row (its respondent is a key alone, and a
///                     key of a principal is found again by hashing the members' principals)
///   survey_answer     as the response it is part of
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Principal "mo:core/Principal";

import RowStore "mo:kernel/rows/RowStore";

import DscFold "DscFold";
import DscRows "DscRows";
import E "Enums";
import St "State";
import SurveyRows "SurveyRows";

module {

  func seesChannel(s : St.State, channelId : Nat, ch : DscRows.Channel, reader : Principal) : Bool {
    not ch.isPrivate or DscFold.isIn(s.dsc, channelId, reader)
  };

  public func channel(s : St.State, id : Nat, r : DscRows.Channel, reader : Principal, _held : E.CompanyRole) : Bool {
    seesChannel(s, id, r, reader)
  };

  public func channel_member(s : St.State, _id : Nat, r : DscRows.ChannelMember, reader : Principal, _held : E.CompanyRole) : Bool {
    switch (RowStore.get<DscRows.Channel>(s.dsc.channels, DscRows.channel, r.channelId)) {
      case (?ch) seesChannel(s, r.channelId, ch, reader);
      case null false;
    }
  };

  public func channel_message(s : St.State, _id : Nat, r : DscRows.ChannelMessage, reader : Principal, _held : E.CompanyRole) : Bool {
    if (r.isDeleted) return false;
    switch (RowStore.get<DscRows.Channel>(s.dsc.channels, DscRows.channel, r.channelId)) {
      case (?ch) seesChannel(s, r.channelId, ch, reader);
      case null false;
    }
  };

  public func notification(_s : St.State, _id : Nat, r : DscRows.Notification, reader : Principal, _held : E.CompanyRole) : Bool {
    r.recipient == reader
  };

  func seesResponse(s : St.State, r : SurveyRows.Response, reader : Principal, held : E.CompanyRole) : Bool {
    switch (RowStore.get<SurveyRows.Survey>(s.surveys.surveys, SurveyRows.survey, r.surveyId)) {
      case (?sv) {
        not sv.isAnonymous and (r.respondent == reader or sv.openedBy == reader or held == #HR or held == #CompanyAdmin)
      };
      case null false;
    }
  };

  public func survey_response(s : St.State, _id : Nat, r : SurveyRows.Response, reader : Principal, held : E.CompanyRole) : Bool {
    seesResponse(s, r, reader, held)
  };

  public func survey_answer(s : St.State, _id : Nat, r : SurveyRows.Answer, reader : Principal, held : E.CompanyRole) : Bool {
    switch (RowStore.get<SurveyRows.Response>(s.surveys.responses, SurveyRows.response, r.responseId)) {
      case (?resp) seesResponse(s, resp, reader, held);
      case null false;
    }
  };
}
