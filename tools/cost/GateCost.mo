// GateCost.mo - the gate's cost on one act, for tools/gate_cost.sh. Not a battery: the tool compiles it with
// `CALLS` and `MEMBERS` set, and measures the instructions it takes by the wasmtime fuel it needs to finish.
//
// The state holds one company with `MEMBERS` members; each of `CALLS` rounds asks the gate, from the view
// `State.apply` builds for every act, about two acts of one of those members: one naming its company (a
// direct lookup of the member's standing) and one naming a record by id alone (the record's row read first).
//
// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";

import Cmd "../../src/Command";
import Gate "../../src/Gate";
import St "../../src/State";

let CALLS : Nat = 0; // set by tools/gate_cost.sh
let MEMBERS : Nat = 0; // set by tools/gate_cost.sh

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 65536) else if (i == 2) Nat8.fromNat((n / 256) % 256) else if (i == 3) Nat8.fromNat(n % 256) else 0
  })))
};
let FOUNDER = who(0);
let state = St.newState();
var block = 0;
func apply(caller : Principal, c : Cmd.Command) : [Nat] {
  block += 1;
  switch (St.apply(state, block, caller, 20_768, null, c)) {
    case (#ok ids) ids;
    case (#err r) Runtime.trap("the cost program's setup was refused: " # St.refusalText(r));
  }
};
let CO = apply(FOUNDER, #bootstrapCompany { facts = { name = "Cost"; slug = "cost"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } })[0];
var m = 1;
while (m <= MEMBERS) {
  ignore apply(FOUNDER, #admitMember { companyId = CO; subject = who(m); companyRole = #HR; platformRole = #None; managerId = 0 });
  m += 1;
};
let branch : Cmd.Command = #createBranch { facts = { companyId = CO; name = "B"; code = "B"; address = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0 } };
let BRANCH = apply(FOUNDER, branch)[0];
let close : Cmd.Command = #closeBranch { branchId = BRANCH; reason = "" };
let MEMBER = who(if (MEMBERS == 0) 0 else MEMBERS / 2 + 1);

var k = 0;
while (k < CALLS) {
  switch (Gate.authorise(St.gateView(state), MEMBER, branch)) { case null {}; case (?_) Runtime.trap("the member was refused") };
  switch (Gate.authorise(St.gateView(state), MEMBER, close)) { case null {}; case (?_) Runtime.trap("the member was refused") };
  k += 1;
};
