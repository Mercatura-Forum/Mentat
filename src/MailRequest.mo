/// MailRequest.mo - the outbound mail request, built and checkable.
///
/// TWO THINGS THE RECEIVED SEND GETS WRONG, AND THEY ARE BOTH IN THE REQUEST:
///
///   1. `crm.mo:923` passes `is_replicated = null`, which is the REPLICATED default. In that mode
///      every node of the subnet issues the request independently and the provider receives one
///      copy per validator; for a `GET` of a price that is merely wasteful, and for a `POST` that
///      SENDS MAIL it means every validator of the subnet delivers the campaign once. An
///      outcall that is not idempotent at the provider must be unreplicated. `is_replicated` is
///      `?false` here and `tools/outcall_and_secrets.sh` fails the build if it is anything else.
///   2. `sendgridApiKey : Text` is a public method argument, travelling in the clear in every
///      ingress message. The secret is a parameter of this function and comes from the key ring at
///      the edge; no command carries it, and no method signature mentions it.
///
/// This module builds the request and does not issue it: issuing belongs to the actor, which has
/// the substrate and the transform closure. What can be got wrong deterministically - 
/// the replication flag, the authorization header, the recipient list, the JSON - is got right
/// here, where a battery can read it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";
import Nat64 "mo:core/Nat64";
import Text "mo:core/Text";

import O "Outcall";

module {

  public type Header = O.Header;
  public type Method = O.Method;
  public type Request = O.Request;

  public type Recipient = { recipientId : Nat; address : Text };

  public type Spec = {
    subject : Text;
    emailFrom : Text;
    bodyHtml : Text;
    /// Empty for none.
    replyTo : Text;
    recipients : [Recipient];
  };

  public let ENDPOINT : Text = "https://api.sendgrid.com/v3/mail/send";

  /// A send's response is a status line and a short body; 4 KiB bounds what the subnet will pay
  /// to receive and is well past what the provider returns on success or on error.
  public let MAX_RESPONSE_BYTES : Nat64 = 4_096;

  /// Build one send.
  ///
  /// `secret` is the provider credential, read from the key ring by the caller. It appears in the
  /// authorization header of the request and nowhere else - not in a command, not in a row, not in
  /// a method signature.
  public func build(spec : Spec, secret : Text) : Request {
    {
      url = ENDPOINT;
      max_response_bytes = ?MAX_RESPONSE_BYTES;
      method = #post;
      headers = [
        { name = "Authorization"; value = "Bearer " # secret },
        { name = "Content-Type"; value = "application/json" },
        { name = "Accept"; value = "application/json" },
      ];
      body = ?Text.encodeUtf8(json(spec));
      // UNREPLICATED. See the note at the head of this module: the replicated default delivers
      // the campaign once per node.
      is_replicated = ?false;
    }
  };

  /// The SendGrid v3 payload. One personalization per recipient, each carrying the recipient ROW's
  /// id in `custom_args`, so a delivery or bounce event can be matched back to the row it belongs
  /// to rather than to an address that several leads may share.
  public func json(spec : Spec) : Text {
    var out = "{\"personalizations\":[";
    var first = true;
    for (r in spec.recipients.vals()) {
      if (not first) out #= ",";
      first := false;
      out #= "{\"to\":[{\"email\":" # str(r.address) # "}],"
           # "\"custom_args\":{\"recipient_id\":" # str(Nat.toText(r.recipientId)) # "}}";
    };
    out #= "],\"from\":{\"email\":" # str(spec.emailFrom) # "}";
    if (spec.replyTo != "") {
      out #= ",\"reply_to\":{\"email\":" # str(spec.replyTo) # "}";
    };
    out #= ",\"subject\":" # str(spec.subject)
         # ",\"content\":[{\"type\":\"text/html\",\"value\":" # str(spec.bodyHtml) # "}]}";
    out
  };

  /// A JSON string literal, from the shared builder so both outbound paths escape the same way.
  public func str(t : Text) : Text { O.str(t) };

  /// The bytes of the body, for a battery that wants to measure rather than read.
  public func bodyBytes(r : Request) : Nat { O.bodyBytes(r) };

}
