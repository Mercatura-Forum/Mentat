/// Identity.mo - a person signed in with a Memphis passkey, as this contract knows them.
///
/// A browser signs every update with its own key (the chain refuses an unsigned call that names a sender), and the
/// person behind it signs in to Memphis with a passkey. Memphis mints a session token SCOPED TO ONE WEB ORIGIN - the
/// one this contract is configured with as its audience - and refuses it at every other, so a token handed to some
/// other application cannot act here, and one handed here cannot act there (an audience restriction, as OAuth's `aud`,
/// RFC 9068, and per-origin delegation). The contract asks Memphis who the token belongs to
/// (`whoami_scoped_u`) and the person's STABLE principal for this application's namespace (`derive_principal_for_u`),
/// and acts as that principal: it is the caller every fold, the gate and the audit index see, and the caller the
/// block records. A company admits a person by that principal, so the browser's own key, which changes with the
/// browser, never holds a role.
///
/// This is thebes-lib's `MemphisAuth` (v1.0.0, Apache 2.0) restated for this tree with three differences: a session
/// is bound to the browser that first presents it; the rules are plain functions around the two calls, which the
/// contract makes; and it reads no clock. The session's expiry is compared with the time the contract's substrate
/// `Source` gives (`tools/no_direct_clock.sh`: one file supplies time, and this is not it). The two Memphis methods are bound to their
/// update forms (`_u`), as thebes-lib states, because a contract-to-contract await on a query export gets no reply on
/// this substrate. The module holds every rule as a plain function - `begin` before the two calls, `settle` after
/// them - and the contract makes the calls between, so each rule is proved by a battery that makes no call.
///
/// THE NAMESPACE IS SET ONCE. `origin` decides every person's principal (`derive_principal_for_u(anchor, origin,
/// version)`); changing it would give every member a new principal and orphan every role. So the platform operator
/// configures the identity contract, its namespace and the audience once; afterwards the identity contract and the
/// audience may be moved (a new Memphis id, a new web address), the namespace and the version never.
///
/// A verified session is kept until its expiry, so a query can name the person (a query cannot await). THE BINDING
/// BELOW IS ONLY AS GOOD AS THE ENTRY THAT HOLDS IT, so the table fails closed: a session it cannot keep is refused, never
/// let act unbound. It holds at most `CACHE_MAX` sessions, the expired ones dropped when it fills, and at most
/// `PERSON_MAX` for one person, so filling it takes that many people's passkeys and not one person's many sign-ins.
///
/// SIGNING OUT ENDS THE TOKEN HERE. Memphis's own sign-out is the browser forgetting the token (memphis-connect.js
/// `signOut`); the token itself lives on at Memphis until its expiry. So `closeSession` does not drop the entry, which
/// would let whoever copied the token bind it afresh: it marks the entry signed out, and the token is refused here, from
/// every browser, until it would have expired (revocation as RFC 7009 states it: a revoked token is refused for the rest
/// of its life). Signing in again mints a new token.
///
/// A SESSION IS HELD BY THE BROWSER THAT OPENED IT. The token is a bearer secret; the browser key that signs each call
/// is not. The first signed call that verifies a token here binds the session to that call's sender, and while the
/// session lives every call presenting the token under another sender is refused - a token copied out of a browser
/// does not act from somewhere else (the sender-constraint of OAuth's DPoP, RFC 9449, with the chain's own signature
/// on every call as the proof of possession). An anonymous call presents no token at all. The proof is the UPDATE's: a
/// query on this substrate names its sender unsigned (the node takes a query's `sender` as given), so a query answered
/// under a session (`whoAmI`, the `…As` reads) asks for the token and the holder's principal together and proves
/// neither's possession - what such a read returns is what the audit index already serves, and no more.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0. After thebes-lib MemphisAuth (Mercatura-Forum, Apache 2.0).

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Iter "mo:core/Iter";
import Map "mo:core/Map";
import Nat "mo:core/Nat";
import Nat64 "mo:core/Nat64";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import C "mo:kernel/codec/Canonical";

import Clk "ClockWiring";

module {

  /// Memphis's errors, mirrored from its interface.
  public type MemphisError = {
    #NotAuthenticated;
    #Unauthorized;
    #SessionExpired;
    #ChallengeExpired;
    #AnchorNotFound;
    #FactorNotFound;
    #InsufficientFactors;
    #DuplicateCredential;
    #InvalidArgument : Text;
    #InvariantViolation : { id : Text; details : Text };
  };

  /// `anchor_id` is the anchor's hash, never the anchor.
  public type WhoAmI = { anchor_id : Blob; session_expires_ns : Nat64; display_tag : Text };

  /// The two methods of Memphis this contract calls, in their update forms.
  public type Memphis = actor {
    whoami_scoped_u : (Blob, Text) -> async ({ #Ok : WhoAmI; #Err : MemphisError });
    derive_principal_for_u : (Blob, Text, Nat64) -> async ({ #Ok : Blob; #Err : MemphisError });
  };

  /// The identity contract (its numeric id on the chain), the namespace principals are derived under, the scheme's
  /// version, and the web origin tokens are minted for.
  public type Config = { memphisCid : Nat; origin : Text; version : Nat64; audience : Text };

  /// `open` is false once the holder signed out: the entry then stands only to refuse the token until its expiry.
  public type Session = { principal : Principal; expiresNs : Nat64; holder : Principal; open : Bool };

  public type State = {
    var config : ?Config;
    var sessions : Map.Map<Blob, Session>;
    /// how many entries of `sessions` name each person, signed out or not
    var perPerson : Map.Map<Principal, Nat>;
  };

  public let CACHE_MAX : Nat = 100_000;
  public let PERSON_MAX : Nat = 32;
  /// A token is at most this many bytes (Memphis's are 32); an origin or an audience at most this many characters.
  public let TOKEN_MAX : Nat = 256;
  public let NAME_MAX : Nat = 256;

  public func newState() : State { { var config = null; var sessions = Map.empty<Blob, Session>(); var perPerson = Map.empty<Principal, Nat>() } };

  /// The 8 big-endian bytes of a numeric contract id: how this substrate names a callee.
  public func principalOfCid(cid : Nat) : Principal {
    Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(8, func(i) { Nat8.fromNat((cid / (256 ** (7 - i : Nat))) % 256) })))
  };

  /// CONFIGURE the identity contract, by the platform operator (the caller is checked by the contract). The first
  /// configuration names all four; a later one may move the identity contract and the audience, never the namespace
  /// or the version.
  public func configure(s : State, memphisCid : Nat, origin : Text, version : Nat64, audience : Text) : { #ok; #err : Text } {
    if (memphisCid == 0 or memphisCid >= 2 ** 64) return #err("an identity contract is a numeric id of the chain, 1 to 2^64 - 1");
    if (Text.size(origin) == 0 or Text.size(origin) > NAME_MAX) return #err("a namespace of 1 to " # Nat.toText(NAME_MAX) # " characters");
    if (Text.size(audience) == 0 or Text.size(audience) > NAME_MAX) return #err("an audience of 1 to " # Nat.toText(NAME_MAX) # " characters");
    switch (s.config) {
      case (?c) {
        if (c.origin != origin or c.version != version) {
          return #err("the namespace and the version are set once: changing them would give every member a new principal");
        };
        // a new identity contract or a new address: the sessions verified by the old ones are dropped (a token minted
        // for the old address or by the old contract is refused by the new one, so no signed-out mark is needed)
        s.sessions := Map.empty<Blob, Session>();
        s.perPerson := Map.empty<Principal, Nat>();
      };
      case null {};
    };
    s.config := ?{ memphisCid; origin; version; audience };
    #ok
  };

  /// A token as the browser carries it: hex text.
  public func tokenOf(hex : Text) : ?Blob {
    switch (C.fromHex(hex)) {
      case (?b) { if (b.size() == 0 or b.size() > TOKEN_MAX) null else ?b };
      case null null;
    }
  };

  /// What a person is told when Memphis refuses.
  public func why(e : MemphisError) : Text {
    switch (e) {
      case (#Unauthorized) "the session was opened for another site";
      case (#SessionExpired) "the session has ended; sign in again";
      case (#NotAuthenticated) "no session goes by that token";
      case _ "the sign-in could not be checked";
    }
  };

  /// A session already verified, held by `holder` and not yet expired at the substrate's time, or null. Read by queries, which
  /// cannot await.
  public func cached(s : State, token : Blob, holder : Principal, source : Clk.Source) : ?Principal {
    let nowNs = source.substrateNow();
    if (Principal.isAnonymous(holder)) return null;
    switch (Map.get(s.sessions, Blob.compare, token)) {
      case (?x) { if (x.open and x.expiresNs > nowNs and x.holder == holder) ?x.principal else null };
      case null null;
    }
  };

  /// How many entries name `p`.
  public func heldBy(s : State, p : Principal) : Nat { switch (Map.get(s.perPerson, Principal.compare, p)) { case (?n) n; case null 0 } };

  func drop(s : State, token : Blob) {
    switch (Map.take(s.sessions, Blob.compare, token)) {
      case (?x) {
        let n = heldBy(s, x.principal);
        if (n <= 1) ignore Map.delete(s.perPerson, Principal.compare, x.principal) else Map.add(s.perPerson, Principal.compare, x.principal, n - 1 : Nat);
      };
      case null {};
    };
  };

  func purge(s : State, source : Clk.Source) {
    let nowNs = source.substrateNow();
    let stale = Iter.toArray(Iter.filterMap<(Blob, Session), Blob>(Map.entries(s.sessions), func((k, v)) { if (v.expiresNs <= nowNs) ?k else null }));
    for (k in stale.values()) drop(s, k);
  };

  /// Keep a session, or say why it cannot be kept. Nothing is ever evicted that has not expired: an evicted binding
  /// would let a copied token act unbound.
  func remember(s : State, token : Blob, x : Session, source : Clk.Source) : ?Text {
    if (Map.size(s.sessions) >= CACHE_MAX or heldBy(s, x.principal) >= PERSON_MAX) purge(s, source);
    if (Map.size(s.sessions) >= CACHE_MAX) return ?FULL;
    if (heldBy(s, x.principal) >= PERSON_MAX) return ?PERSON_FULL;
    Map.add(s.sessions, Blob.compare, token, x);
    Map.add(s.perPerson, Principal.compare, x.principal, heldBy(s, x.principal) + 1);
    null
  };

  /// WHO A TOKEN SIGNS IN, in two halves around the two calls to Memphis, which the contract makes (`Mentat.mo`
  /// `person`): every rule is here, and the contract only carries the answers across.
  ///
  /// BEFORE THE CALLS: a session held here and not ended is answered at once (or refused, if another browser holds
  /// it); one ended is dropped; otherwise the configuration to ask Memphis under.
  public func begin(s : State, token : Blob, holder : Principal, source : Clk.Source) : { #known : Principal; #ask : Config; #err : Text } {
    let ?c = s.config else return #err("no identity contract is configured");
    if (Principal.isAnonymous(holder)) return #err("sign the call: a session is presented only by a signed call");
    switch (Map.get(s.sessions, Blob.compare, token)) {
      case (?x) {
        if (x.expiresNs > source.substrateNow()) {
          return if (not x.open) #err(SIGNED_OUT) else if (x.holder == holder) #known(x.principal) else #err(HELD);
        };
        drop(s, token);
      };
      case null {};
    };
    #ask(c)
  };

  let HELD = "this session is held by another browser; sign in here";
  let SIGNED_OUT = "this session was signed out; sign in again";
  let FULL = "this contract holds as many open sessions as it may; sign in again once others have ended";
  let PERSON_FULL = "you have 32 sessions open here (PERSON_MAX); sign out of one, or wait for one to end";

  /// AFTER THE CALLS: Memphis's answers - the session's expiry from `whoami_scoped_u` and the principal from
  /// `derive_principal_for_u` - under the configuration `asked`. Checked against the substrate's time AFTER both
  /// answers, against the configuration as it stands now (it may have moved while the contract awaited) and against
  /// any binding another call made meanwhile (the first holds); then the session is kept, bound to `holder`.
  public func settle(s : State, token : Blob, holder : Principal, asked : Config, expiresNs : Nat64, derived : Blob, source : Clk.Source) : { #ok : Principal; #err : Text } {
    if (derived.size() == 0 or derived.size() > 29) return #err("the identity contract gave no principal");
    let p = Principal.fromBlob(derived);
    if (Principal.isAnonymous(p)) return #err("the identity contract gave the anonymous principal");
    let nowNs = source.substrateNow();
    if (expiresNs <= nowNs) return #err("the session has ended; sign in again");
    switch (s.config) {
      case (?c) { if (c != asked) return #err("the identity contract was reconfigured; sign in again") };
      case null return #err("no identity contract is configured");
    };
    switch (Map.get(s.sessions, Blob.compare, token)) {
      case (?x) {
        if (x.expiresNs > nowNs) {
          // another call settled this token while this one awaited: the first holds, and a sign-out meanwhile stands
          if (not x.open) return #err(SIGNED_OUT);
          if (x.holder != holder) return #err(HELD);
          return #ok(x.principal);
        };
        drop(s, token);
      };
      case null {};
    };
    switch (remember(s, token, { principal = p; expiresNs; holder; open = true }, source)) {
      case (?why) #err(why);
      case null #ok(p);
    }
  };

  /// SIGN OUT, by the browser holding the session: the token is refused here from then until its expiry, from every
  /// browser. True when an open session was signed out.
  public func forget(s : State, token : Blob, holder : Principal) : Bool {
    switch (Map.get(s.sessions, Blob.compare, token)) {
      case (?x) {
        if (x.holder != holder or not x.open) return false;
        Map.add(s.sessions, Blob.compare, token, { x with open = false });
        true
      };
      case null false;
    }
  };
}
