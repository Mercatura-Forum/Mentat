/// EtaSubmit.mo - the two requests a filing makes to the tax authority, and how their answers are
/// read.
///
/// THE AUTHORITY'S API, AS ITS SDK STATES IT (read 2026-09-20, statuses in the references):
///
///   POST {identity}/connect/token          OAuth 2.0 client credentials: `Authorization: Basic
///                                          base64(clientId:clientSecret)`, form body
///                                          `grant_type=client_credentials&scope=InvoicingAPI`;
///                                          answers `{ access_token, token_type, expires_in }`.
///   POST {api}/api/v1.0/documentsubmissions  `Authorization: Bearer <token>`, JSON body
///                                          `{ documents: [ … ] }`; answers 202 with
///                                          `{ submissionUUID, acceptedDocuments: [ { uuid, longId,
///                                          internalId } ], rejectedDocuments: [ { internalId,
///                                          error: { code, message, target, details } } ] }`,
///                                          or an error with `{ code, message }`.
///
/// EVERY REQUEST IS AT QUORUM ONE. On this substrate an outbound call is fetched by as many
/// validators as the request's quorum says, and the answer they agree on is delivered. A filing is
/// not idempotent at the authority - a second submission of the same document is a duplicate - so
/// exactly one validator makes it. `tools/outcall_and_secrets.sh` requires every request built in
/// this tree to say so, with a control that raises the quorum and must be caught.
///
/// THE CREDENTIAL NEVER ENTERS A COMMAND OR A ROW. The client id and secret are the actor's own
/// variables, installed by the company's administrator through a method that writes no block and no
/// row, and read here at the moment the login request is built. The bearer token the login returns
/// lives in the actor for its hour and is never written anywhere either.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Text "mo:core/Text";

import Base64 "mo:kernel/codec/Base64";
import Json "mo:kernel/codec/JsonTree";

module {

  /// The largest answer either request may return. The authority's answers are small; a bound is
  /// part of the agreement, so an oversize answer is a deterministic refusal.
  public let MAX_RESPONSE_BYTES : Nat = 65_536;

  /// An outbound request as this module decides it. The actor turns it into the substrate's own
  /// request record; this module does not import the substrate's surface, so every battery can
  /// build and inspect a request under a compiler that has no substrate.
  public type Request = {
    url : Text;
    headers : [(Text, Text)];
    body : Blob;
    /// How many validators fetch it. One, always: a filing is not idempotent at the authority.
    quorum : Nat;
    maxResponseBytes : Nat;
  };

  /// The login: client credentials, form-encoded, at quorum one.
  public func loginRequest(identityEndpoint : Text, clientId : Text, clientSecret : Text) : Request {
    let basic = Base64.encode(Text.encodeUtf8(clientId # ":" # clientSecret));
    {
      url = identityEndpoint # "/connect/token";
      headers = [("Authorization", "Basic " # basic), ("Content-Type", "application/x-www-form-urlencoded")];
      body = Text.encodeUtf8("grant_type=client_credentials&scope=InvoicingAPI");
      quorum = 1;
      maxResponseBytes = MAX_RESPONSE_BYTES;
    }
  };

  /// The submission: the sealed document inside the API's envelope, at quorum one.
  public func submissionRequest(apiEndpoint : Text, bearer : Text, body : Text) : Request {
    {
      url = apiEndpoint # "/api/v1.0/documentsubmissions";
      headers = [("Authorization", "Bearer " # bearer), ("Content-Type", "application/json")];
      body = Text.encodeUtf8(body);
      quorum = 1;
      maxResponseBytes = MAX_RESPONSE_BYTES;
    }
  };

  // ── reading the answers ─────────────────────────────────────────────────────

  /// The access token from a login answer, or why not.
  public func readToken(status : Nat, body : Blob) : { #ok : { token : Text; expiresIn : Nat }; #err : Text } {
    let ?text = Text.decodeUtf8(body) else return #err("the login answer is not UTF-8");
    switch (Json.parse(text)) {
      case (#err e) #err("the login answer is not JSON: " # e);
      case (#ok j) {
        if (status != 200) {
          let code = switch (Json.str(j, "error")) { case (?c) c; case null Nat.toText(status) };
          let why = switch (Json.str(j, "error_description")) { case (?d) ": " # d; case null "" };
          return #err("login refused, " # code # why);
        };
        let ?token = Json.str(j, "access_token") else return #err("the login answer carries no access_token");
        let expiresIn = switch (Json.get(j, "expires_in")) { case (?#number n) { switch (Nat.fromText(n)) { case (?v) v; case null 0 } }; case _ 0 };
        #ok({ token; expiresIn })
      };
    }
  };

  public type Accepted = { uuid : Text; longId : Text; internalId : Text };
  public type Rejected = { internalId : Text; code : Text; message : Text };
  public type SubmissionAnswer = {
    submissionUuid : Text;
    accepted : [Accepted];
    rejected : [Rejected];
  };

  /// What the authority said to a submission: the identifiers it assigned, or the errors it gave,
  /// or - for a status that is not an acceptance - the error the whole call was refused with.
  /// The authority's answer to a submission: accepted and rejected documents; or a refusal of the
  /// whole submission; or - `#duplicate` - the authority's word that it saw an identical submission
  /// from this taxpayer within the past ten minutes (its own 422 DuplicateSubmission), which is
  /// NOT this filing's answer: the first submission's answer stands, and this one is not to be
  /// folded as a rejection. On a substrate whose every validator fetches an outcall, this is the
  /// answer all but one of them receive.
  public func readSubmission(status : Nat, body : Blob) : { #ok : SubmissionAnswer; #duplicate : Text; #err : Text } {
    let ?text = Text.decodeUtf8(body) else return #err("the submission answer is not UTF-8");
    switch (Json.parse(text)) {
      case (#err e) #err("the submission answer is not JSON: " # e);
      case (#ok j) {
        if (status != 202 and status != 200) {
          let code = switch (Json.str(j, "code")) { case (?c) c; case null { switch (Json.obj(j, "error")) { case (?er) { switch (Json.str(er, "code")) { case (?c) c; case null Nat.toText(status) } }; case null Nat.toText(status) } } };
          let why = switch (Json.str(j, "message")) { case (?m) ": " # m; case null { switch (Json.obj(j, "error")) { case (?er) { switch (Json.str(er, "message")) { case (?m) ": " # m; case null "" } }; case null "" } } };
          if (status == 422 and code == "DuplicateSubmission") return #duplicate(code # why);
          return #err("submission refused with " # code # why);
        };
        let submissionUuid = switch (Json.str(j, "submissionUUID")) { case (?u) u; case null switch (Json.str(j, "submissionUuid")) { case (?u) u; case null "" } };
        let accepted = switch (Json.arr(j, "acceptedDocuments")) {
          case null [];
          case (?xs) {
            var out : [Accepted] = [];
            for (x in xs.vals()) {
              out := arrayAppend(out, {
                uuid = switch (Json.str(x, "uuid")) { case (?v) v; case null "" };
                longId = switch (Json.str(x, "longId")) { case (?v) v; case null "" };
                internalId = switch (Json.str(x, "internalId")) { case (?v) v; case null "" };
              });
            };
            out
          };
        };
        let rejected = switch (Json.arr(j, "rejectedDocuments")) {
          case null [];
          case (?xs) {
            var out : [Rejected] = [];
            for (x in xs.vals()) {
              let (code, message) = switch (Json.obj(x, "error")) {
                case (?er) (switch (Json.str(er, "code")) { case (?c) c; case null "" }, switch (Json.str(er, "message")) { case (?m) m; case null "" });
                case null ("", "");
              };
              out := arrayAppend(out, { internalId = switch (Json.str(x, "internalId")) { case (?v) v; case null "" }; code; message });
            };
            out
          };
        };
        #ok({ submissionUuid; accepted; rejected })
      };
    }
  };

  func arrayAppend<T>(a : [T], x : T) : [T] { Array.concat<T>(a, [x]) };
}
