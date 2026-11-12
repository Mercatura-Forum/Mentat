/// BlogFold.mo - the blog: posts as published documents with an author and a date from the calendar.
///
/// A POST IS A PAGE WITH A BYLINE AND A DAY. Its bytes are a company document the fold reads whole from
/// the evidence store and finds to be its own plaintext, exactly as the website's pages are; its
/// AUTHOR is the member who published it and nobody a form names; its DATE is the calendar's business
/// day when the command was folded and no day a caller states, so a post cannot be back-dated or
/// post-dated by the person writing it. Revised, the post carries another document under the same
/// slug with the day of first publication kept and the day of revision beside it; withdrawn, it is
/// listed and served no more; published again under its slug, it stands again as a further revision.
///
/// THE READ SURFACE LISTS AND SERVES IT: `/sites/<slug>/blog` is the index - the live posts newest
/// first, each its title (escaped), its date as the calendar writes it and its link - and
/// `/sites/<slug>/blog/<post>` the post's bytes under their content type, with the publication block,
/// the revision and the fingerprint recomputed from the bytes in the headers.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Char "mo:core/Char";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import CivilDate "mo:kernel/num/CivilDate";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import BF "BlogFacts";
import BR "BlogRows";
import EF "EvFold";
import F "Fields";
import SFold "SiteFold";
import SiteRows "SiteRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    /// A slug is lower-case letters, digits and hyphens, neither starting nor ending with one, at
    /// most the field.
    #slugInvalid : { slug : Text; why : Text };
    /// A live post holds the slug.
    #slugTaken : { slug : Text; postId : Nat };
    #titleRequired;
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #noSuchPost : { postId : Nat };
    #postWithdrawn : { postId : Nat };
    /// The website's own refusal of the document or the content type: not the company's, not a
    /// company document, archived or erased, too large, not its own plaintext.
    #site : SFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#slugInvalid { slug; why }) "slug \"" # slug # "\": " # why;
      case (#slugTaken { slug; postId }) "slug \"" # slug # "\" is post " # Nat.toText(postId) # "'s";
      case (#titleRequired) "a post needs a title";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#noSuchPost { postId }) "no post " # Nat.toText(postId);
      case (#postWithdrawn { postId }) "post " # Nat.toText(postId) # " is withdrawn";
      case (#site r) SFold.refusalText(r);
    }
  };

  public type Stores = {
    var posts : RowStore.Store;
    var nextPostId : Nat;
  };

  public func newStores() : Stores {
    { var posts = RowStore.newStore<BR.Post>(BR.post); var nextPostId = 1 }
  };

  public type Ctx = {
    blog : Stores;
    /// The documents and the evidence store they point into: read, never written.
    evs : EF.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  /// What the index lists at most: the newest.
  public let INDEX_LIMIT : Nat = 50;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func all<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for (row in pg.rows.vals()) List.add(out, row);
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  func slugChar(ch : Char) : Bool { let n = Char.toNat32(ch); (n >= 97 and n <= 122) or Char.isDigit(ch) or ch == '-' };

  /// A slug's field, or the reason it is not one.
  public func slugField(slug : Text) : { #ok : Blob; #err : Refusal } {
    if (Text.size(slug) == 0) return #err(#slugInvalid { slug; why = "a slug is required" });
    for (ch in slug.chars()) { if (not slugChar(ch)) return #err(#slugInvalid { slug; why = "a slug is lower-case letters, digits and hyphens" }) };
    if (Text.startsWith(slug, #text "-") or Text.endsWith(slug, #text "-")) return #err(#slugInvalid { slug; why = "a slug neither starts nor ends with a hyphen" });
    let ?field = F.textField(slug, W.PATH) else return #err(#slugInvalid { slug; why = "a slug is at most " # Nat.toText(W.PATH) # " bytes" });
    #ok(field)
  };

  /// THE DATE AS THE CALENDAR WRITES IT: the day as year-month-day.
  public func isoDate(day : Nat) : Text {
    let (y, m, d) = CivilDate.toCivil(day);
    Nat.toText(y) # "-" # (if (m < 10) "0" else "") # Nat.toText(m) # "-" # (if (d < 10) "0" else "") # Nat.toText(d)
  };

  /// A title in HTML: the five characters that would make markup, escaped.
  public func escape(t : Text) : Text {
    var out = "";
    for (ch in t.chars()) {
      out #= switch (ch) { case '&' "&amp;"; case '<' "&lt;"; case '>' "&gt;"; case '\"' "&quot;"; case '\'' "&#39;"; case c Text.fromChar(c) };
    };
    out
  };

  /// A document verified to be its own plaintext, with its content type checked: what the website
  /// requires of a page, required of a post.
  func verified(c : Ctx, companyId : Nat, documentId : Nat, contentType : Text) : { #ok : (Nat, Nat, Blob); #err : Refusal } {
    switch (SFold.checkContentType(contentType)) { case (?e) return #err(#site e); case null {} };
    let (_, ev) = switch (SFold.pageDocument(c.evs, companyId, documentId)) { case (#err e) return #err(#site e); case (#ok x) x };
    let bytes = switch (SFold.readBytes(c.evs.ev, ev.blobId)) { case (#err e) return #err(#site e); case (#ok b) b };
    let fingerprint = SFold.fingerprintOf(bytes);
    if (SFold.hexOf(fingerprint) != ev.plainHash) return #err(#site(#fingerprintDisagrees { declared = ev.plainHash; computed = SFold.hexOf(fingerprint) }));
    #ok((ev.id, bytes.size(), fingerprint))
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func postBySlug(st : Stores, companyId : Nat, slug : Blob) : ?(Nat, BR.Post) {
    let k = SiteRows.pathKey(companyId, slug);
    one<BR.Post>(RowStore.page<BR.Post>(st.posts, BR.post, "by_slug_one", k, k, null, 1))
  };

  /// The live posts, NEWEST FIRST: the day index read whole and reversed, at most the index's limit.
  public func livePosts(st : Stores, companyId : Nat) : [(Nat, BR.Post)] {
    let (lo, hi) = BR.dayRange(companyId);
    let asc = all<BR.Post>(st.posts, BR.post, "by_company_day_live", lo, hi);
    let n = Nat.min(asc.size(), INDEX_LIMIT);
    Array.tabulate<(Nat, BR.Post)>(n, func(i) { asc[asc.size() - 1 - i] })
  };

  // ── the post ────────────────────────────────────────────────────────────────

  /// PUBLISH: a verified document as a post at a slug, the caller its author, today its date. A
  /// withdrawn post published again under its slug stands again as a further revision; a live one
  /// holds its slug.
  public func publish(c : Ctx, f : BF.PostFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let slug = switch (slugField(f.slug)) { case (#err e) return #err(e); case (#ok s) s };
    if (Text.size(f.title) == 0) return #err(#titleRequired);
    if (Text.size(f.title) > TA.maxLength()) return #err(#textDoesNotFit { field = "title"; value = f.title; max = TA.maxLength() });
    let existing = postBySlug(c.blog, f.companyId, slug);
    switch (existing) { case (?(postId, p)) { if (p.isLive) return #err(#slugTaken { slug = f.slug; postId }) }; case null {} };
    let (evidenceId, byteSize, fingerprint) = switch (verified(c, f.companyId, f.documentId, f.contentType)) { case (#err e) return #err(e); case (#ok x) x };
    // nothing left that can refuse
    let title = switch (put(c.arena, "title", f.title)) { case (#ok r) r; case (#err e) return #err(e) };
    let contentType = switch (put(c.arena, "content type", f.contentType)) { case (#ok r) r; case (#err e) return #err(e) };
    switch (existing) {
      case (?(postId, p)) {
        RowStore.put<BR.Post>(c.blog.posts, BR.post, postId, { p with title; revisedDay = c.day; revision = p.revision + 1; documentId = f.documentId; evidenceId; contentType; byteSize; fingerprint; isLive = true; lastBlock = c.block });
        #ok([postId])
      };
      case null {
        let id = c.blog.nextPostId;
        RowStore.put<BR.Post>(c.blog.posts, BR.post, id, {
          companyId = f.companyId; slug; title; author = c.caller; publishedDay = c.day; publishedBlock = c.block; revisedDay = c.day; revision = 1;
          documentId = f.documentId; evidenceId; contentType; byteSize; fingerprint; isLive = true; lastBlock = c.block });
        c.blog.nextPostId += 1;
        #ok([id])
      };
    }
  };

  /// REVISE: another verified document under the same slug; the day of first publication kept, the
  /// day of revision written, the revision counted.
  public func revise(c : Ctx, f : BF.RevisionFacts) : Outcome {
    let ?p = RowStore.get<BR.Post>(c.blog.posts, BR.post, f.postId) else return #err(#noSuchPost { postId = f.postId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (not p.isLive) return #err(#postWithdrawn { postId = f.postId });
    let (evidenceId, byteSize, fingerprint) = switch (verified(c, f.companyId, f.documentId, f.contentType)) { case (#err e) return #err(e); case (#ok x) x };
    let contentType = switch (put(c.arena, "content type", f.contentType)) { case (#ok r) r; case (#err e) return #err(e) };
    RowStore.put<BR.Post>(c.blog.posts, BR.post, f.postId, { p with revisedDay = c.day; revision = p.revision + 1; documentId = f.documentId; evidenceId; contentType; byteSize; fingerprint; lastBlock = c.block });
    #ok([f.postId])
  };

  /// WITHDRAW: listed and served no more; the row stays, the slug stays its own.
  public func withdraw(c : Ctx, companyId : Nat, postId : Nat) : Outcome {
    let ?p = RowStore.get<BR.Post>(c.blog.posts, BR.post, postId) else return #err(#noSuchPost { postId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (not p.isLive) return #err(#postWithdrawn { postId });
    RowStore.put<BR.Post>(c.blog.posts, BR.post, postId, { p with isLive = false; lastBlock = c.block });
    #ok([postId])
  };

  // ── the read surface ────────────────────────────────────────────────────────

  /// Under a site's path: the blog's index, or one post by its slug, or neither.
  public func routeBlog(path : Text) : ?{ #index; #post : Text } {
    if (path == "/blog" or path == "/blog/") return ?#index;
    if (not Text.startsWith(path, #text "/blog/")) return null;
    let slug = Text.trimStart(path, #text "/blog/");
    if (slug == "" or Text.contains(slug, #char '/')) return null;
    ?#post(slug)
  };

  /// THE INDEX: the live posts newest first, each its escaped title, its date and its link.
  public func index(st : Stores, arena : TA.Arena, companyId : Nat, companySlug : Text) : Text {
    var body = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Blog</title></head><body><h1>Blog</h1><ul>";
    for ((_, p) in livePosts(st, companyId).vals()) {
      let title = switch (TA.get(arena, p.title)) { case (?t) t; case null "" };
      let slug = switch (F.textOfField(p.slug)) { case (?s) s; case null "" };
      body #= "<li><a href=\"/sites/" # escape(companySlug) # "/blog/" # slug # "\">" # escape(title) # "</a> <time datetime=\"" # isoDate(p.publishedDay) # "\">" # isoDate(p.publishedDay) # "</time></li>";
    };
    body # "</ul></body></html>"
  };

  /// THE POST AS SERVED: live, its document still a page's, the bytes read and hashed again.
  public func serve(st : Stores, evs : EF.Stores, arena : TA.Arena, companyId : Nat, slug : Text) : ?SFold.Served {
    let field = switch (slugField(slug)) { case (#err _) return null; case (#ok s) s };
    let ?(_, p) = postBySlug(st, companyId, field) else return null;
    if (not p.isLive) return null;
    let (_, ev) = switch (SFold.pageDocument(evs, companyId, p.documentId)) { case (#err _) return null; case (#ok x) x };
    let bytes = switch (SFold.readBytes(evs.ev, ev.blobId)) { case (#err _) return null; case (#ok b) b };
    if (SFold.fingerprintOf(bytes) != p.fingerprint) return null;
    let ?contentType = TA.get(arena, p.contentType) else return null;
    ?{ body = bytes; contentType; block = p.publishedBlock; version = p.revision; fingerprint = p.fingerprint }
  };

}
