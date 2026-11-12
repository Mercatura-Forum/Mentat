/// KbRows.mo - the knowledge tables: the articles a company keeps, every version of each with the document in the
/// evidence store that holds its words, and the views and votes of the members who read them.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  // ── keys ────────────────────────────────────────────────────────────────────

  /// (company, state, id): a company's articles in one state, in order.
  public func stateKey(companyId : Nat, s : E.KbState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.kbStateByte(s));
    SR.putNat(w, id, W.ID);
    SR.done(w, STATE_KEY_BYTES)
  };
  public let STATE_KEY_BYTES : Nat = 13;   // COMPANY + ENUM + ID
  public func stateRange(companyId : Nat, s : E.KbState) : (Blob, Blob) {
    (stateKey(companyId, s, 0), stateKey(companyId, s, F.pow256(W.ID) - 1))
  };

  /// (company, category, id): a company's PUBLISHED articles of one category, in order.
  public func categoryKey(companyId : Nat, c : E.KbCategory, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.kbCategoryByte(c));
    SR.putNat(w, id, W.ID);
    SR.done(w, STATE_KEY_BYTES)
  };
  public func categoryRange(companyId : Nat, c : E.KbCategory) : (Blob, Blob) {
    (categoryKey(companyId, c, 0), categoryKey(companyId, c, F.pow256(W.ID) - 1))
  };

  /// (article, version number): ONE ROW PER VERSION.
  public func versionKey(articleId : Nat, number : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, articleId, W.ID);
    SR.putNat(w, number, W.SEQUENCE);
    SR.done(w, VERSION_KEY_BYTES)
  };
  public let VERSION_KEY_BYTES : Nat = 10;   // ID + SEQUENCE

  /// (document): A DOCUMENT IS THE WORDS OF ONE VERSION AT MOST, of one article.
  public func documentKey(documentId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, documentId, W.ID);
    SR.done(w, W.ID)
  };

  /// (article, person): one view and one vote per person per article.
  public func personKey(articleId : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, articleId, W.ID);
    F.putPrincipal(w, p);
    SR.done(w, PERSON_KEY_BYTES)
  };
  public let PERSON_KEY_BYTES : Nat = 36;   // ID + PRINCIPAL

  // ── the tags ────────────────────────────────────────────────────────────────

  /// `W.KB_TAGS` slots of `W.CODE` bytes; a slot of zeros is no tag (a tag is never empty and never starts with NUL).
  func putTags(w : SR.Buf, tags : [Blob]) {
    var i = 0;
    while (i < W.KB_TAGS) {
      SR.putBlob(w, if (i < tags.size()) tags[i] else Blob.fromArray(Array.tabulate<Nat8>(W.CODE, func(_) { 0 })), W.CODE);
      i += 1;
    };
  };

  func getTags(r : [Nat8], at : Nat) : [Blob] {
    let tags = List.empty<Blob>();
    var o = at;
    var i = 0;
    while (i < W.KB_TAGS) {
      if (r[o] != 0) List.add(tags, SR.getBlob(r, o, W.CODE));
      o += W.CODE;
      i += 1;
    };
    List.toArray(tags)
  };

  // ── the article ─────────────────────────────────────────────────────────────

  /// An article. Its words and its title are its versions'; what it carries is where it stands - its category and
  /// tags (the latest version's), its state, how many versions it has and WHICH ONE IS PUBLISHED (0 while none is),
  /// and what its readers did: how many members viewed it, how many found it helpful and how many did not.
  public type Article = {
    companyId : Nat;
    category : E.KbCategory;
    /// at most `W.KB_TAGS`, each normalised and at most `W.CODE` bytes
    tags : [Blob];
    state : E.KbState;
    createdBy : Principal;
    versions : Nat;
    publishedVersion : Nat;
    publishedDay : Nat;
    views : Nat;
    helpful : Nat;
    notHelpful : Nat;
    createdDay : Nat;
    lastBlock : Nat;
  };

  func encodeArticle(x : Article) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.kbCategoryByte(x.category));
    putTags(w, x.tags);
    SR.putByte(w, E.kbStateByte(x.state));
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.versions, W.SEQUENCE);
    SR.putNat(w, x.publishedVersion, W.SEQUENCE);
    SR.putNat(w, x.publishedDay, W.DAY);
    SR.putNat(w, x.views, W.QTY);
    SR.putNat(w, x.helpful, W.QTY);
    SR.putNat(w, x.notHelpful, W.QTY);
    SR.putNat(w, x.createdDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.KB_ARTICLE_ROW)
  };

  func decodeArticle(r : [Nat8]) : Article {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?category = E.kbCategoryOf(r[o]) else Runtime.trap("KbRows: article with category byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let tags = getTags(r, o); o += W.CODE * W.KB_TAGS;
    let ?state = E.kbStateOf(r[o]) else Runtime.trap("KbRows: article with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let versions = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let publishedVersion = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let publishedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let views = SR.getNat(r, o, W.QTY); o += W.QTY;
    let helpful = SR.getNat(r, o, W.QTY); o += W.QTY;
    let notHelpful = SR.getNat(r, o, W.QTY); o += W.QTY;
    let createdDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; category; tags; state; createdBy; versions; publishedVersion; publishedDay;
      views; helpful; notHelpful; createdDay; lastBlock }
  };

  public let article : RowStore.Decl<Article> = {
    table = "kb_article";
    idBytes = W.ID;
    rowBytes = W.KB_ARTICLE_ROW;
    encode = encodeArticle;
    decode = decodeArticle;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Article) : ?Blob { ?PR.pairKey(x.companyId, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Article) : ?Blob { ?stateKey(x.companyId, x.state, id) } },
      // WHAT A READER LOOKS THROUGH: the published articles of a category, and only those
      { name = "by_category_published"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Article) : ?Blob { if (x.state == #published) ?categoryKey(x.companyId, x.category, id) else null } },
    ];
  };

  // ── the version ─────────────────────────────────────────────────────────────

  /// A version: its number in the article, THE DOCUMENT IN THE EVIDENCE STORE THAT HOLDS ITS WORDS, its title, its
  /// category and its tags, its author (the document's uploader), the day and the block it was written.
  public type Version = {
    companyId : Nat;
    articleId : Nat;
    number : Nat;
    documentId : Nat;
    title : TA.Ref;
    category : E.KbCategory;
    tags : [Blob];
    author : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeVersion(x : Version) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.articleId, W.ID);
    SR.putNat(w, x.number, W.SEQUENCE);
    SR.putNat(w, x.documentId, W.ID);
    TA.putRef(w, x.title);
    SR.putByte(w, E.kbCategoryByte(x.category));
    putTags(w, x.tags);
    F.putPrincipal(w, x.author);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.KB_VERSION_ROW)
  };

  func decodeVersion(r : [Nat8]) : Version {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let articleId = SR.getNat(r, o, W.ID); o += W.ID;
    let number = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let documentId = SR.getNat(r, o, W.ID); o += W.ID;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let ?category = E.kbCategoryOf(r[o]) else Runtime.trap("KbRows: version with category byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let tags = getTags(r, o); o += W.CODE * W.KB_TAGS;
    let author = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; articleId; number; documentId; title; category; tags; author; day; lastBlock }
  };

  public let version : RowStore.Decl<Version> = {
    table = "kb_version";
    idBytes = W.ID;
    rowBytes = W.KB_VERSION_ROW;
    encode = encodeVersion;
    decode = decodeVersion;
    indexes = [
      { name = "by_article_one"; keyBytes = VERSION_KEY_BYTES;
        keyOf = func(_id : Nat, x : Version) : ?Blob { ?versionKey(x.articleId, x.number) } },
      { name = "by_document_one"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : Version) : ?Blob { ?documentKey(x.documentId) } },
    ];
  };

  // ── the view and the vote ───────────────────────────────────────────────────

  /// A member's reading of an article, once: the version they first read and the day.
  public type View = {
    companyId : Nat;
    articleId : Nat;
    viewer : Principal;
    version : Nat;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeView(x : View) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.articleId, W.ID);
    F.putPrincipal(w, x.viewer);
    SR.putNat(w, x.version, W.SEQUENCE);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.KB_VIEW_ROW)
  };

  func decodeView(r : [Nat8]) : View {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let articleId = SR.getNat(r, o, W.ID); o += W.ID;
    let viewer = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let version = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; articleId; viewer; version; day; lastBlock }
  };

  public let view : RowStore.Decl<View> = {
    table = "kb_view";
    idBytes = W.ID;
    rowBytes = W.KB_VIEW_ROW;
    encode = encodeView;
    decode = decodeView;
    indexes = [
      { name = "by_key_one"; keyBytes = PERSON_KEY_BYTES;
        keyOf = func(_id : Nat, x : View) : ?Blob { ?personKey(x.articleId, x.viewer) } },
    ];
  };

  /// A member's vote on an article: helpful or not, one per member, moved when they change their mind.
  public type Vote = {
    companyId : Nat;
    articleId : Nat;
    voter : Principal;
    isHelpful : Bool;
    lastBlock : Nat;
  };

  func encodeVote(x : Vote) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.articleId, W.ID);
    F.putPrincipal(w, x.voter);
    SR.putBool(w, x.isHelpful);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.KB_VOTE_ROW)
  };

  func decodeVote(r : [Nat8]) : Vote {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let articleId = SR.getNat(r, o, W.ID); o += W.ID;
    let voter = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let isHelpful = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; articleId; voter; isHelpful; lastBlock }
  };

  public let vote : RowStore.Decl<Vote> = {
    table = "kb_vote";
    idBytes = W.ID;
    rowBytes = W.KB_VOTE_ROW;
    encode = encodeVote;
    decode = decodeVote;
    indexes = [
      { name = "by_key_one"; keyBytes = PERSON_KEY_BYTES;
        keyOf = func(_id : Nat, x : Vote) : ?Blob { ?personKey(x.articleId, x.voter) } },
    ];
  };
}
