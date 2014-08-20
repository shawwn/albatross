open Term
open Container
open Support


type proof_term =
    Axiom      of term
  | Assumption of term
  | Detached   of int * int  (* modus ponens *)
  | Specialize of int * term array
  | Subproof   of int        (* nargs *)
                * int array  (* names *)
                * int        (* res *)
                * proof_term array
  | Inherit    of int * int  (* assertion, descendant class *)

type desc = {nbenv0:     int;
             term:       term;
             proof_term: proof_term}

type gdesc = {defer: bool; owner:int}

type entry = {nbenv:  int;
              names:  int array;
              imp_id: int;
              all_id: int;
              mutable count:   int;
              mutable req:     int list}

type t = {seq:  desc Seq.t;
          gseq: gdesc Seq.t;
          mutable entry: entry;
          mutable stack: entry list;
          c: Context.t}

let context (at:t): Context.t = at.c
let class_table (at:t):   Class_table.t   = Context.class_table at.c
let feature_table (at:t): Feature_table.t = Context.feature_table at.c

let depth (at:t): int =
  List.length at.stack

let is_global (at:t): bool =
  at.stack = []

let is_local (at:t): bool =
  not (is_global at)

let is_toplevel (at:t): bool =
  Mylist.is_singleton at.stack

let count (at:t): int =
  Seq.count at.seq


let count_previous (at:t): int =
  if is_global at then
    0
  else
    (List.hd at.stack).count


let count_global (pt:t): int =
  let rec count (lst: entry list): int =
    match lst with
      []     -> assert false
    | [e]    -> e.count
    | _::lst -> count lst
  in
  if pt.stack = []
  then
    Seq.count pt.seq
  else
    count pt.stack


let count_last_local (pt:t): int =
  (count pt) - (count_previous pt)

let nbenv (at:t): int = at.entry.nbenv

let nbenv_local (at:t): int =
  at.entry.nbenv - if at.stack = [] then 0 else (List.hd at.stack).nbenv

let names (at:t): int array =
  at.entry.names

let imp_id (at:t): int =
  at.entry.imp_id

let all_id (at:t): int =
  at.entry.all_id


let split_implication (t:term) (at:t): term * term =
  Term.binary_split t at.entry.imp_id

let split_all_quantified (t:term) (at:t): int * int array * term =
  Term.quantifier_split t at.entry.all_id

let implication (a:term) (b:term) (at:t): term =
  Term.binary at.entry.imp_id a b

let implication_chain (ps: term list) (tgt:term) (at:t): term =
  Term.make_implication_chain ps tgt (imp_id at)

let split_implication_chain (t:term) (at:t): term list * term =
  Term.split_implication_chain t (imp_id at)

let all_quantified (nargs:int) (names:int array) (t:term) (at:t): term =
  Term.quantified at.entry.all_id nargs names t

let all_quantified_outer (t:term) (at:t): term =
  let nargs  = nbenv_local at          in
  let all_id = at.entry.all_id - nargs in
  Term.quantified all_id nargs at.entry.names t

let rec stacked_counts (pt:t): int list =
  List.map (fun e -> e.count) pt.stack


let string_of_term (t:term) (at:t): string =
  Context.string_of_term t at.c


let make (): t =
  {seq   = Seq.empty ();
   gseq  = Seq.empty ();
   entry = {count   = 0;
            names   = [||];
            nbenv   = 0;
            req     = [];
            imp_id  = Feature_table.implication_index;
            all_id  = Feature_table.all_index};
   stack = [];
   c = Context.make ()}


let push0 (nbenv:int) (names: int array) (at:t): unit =
  assert (nbenv = Array.length names);
  at.entry.count <- Seq.count at.seq;
  at.stack       <- at.entry :: at.stack;
  at.entry       <-
    {at.entry with
     req    = [];
     nbenv  = at.entry.nbenv + nbenv;
     names  = names;
     imp_id = at.entry.imp_id + nbenv;
     all_id = at.entry.all_id + nbenv}



let push (entlst:entities list withinfo) (at:t): unit =
  let c = context at in
  assert (depth at = Context.depth c);
  Context.push entlst None c;
  let nbenv = Context.arity c
  and names = Context.local_fargnames c in
  assert (nbenv = Array.length names);
  push0 nbenv names at


let push_untyped (names:int array) (at:t): unit =
  let c = context at in
  Context.push_untyped names c;
  let nbenv = Context.arity c in
  assert (nbenv = Array.length names);
  assert (names = Context.local_fargnames c);
  push0 nbenv names at



let pop (at:t): unit =
  assert (is_local at);
  assert (depth at = Context.depth (context at));
  Context.pop (context at);
  at.entry  <- List.hd at.stack;
  at.stack  <- List.tl at.stack;
  Seq.keep at.entry.count at.seq



let term (i:int) (at:t): term * int =
  (** The [i]th proved term with the number of variables of its environment.
   *)
  assert (i < count at);
  let desc = Seq.elem i at.seq in
  desc.term, desc.nbenv0


let nbenv_term (i:int) (at:t): int =
  (** The number of variables of the environment of the  [i]th proved term.
   *)
  assert (i < count at);
  (Seq.elem i at.seq).nbenv0



let local_term (i:int) (at:t): term =
  (** The [i]th proved term in the local environment.
   *)
  assert (i < count at);
  let desc = Seq.elem i at.seq in
  let n_up = at.entry.nbenv - desc.nbenv0
  in
  Term.up n_up desc.term


let variant (i:int) (cls:int) (at:t): term =
  let ft = feature_table at in
  let t,nbenv = term i at   in
  Feature_table.variant_term t nbenv cls ft



let discharged_term (i:int) (at:t): term =
  (** The [i]th term of the current environment with all local variables and
      assumptions discharged.
   *)
  let ps = List.map (fun j -> local_term j at) at.entry.req
  and tgt = local_term i at
  in
  let t = implication_chain ps tgt at
  in
  all_quantified_outer t at


let is_assumption (i:int) (at:t): bool =
  assert (i < count at);
  let desc = Seq.elem i at.seq in
  match desc.proof_term with
    Assumption _ -> true
  | _            -> false


let add_proved_0 (t:term) (pt:proof_term) (at:t): unit =
  (** Add the term [t] and its proof term [pt] to the table.
   *)
  let raw_add () =
    Seq.push {nbenv0 = at.entry.nbenv;
              term   = t;
              proof_term = pt} at.seq
  in
  match pt with
    Assumption _ ->
      let idx = count at in
      raw_add ();
      at.entry.req <- idx :: at.entry.req
  | _ ->
      raw_add ()




let rec term_of_pt (pt:proof_term) (at:t): term =
  (** Construct a term from the proof term [pt].
   *)
  let seq = at.seq in
  let cnt = Seq.count seq in
  match pt with
    Axiom t  -> t
  | Assumption t -> t
  | Detached (a,b) ->
      assert (a < cnt && b < cnt);
      let ta = local_term a at
      and tb = local_term b at
      in
      let b1,b2 =
        try Term.binary_split tb (imp_id at)
        with Not_found ->
          Printf.printf "ta <%d:%s> tb <%d:%s>\n"
            a (string_of_term ta at)
            b (string_of_term tb at);
          assert false
      in
      if ta <> b1 then
        Printf.printf "ta <%d:%s>, b1 <%s>, tb <%d:%s>, b2 <%s>\n"
          a (string_of_term ta at)
          (string_of_term b1 at)
          b (string_of_term tb at)
          (string_of_term b2 at);
      assert (ta = b1);
      b2
  | Specialize (i,args) ->
      assert (i < cnt);
      let nargs = Array.length args
      and t = local_term i at
      in
      let n,nms,t0 =
        try Term.quantifier_split t (all_id at)
        with Not_found -> assert false
      in
      assert (nargs <= n);
      let tsub = Term.part_sub t0 n args 0
      in
      let res =
        if nargs < n then
          let imp_id0 = (imp_id at)           in
          let imp_id1 = imp_id0 + (n-nargs)   in
          let a,b = Term.binary_split tsub imp_id1 in
          Term.binary
            imp_id0
            (try Term.down (n-nargs) a
            with Term_capture -> assert false)
            (Term.quantified
               (all_id at)
               (n-nargs)
               (Array.sub nms nargs (n-nargs))
               b)
        else
          tsub
      in
      Term.reduce res
  | Subproof (nargs,names,res_idx,pt_arr) ->
      push_untyped names at;
      let pt_len = Array.length pt_arr
      and cnt    = count at
      in
      assert (res_idx < cnt + pt_len);
      Array.iteri
        (fun i pt -> add_proved_0 (term_of_pt pt at) pt at)
        pt_arr;
      let term = discharged_term res_idx at in
      pop at;
      term
  | Inherit (idx,cls) ->
      variant idx cls at


let is_proof_pair (t:term) (pt:proof_term) (at:t): bool =
  Term.equal_wo_names t (term_of_pt pt at)


let add_proved (t:term) (pt:proof_term) (at:t): unit =
  (** Add the term [t] and its proof term [pt] to the table.
   *)
  add_proved_0 t pt at


let add_proved_global
    (defer:bool) (owner:int) (t:term) (pt:proof_term) (at:t): unit =
  (** Add the term [t] and its proof term [pt] to the table.
   *)
  assert (is_global at);
  let cnt = count at in
  (*assert (is_proof_pair t pt at);*)
  add_proved t pt at;
  Seq.push {defer=defer; owner=owner} at.gseq;
  let ct = class_table at in
  if owner <> (-1) then
    Class_table.add_assertion cnt owner defer ct



let add_axiom (t:term) (at:t): unit =
  let pt = Axiom t in
  assert (is_proof_pair t pt at);
  add_proved t pt at


let add_assumption (t:term) (at:t): unit =
  let pt = Assumption t in
  assert (is_proof_pair t pt at);
  add_proved t pt at

let add_inherited (t:term) (idx:int) (cls:int) (at:t): unit =
  assert (is_global at);
  let pt = Inherit (idx,cls) in
  (*assert (is_proof_pair t pt at);*)
  add_proved t pt at


let add_mp (t:term) (i:int) (j:int) (at:t): unit =
  let pt = Detached (i,j) in
  assert (is_proof_pair t pt at);
  add_proved t pt at


let add_specialize (t:term) (i:int) (args:term array) (at:t): unit =
  let pt = Specialize (i,args) in
  assert (is_proof_pair t pt at);
  add_proved t pt at



let rec used_assertions (i:int) (at:t) (lst:int list): int list =
  (** The assertions of the local context which are needed to prove
      assertion [i] in [at] cumulated to list [lst].

      The list includes [i] if it is in the current context.
   *)
  assert (i < (count at));
  let cnt0 = count_previous at in

  let used (lst:int list): int list =
    assert (cnt0 <= i);
    let desc = Seq.elem i at.seq in
    match desc.proof_term with
      Axiom _
    | Assumption _       -> lst
    | Specialize (j,_)   -> used_assertions j at lst
    | Subproof (_,_,_,_) -> lst
    | Detached (i,j) ->
        let used_i = used_assertions i at lst in
        used_assertions j at used_i
    | Inherit (idx,cls) ->
        assert false
  in
  if i < cnt0 then lst
  else used (i::lst)




let discharged (i:int) (at:t): term * proof_term =
  (** The [i]th term of the current environment with all local variables and
      assumptions discharged together with its proof term.
   *)
  let cnt0 = count_previous at
  and axiom = List.exists
      (fun i ->
        assert (i < (count at));
        match (Seq.elem i at.seq).proof_term with
          Axiom _ -> true
        | _       -> false)
      (used_assertions i at [])
  and term  = discharged_term i at
  and nargs = nbenv_local at
  and nms   = names at
  in
  let pterm =
    if axiom then
      Axiom term
    else
      let narr =
        if cnt0 <= i then i + 1 - cnt0
        else
          match at.entry.req with
            [] -> 0
          | i_last_assumption::_ -> i_last_assumption + 1 - cnt0
      in
      assert (0 <= narr);
      let pt_arr =
        Array.init
          narr
          (fun j -> (Seq.elem (j+cnt0) at.seq).proof_term)
      in
      Subproof (nargs,nms,i,pt_arr)
  in
  term, pterm
