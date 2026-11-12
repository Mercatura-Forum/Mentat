/// KbFold.mo - knowledge: articles as versioned documents in the evidence store.
///
/// AN ARTICLE IS ITS VERSIONS. Each version is a DOCUMENT IN THE EVIDENCE STORE - uploaded and registered by its
/// author under the company's ring (a company document, so every member who holds the company's ring can open
/// it, and nobody the ring does not reach), still active, and the words of no other version of any article - with
/// a title, a category and at most four tags, each normalised, at most sixteen bytes and named once. The first
/// version opens the article as a DRAFT; any member may write the next, and an article that is archived takes no
/// more.
///
/// WHAT READERS READ IS THE PUBLISHED VERSION, and A VERSION IS PUBLISHED BY SOMEBODY WHO DID NOT WRITE IT - any
/// version of the article, the latest or an earlier one brought back, while its document is still active. The
/// article then carries that version's category and tags, so what a reader looks through by category is what was
/// published and never a draft written since. An article is ARCHIVED by a member and stands for no reader; it
/// comes back only by being published again, by a second person.
///
/// A VIEW is a member's reading of a published article, recorded once, with the version they read. A VOTE is a
/// member's word on whether a published article helped, never the published version's author's own, one per
/// member and moved when they change their mind; the article counts the views and both sides of the votes.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import CR "CrmRows";
import E "Enums";
import F "Fields";
import KF "KbFacts";
import KR "KbRows";
import Lookup "Lookup";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #nameRequired : { what : Text };
    #textTooLong : { max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
    #tooManyTags : { max : Nat };
    #tagRequired;
    #tagDoesNotFit : { tag : Text; max : Nat };
    #tagTwice : { tag : Text };
    #noSuchDocument : { documentId : Nat };
    #documentNotShared : { documentId : Nat };
    #documentNotActive : { documentId : Nat };
    #notTheUploader : { documentId : Nat; subject : Principal };
    #documentAlreadyAVersion : { documentId : Nat; articleId : Nat };
    #noSuchArticle : { articleId : Nat };
    #articleArchived : { articleId : Nat };
    #noSuchVersion : { articleId : Nat; number : Nat };
    #authorPublishes : { articleId : Nat; number : Nat; subject : Principal };
    #alreadyPublished : { articleId : Nat; number : Nat };
    #alreadyArchived : { articleId : Nat };
    #notPublished : { articleId : Nat };
    #alreadyViewed : { articleId : Nat; subject : Principal };
    #authorVotes : { articleId : Nat; subject : Principal };
    #alreadyVoted : { articleId : Nat; isHelpful : Bool };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(expected) # " expected, " # Nat.toText(found) # " found";
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#nameRequired { what }) what # " is required";
      case (#textTooLong { max }) "a text past " # Nat.toText(max) # " characters";
      case (#textDoesNotFit { field; max }) "the " # field # " does not fit the arena's " # Nat.toText(max);
      case (#tooManyTags { max }) "an article carries at most " # Nat.toText(max) # " tags";
      case (#tagRequired) "a tag is a word, not nothing";
      case (#tagDoesNotFit { tag; max }) "the tag " # tag # " does not fit in " # Nat.toText(max) # " bytes";
      case (#tagTwice { tag }) "the tag " # tag # " is named twice";
      case (#noSuchDocument { documentId }) "no document " # Nat.toText(documentId);
      case (#documentNotShared { documentId }) "document " # Nat.toText(documentId) # " is not a company document under the company's ring";
      case (#documentNotActive { documentId }) "document " # Nat.toText(documentId) # " is archived or erased";
      case (#notTheUploader { documentId; subject }) Principal.toText(subject) # " did not upload document " # Nat.toText(documentId);
      case (#documentAlreadyAVersion { documentId; articleId }) "document " # Nat.toText(documentId) # " is already a version of article " # Nat.toText(articleId);
      case (#noSuchArticle { articleId }) "no article " # Nat.toText(articleId);
      case (#articleArchived { articleId }) "article " # Nat.toText(articleId) # " is archived";
      case (#noSuchVersion { articleId; number }) "article " # Nat.toText(articleId) # " has no version " # Nat.toText(number);
      case (#authorPublishes { articleId; number; subject }) Principal.toText(subject) # " wrote version " # Nat.toText(number) # " of article " # Nat.toText(articleId) # " and does not publish it";
      case (#alreadyPublished { articleId; number }) "version " # Nat.toText(number) # " of article " # Nat.toText(articleId) # " is the one published";
      case (#alreadyArchived { articleId }) "article " # Nat.toText(articleId) # " is archived already";
      case (#notPublished { articleId }) "article " # Nat.toText(articleId) # " is not published";
      case (#alreadyViewed { articleId; subject }) Principal.toText(subject) # " has viewed article " # Nat.toText(articleId);
      case (#authorVotes { articleId; subject }) Principal.toText(subject) # " wrote the published version of article " # Nat.toText(articleId) # " and does not vote on it";
      case (#alreadyVoted { articleId; isHelpful }) "the vote on article " # Nat.toText(articleId) # " is " # (if (isHelpful) "helpful" else "not helpful") # " already";
    }
  };

  public type Stores = {
    var articles : RowStore.Store;
    var versions : RowStore.Store;
    var views : RowStore.Store;
    var votes : RowStore.Store;
    var nextArticleId : Nat;
    var nextVersionId : Nat;
    var nextViewId : Nat;
    var nextVoteId : Nat;
  };

  public func newStores() : Stores {
    {
      var articles = RowStore.newStore<KR.Article>(KR.article);
      var versions = RowStore.newStore<KR.Version>(KR.version);
      var views = RowStore.newStore<KR.View>(KR.view);
      var votes = RowStore.newStore<KR.Vote>(KR.vote);
      var nextArticleId = 1; var nextVersionId = 1; var nextViewId = 1; var nextVoteId = 1;
    }
  };

  /// A document of the evidence register as a version reads it.
  public type DocumentView = {
    companyId : Nat;
    kind : E.DocumentKind;
    state : E.DocumentState;
    uploadedBy : Principal;
  };

  public type Ctx = {
    kb : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    documentOf : Nat -> ?DocumentView;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_TEXT : Nat = 4_000;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    if (Text.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };
  func member(c : Ctx, companyId : Nat) : ?Refusal {
    if (not c.companyExists(companyId)) return ?#wrongCompany { expected = companyId; found = 0 };
    if (not c.isMember(companyId, c.caller)) return ?#notAMember { subject = c.caller };
    null
  };
  func maxSequence() : Nat { F.pow256(W.SEQUENCE) - 1 };

  /// THE TAGS, each normalised (case and surrounding space aside), a word, at most sixteen bytes, named once.
  public func tagFields(tags : [Text]) : { #ok : [Blob]; #err : Refusal } {
    if (tags.size() > W.KB_TAGS) return #err(#tooManyTags { max = W.KB_TAGS });
    var out : [Blob] = [];
    for (t in tags.vals()) {
      let n = CR.normalise(t);
      if (Text.size(n) == 0) return #err(#tagRequired);
      let ?field = F.textField(n, W.CODE) else return #err(#tagDoesNotFit { tag = n; max = W.CODE });
      // a tag read back must be the tag written: one that ends in NUL would read back as another
      if (F.textOfField(field) != ?n) return #err(#tagDoesNotFit { tag = n; max = W.CODE });
      for (seen in out.vals()) { if (seen == field) return #err(#tagTwice { tag = n }) };
      out := Array.concat(out, [field]);
    };
    #ok(out)
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func versionOf(st : Stores, articleId : Nat, number : Nat) : ?(Nat, KR.Version) {
    let k = KR.versionKey(articleId, number);
    Lookup.firstOf<KR.Version>(st.versions, KR.version, "by_article_one", k, k)
  };

  public func versionOfDocument(st : Stores, documentId : Nat) : ?(Nat, KR.Version) {
    let k = KR.documentKey(documentId);
    Lookup.firstOf<KR.Version>(st.versions, KR.version, "by_document_one", k, k)
  };

  /// An article's versions in order, a page from the version after `afterNumber`.
  public func versionsOf(st : Stores, articleId : Nat, afterNumber : Nat, limit : Nat) : Page.Result<(Nat, KR.Version)> {
    Lookup.upTo<KR.Version>(st.versions, KR.version, "by_article_one", KR.versionKey(articleId, afterNumber + 1), KR.versionKey(articleId, maxSequence()), limit)
  };

  /// A company's articles in one state, a page from the article after `afterId`.
  public func articlesIn(st : Stores, companyId : Nat, s : E.KbState, afterId : Nat, limit : Nat) : Page.Result<(Nat, KR.Article)> {
    let (_, hi) = KR.stateRange(companyId, s);
    Lookup.upTo<KR.Article>(st.articles, KR.article, "by_state", KR.stateKey(companyId, s, afterId + 1), hi, limit)
  };

  /// WHAT A READER LOOKS THROUGH: a company's published articles of a category, a page from the article after `afterId`.
  public func publishedIn(st : Stores, companyId : Nat, category : E.KbCategory, afterId : Nat, limit : Nat) : Page.Result<(Nat, KR.Article)> {
    let (_, hi) = KR.categoryRange(companyId, category);
    Lookup.upTo<KR.Article>(st.articles, KR.article, "by_category_published", KR.categoryKey(companyId, category, afterId + 1), hi, limit)
  };

  public func viewOf(st : Stores, articleId : Nat, p : Principal) : ?(Nat, KR.View) {
    let k = KR.personKey(articleId, p);
    Lookup.firstOf<KR.View>(st.views, KR.view, "by_key_one", k, k)
  };

  public func voteOf(st : Stores, articleId : Nat, p : Principal) : ?(Nat, KR.Vote) {
    let k = KR.personKey(articleId, p);
    Lookup.firstOf<KR.Vote>(st.votes, KR.vote, "by_key_one", k, k)
  };

  // ── the versions ────────────────────────────────────────────────────────────

  /// A version's words: a document of the company, under its ring, active, uploaded by the caller, and no other
  /// version's.
  func checkDocument(c : Ctx, companyId : Nat, documentId : Nat) : ?Refusal {
    let ?d = c.documentOf(documentId) else return ?#noSuchDocument { documentId };
    if (d.companyId != companyId) return ?#wrongCompany { expected = companyId; found = d.companyId };
    if (d.kind != #company) return ?#documentNotShared { documentId };
    if (d.state != #active) return ?#documentNotActive { documentId };
    if (d.uploadedBy != c.caller) return ?#notTheUploader { documentId; subject = c.caller };
    switch (versionOfDocument(c.kb, documentId)) {
      case (?(_, v)) return ?#documentAlreadyAVersion { documentId; articleId = v.articleId };
      case null {};
    };
    null
  };

  func writeVersion(c : Ctx, articleId : Nat, number : Nat, f : KF.VersionFacts, tags : [Blob]) : { #ok : Nat; #err : Refusal } {
    let title = switch (put(c.arena, "title", f.title)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.kb.nextVersionId;
    RowStore.put<KR.Version>(c.kb.versions, KR.version, id, {
      companyId = f.companyId; articleId; number; documentId = f.documentId; title; category = f.category; tags;
      author = c.caller; day = c.day; lastBlock = c.block });
    c.kb.nextVersionId += 1;
    #ok(id)
  };

  /// AN ARTICLE OPENED BY ITS FIRST VERSION, a draft.
  public func createKbArticle(c : Ctx, f : KF.VersionFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "an article's title" });
    let tags = switch (tagFields(f.tags)) { case (#ok t) t; case (#err e) return #err(e) };
    switch (checkDocument(c, f.companyId, f.documentId)) { case (?r) return #err(r); case null {} };
    let articleId = c.kb.nextArticleId;
    let versionId = switch (writeVersion(c, articleId, 1, f, tags)) { case (#ok id) id; case (#err e) return #err(e) };
    RowStore.put<KR.Article>(c.kb.articles, KR.article, articleId, {
      companyId = f.companyId; category = f.category; tags; state = #draft; createdBy = c.caller; versions = 1;
      publishedVersion = 0; publishedDay = 0; views = 0; helpful = 0; notHelpful = 0; createdDay = c.day; lastBlock = c.block });
    c.kb.nextArticleId += 1;
    #ok([articleId, versionId])
  };

  func articleOf(c : Ctx, companyId : Nat, articleId : Nat) : { #ok : KR.Article; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?a = RowStore.get<KR.Article>(c.kb.articles, KR.article, articleId) else return #err(#noSuchArticle { articleId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    #ok(a)
  };

  /// THE NEXT VERSION, by any member, of an article not archived. A draft takes the new category and tags at
  /// once; a published article keeps its published version's until a second person publishes the new one.
  public func reviseKbArticle(c : Ctx, articleId : Nat, f : KF.VersionFacts) : Outcome {
    let a = switch (articleOf(c, f.companyId, articleId)) { case (#err e) return #err(e); case (#ok x) x };
    if (a.state == #archived) return #err(#articleArchived { articleId });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "an article's title" });
    let tags = switch (tagFields(f.tags)) { case (#ok t) t; case (#err e) return #err(e) };
    switch (checkDocument(c, f.companyId, f.documentId)) { case (?r) return #err(r); case null {} };
    let number = a.versions + 1;
    let versionId = switch (writeVersion(c, articleId, number, f, tags)) { case (#ok id) id; case (#err e) return #err(e) };
    let (category, shown) = if (a.state == #draft) (f.category, tags) else (a.category, a.tags);
    RowStore.put<KR.Article>(c.kb.articles, KR.article, articleId, { a with versions = number; category; tags = shown; lastBlock = c.block });
    #ok([versionId])
  };

  // ── publishing and archiving ────────────────────────────────────────────────

  /// PUBLISHED BY SOMEBODY WHO DID NOT WRITE THE VERSION, its document still active: the latest version, or an
  /// earlier one brought back; an archived article comes back this way and no other.
  public func publishKbVersion(c : Ctx, companyId : Nat, articleId : Nat, number : Nat) : Outcome {
    let a = switch (articleOf(c, companyId, articleId)) { case (#err e) return #err(e); case (#ok x) x };
    let ?(_, v) = versionOf(c.kb, articleId, number) else return #err(#noSuchVersion { articleId; number });
    if (a.state == #published and a.publishedVersion == number) return #err(#alreadyPublished { articleId; number });
    if (v.author == c.caller) return #err(#authorPublishes { articleId; number; subject = c.caller });
    let ?d = c.documentOf(v.documentId) else return #err(#noSuchDocument { documentId = v.documentId });
    if (d.state != #active) return #err(#documentNotActive { documentId = v.documentId });
    RowStore.put<KR.Article>(c.kb.articles, KR.article, articleId, {
      a with state = #published; publishedVersion = number; publishedDay = c.day; category = v.category; tags = v.tags; lastBlock = c.block });
    #ok([articleId])
  };

  /// ARCHIVED BY A MEMBER: it stands for no reader, keeps every version, and takes no more.
  public func archiveKbArticle(c : Ctx, companyId : Nat, articleId : Nat) : Outcome {
    let a = switch (articleOf(c, companyId, articleId)) { case (#err e) return #err(e); case (#ok x) x };
    if (a.state == #archived) return #err(#alreadyArchived { articleId });
    RowStore.put<KR.Article>(c.kb.articles, KR.article, articleId, { a with state = #archived; lastBlock = c.block });
    #ok([articleId])
  };

  // ── readers ─────────────────────────────────────────────────────────────────

  func published(c : Ctx, companyId : Nat, articleId : Nat) : { #ok : KR.Article; #err : Refusal } {
    let a = switch (articleOf(c, companyId, articleId)) { case (#err e) return #err(e); case (#ok x) x };
    if (a.state != #published) return #err(#notPublished { articleId });
    #ok(a)
  };

  /// A VIEW, ONCE PER MEMBER, of a published article, with the version read.
  public func recordKbView(c : Ctx, companyId : Nat, articleId : Nat) : Outcome {
    let a = switch (published(c, companyId, articleId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (viewOf(c.kb, articleId, c.caller)) { case (?_) return #err(#alreadyViewed { articleId; subject = c.caller }); case null {} };
    let id = c.kb.nextViewId;
    RowStore.put<KR.View>(c.kb.views, KR.view, id, {
      companyId; articleId; viewer = c.caller; version = a.publishedVersion; day = c.day; lastBlock = c.block });
    c.kb.nextViewId += 1;
    RowStore.put<KR.Article>(c.kb.articles, KR.article, articleId, { a with views = a.views + 1; lastBlock = c.block });
    #ok([id])
  };

  /// A VOTE, one per member, never the published version's author's, moved when the member changes their mind.
  public func voteKbArticle(c : Ctx, companyId : Nat, articleId : Nat, isHelpful : Bool) : Outcome {
    let a = switch (published(c, companyId, articleId)) { case (#err e) return #err(e); case (#ok x) x };
    let ?(_, v) = versionOf(c.kb, articleId, a.publishedVersion) else return #err(#noSuchVersion { articleId; number = a.publishedVersion });
    if (v.author == c.caller) return #err(#authorVotes { articleId; subject = c.caller });
    switch (voteOf(c.kb, articleId, c.caller)) {
      case (?(id, x)) {
        if (x.isHelpful == isHelpful) return #err(#alreadyVoted { articleId; isHelpful });
        RowStore.put<KR.Vote>(c.kb.votes, KR.vote, id, { x with isHelpful; lastBlock = c.block });
        let (helpful, notHelpful) = if (isHelpful) (a.helpful + 1, a.notHelpful - 1) else (a.helpful - 1, a.notHelpful + 1);
        RowStore.put<KR.Article>(c.kb.articles, KR.article, articleId, { a with helpful; notHelpful; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.kb.nextVoteId;
        RowStore.put<KR.Vote>(c.kb.votes, KR.vote, id, { companyId; articleId; voter = c.caller; isHelpful; lastBlock = c.block });
        c.kb.nextVoteId += 1;
        let (helpful, notHelpful) = if (isHelpful) (a.helpful + 1, a.notHelpful) else (a.helpful, a.notHelpful + 1);
        RowStore.put<KR.Article>(c.kb.articles, KR.article, articleId, { a with helpful; notHelpful; lastBlock = c.block });
        #ok([id])
      };
    }
  };
}
