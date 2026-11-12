/// ClockWiring.mo - the one place in this product that has a time source.
///
/// THE RULE ON TIME: every product runs on the calendar enforced by the
/// application - the calendar authority - and that is the only time source until the real block
/// timestamp is validated on the chain. The timestamp path is built in the kernel behind one
/// function; nothing here selects it.
///
/// WHY THIS FILE EXISTS AT ALL. The received tree calls `Time.now()` 432 times (`main.mo` 430,
/// `crm.mo` 2) and, in a dozen public methods, takes the time from the CALLER - `nowNs : Int` on
/// `postMove`'s neighbours in `erp.mo`, on `sendMailingBatch` in `crm.mo`, and a caller-supplied
/// `date : Text` and `time : Text` on `clockIn` in `main.mo` beside a `punchAt = Time.now()` that
/// nothing compares them to. Both are the same defect: the contract does not know what day it is.
/// On Thebes `Time.now()` is the block height in seconds, and the banking tree's clock day computed
/// to **0** and refused a 2026 business date at the first dated act (`thebes-banking-core`
/// `f7e28bb`). This product does not get to repeat it: no file outside this one reads a clock, and
/// `tools/no_direct_clock.sh` fails the build if one does.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";
import Nat64 "mo:core/Nat64";
import Result "mo:core/Result";

import Clock "mo:kernel/time/Clock";

module {

  public type Day = Clock.Day;
  public type Config = Clock.Config;
  public type Source = Clock.Source;
  public type Reading = Clock.Reading;
  public type Deadline = Clock.Deadline;
  public type Error = Clock.Error;

  /// A contract's configuration at genesis: the calendar authority, no date yet, and a roll bound.
  /// A company's first `rollBusinessDate` sets the date; until then every dated act is refused with
  /// `#NoBusinessDate`, which is the right answer and not zero.
  public func genesisConfig(maxRollDays : Nat) : Config {
    { authority = #businessDate; businessDate = null; maxRollDays; calendar = null }
  };

  /// The authority this product selects. Stated as a function so the battery can assert it, rather
  /// than as a comment someone has to believe.
  public func selectedAuthority() : Clock.Authority { #businessDate };

  /// Is the configuration one this product is allowed to run on? The kernel says which authorities
  /// are selectable at all; this adds the product's own narrowing to the one the rule on time names.
  public func permitted(c : Config) : ?Text {
    if (not Clock.isSelectable(c.authority)) {
      return ?("authority " # Clock.authorityName(c.authority) # " is not selectable in this kernel");
    };
    if (not Clock.sameAuthority(c.authority, selectedAuthority())) {
      return ?("this product runs on " # Clock.authorityName(selectedAuthority())
               # " only; " # Clock.authorityName(c.authority) # " is built but not selected");
    };
    switch (Clock.validate(c)) { case (?e) ?Clock.errorText(e); case null null }
  };

  /// The business date, or the typed reason there is none.
  public func today(c : Config, s : Source) : Result.Result<Day, Error> { Clock.today(c, s) };

  /// Day, height and - where the substrate carries one - wall time, taken as ONE reading, so a
  /// decision cannot straddle a block boundary.
  public func read(c : Config, s : Source) : Result.Result<Reading, Error> { Clock.read(c, s) };

  /// The height a block is stamped with. The log's `timestamp` field carries this and never a
  /// wall-clock instant.
  public func stamp(r : Reading) : Nat64 { Nat64.fromNat(r.height) };

  public func roll(c : Config, to : Day) : Result.Result<Config, Error> { Clock.roll(c, to) };

  public func errorText(e : Error) : Text { Clock.errorText(e) };

}
