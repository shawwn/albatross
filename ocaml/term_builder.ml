(* Copyright (C) Helmut Brandl  <helmut dot brandl at gmx dot net>

   This file is distributed under the terms of the GNU General Public License
   version 2 (GPLv2) as published by the Free Software Foundation.
*)

open Signature
open Term
open Support
open Container
open Printf

type t = {mutable tlist: term list;
          mutable sign:  Sign.t;  (* expected *)
          mutable tvars: TVars_sub.t;
          c: Context.t}

(* The type variables of the term builder and the context differ.

   context:          locs         +           fgs
   builder:  blocs + locs + globs + garbfgs + fgs

   Transformation from the context to the builder means
   - make space for the additional locals at the bottom
   - make space for the globals and the garbage formal generics in the middle

   Note: The context never has global type variables. These appear only in the
   term builder from the global functions with formal generics.
*)

let class_table (tb:t): Class_table.t = Context.class_table tb.c

let signature (tb:t): Sign.t = Sign.substitute tb.sign tb.tvars

let count_local (tb:t): int  = TVars_sub.count_local tb.tvars

let count_global (tb:t): int = TVars_sub.count_global tb.tvars

let count (tb:t): int = TVars_sub.count tb.tvars

let count_fgs (tb:t): int = TVars_sub.count_fgs tb.tvars

let count_all (tb:t): int = TVars_sub.count_all tb.tvars

let count_terms (tb:t): int = List.length tb.tlist

let concept (i:int) (tb:t): type_term = TVars_sub.concept i tb.tvars

let tvs (tb:t): Tvars.t  = TVars_sub.tvars tb.tvars

let has_term (tb:t): bool = tb.tlist <> []

let head_term (tb:t): term = assert (has_term tb); List.hd tb.tlist

let satisfies (t1:type_term) (t2:type_term) (tb:t): bool =
  let ct  = class_table tb
  and tvs = tvs tb in
  Class_table.satisfies t1 tvs t2 tvs ct


let string_of_term (t:term) (tb:t): string =
  Context.string_of_term t 0 tb.c


let string_of_head_term (tb:t): string =
  assert (has_term tb);
  string_of_term (head_term tb) tb


let string_of_type (tp:type_term) (tb:t): string =
  let ct = class_table tb in
  Class_table.string_of_type tp (tvs tb) ct


let string_of_signature (s:Sign.t) (tb:t): string =
  let ct      = Context.class_table tb.c in
  Class_table.string_of_signature s (tvs tb) ct


let string_of_complete_signature (s:Sign.t) (tb:t): string =
  let ct      = Context.class_table tb.c in
  Class_table.string_of_complete_signature s (tvs tb) ct

let string_of_complete_signature_sub (s:Sign.t) (tb:t): string =
  let ct      = Context.class_table tb.c in
  Class_table.string_of_complete_signature_sub s tb.tvars ct

let signature_string (tb:t): string =
  let s       = signature tb in
  string_of_signature s tb

let complete_signature_string (tb:t): string =
  let s = signature tb in
  string_of_complete_signature s tb

let substitution_string (tb:t): string =
  let sub_lst  = Array.to_list (TVars_sub.args tb.tvars)
  and ntvs     = count tb
  and fnames   = Context.fgnames tb.c
  and ct       = Context.class_table tb.c
  in
  "[" ^
  (String.concat
     ","
     (List.mapi
        (fun i tp ->
          (string_of_int i) ^ "~>" ^
          Class_table.type2string tp ntvs fnames ct)
        sub_lst)) ^
  "]"

let concepts_string (tb:t): string =
  let ct      = Context.class_table tb.c in
  Class_table.string_of_concepts (TVars_sub.tvars tb.tvars) ct


let string_of_tvs (tvs:Tvars.t) (tb:t): string =
  let ct  = Context.class_table tb.c in
  Class_table.string_of_tvs tvs ct


let string_of_tvs_sub (tb:t): string =
  let ct  = Context.class_table tb.c in
  Class_table.string_of_tvs_sub tb.tvars ct



let context_signature (tb:t): Sign.t =
  (* The signature of the context transformed into the environment of the term
     builder [tb].

     context:           loc          +         fgs

     builder:    bloc + loc  + glob  +  garb + fgs

   *)
  let s = Context.signature tb.c
  and tvs = TVars_sub.tvars (Context.type_variables tb.c) in
  let nlocs  = count_local tb
  and nglobs = count_global tb
  and ngarb  = count_fgs tb - Tvars.count_fgs tvs
  in
  assert (ngarb = 0); (* remove the first time not valid *)
  let nlocs_delta = nlocs - Tvars.count_local tvs in
  assert (0 <= nlocs_delta);
  assert (Tvars.count_global tvs = 0);
  assert (Tvars.count_fgs tvs = count_fgs tb);
  let s = Sign.up nlocs_delta s in
  Sign.up_from (nglobs+ngarb) nlocs s


let upgrade_signature (s:Sign.t) (is_pred:bool) (tb:t): Sign.t =
  (* The signature [s] upgraded to a predicate or a function. *)
  let ntvs = count_all tb  in
  let tp = Class_table.upgrade_signature ntvs is_pred s in
  Sign.make_const tp



let add_local (ntvs:int) (tb:t): unit =
  tb.tvars <- TVars_sub.add_local ntvs tb.tvars;
  tb.sign  <- Sign.up ntvs tb.sign

let remove_local (ntvs:int) (tb:t): unit =
  (* signature is irrelevant *)
  tb.tvars <- TVars_sub.remove_local ntvs tb.tvars


let add_fgs (nfgs:int) (tb:t): unit =
  (* Add [nfgs] additional formal generics from the context.

     context:    loc          +         fgs1 + fgs2

     builder:    loc  + glob  +  garb +        fgs2

   *)
  let nlocs     = count_local tb in
  let tvars_sub = Context.type_variables tb.c in
  assert (nlocs = TVars_sub.count_local tvars_sub);
  assert (nfgs <= TVars_sub.count_fgs tvars_sub);
  let nfgs2 = TVars_sub.count_fgs tvars_sub - nfgs in
  assert (nfgs2 <= count_fgs tb);
  let ngarb = count_fgs tb - nfgs2 in
  let start = count tb + ngarb
  in
  tb.sign  <- Sign.up_from nfgs start tb.sign;
  tb.tvars <- TVars_sub.add_fgs nfgs tvars_sub tb.tvars





let has_sub (i:int) (tb:t): bool = TVars_sub.has i tb.tvars

let get_sub (i:int) (tb:t): type_term = TVars_sub.get i tb.tvars


let do_sub_var (i:int) (j:int) (tb:t): unit =
  (** Substitute the variable [i] by the variable [j] or vice versa, neither
      has substitutions *)
  assert (not (has_sub i tb));
  assert (not (has_sub j tb));
  if i=j then
    ()
  else
    let add_sub (i:int) (j:int): unit =
      TVars_sub.add_sub i (Variable j) tb.tvars
    in
    let cnt_loc = count_local tb in
    let lo,hi = if i < j then i,j else j,i in
    if hi < cnt_loc || lo < cnt_loc then
      add_sub lo hi
    else begin
      assert (cnt_loc <= i);
      assert (cnt_loc <= j);
      let cpt_i, cpt_j = concept i tb, concept j tb in
      if satisfies cpt_j cpt_i tb then
        add_sub i j
      else if satisfies cpt_i cpt_j tb then
        add_sub j i
      else
        raise Not_found
    end


let is_anchor (i:int) (tb:t): bool =
  assert (i < count tb);
  TVars_sub.anchor i tb.tvars = i


let upgrade_dummy (i:int) (t:term) (tb:t): unit =
  (* Upgrade a potential dummy in the type variable [i] to a predicate or a
  function, if possible. *)
  assert (i < count tb);
  assert (is_anchor i tb);
  assert (has_sub i tb);
  let nall = count_all tb in
  let t_i = get_sub i tb
  and t   = TVars_sub.sub_star t tb.tvars
  in
  let update_with t =
    if i < count_local tb || satisfies t (concept i tb) tb then
      TVars_sub.update_sub i t tb.tvars
    else
      raise Not_found
  in
  match t_i, t with
    Application(Variable idx1, args1,_),
    Application(Variable idx2, args2,_)
    when idx1 = nall + Class_table.dummy_index ->
      if idx2 = nall + Class_table.predicate_index then
        let t_new = Application(Variable idx2, [|args1.(0)|],false) in
        update_with t_new
      else if idx2 = nall + Class_table.function_index then
        let t_new = Application(Variable idx2, args1,false) in
        update_with t_new
      else if idx2 = nall + Class_table.dummy_index then
        ()
      else
        assert false
  | _ ->
      ()



let add_sub (i:int) (t:term) (tb:t): unit =
  assert (not (has_sub i tb));
  TVars_sub.add_sub i t tb.tvars



let unify
    (t1:term)
    (t2:term)
    (tb:t)
    : unit =
  (** Unify the terms [t1] and [t2] using the substitution [tvars_sub] in the
      context [c] , i.e.  apply first the substitution [tvars_sub] to both
      terms and then add substitutions to [tvars_sub] so that when applied to
      both terms makes them identical.
   *)
  (*printf "    unify t1 %s\n" (string_of_type t1 tb);
  printf "          t2 %s\n" (string_of_type t2 tb);*)
  let nvars = TVars_sub.count tb.tvars
  and nall  = TVars_sub.count_all tb.tvars
  and nloc  = count_local tb
  in
  let rec uni (t1:term) (t2:term) (nb:int): unit =
    assert (nb = 0);
    let pred_idx = nall + nb + Class_table.predicate_index
    and func_idx = nall + nb + Class_table.function_index
    and dum_idx  = nall + nb + Class_table.dummy_index
    in
    let rec do_sub0 (i:int) (t:type_term) (nb:int): unit =
      (*printf "    do_sub0 i %d, t %s\n" i (string_of_type t tb);*)
      let i,t = i-nb, Term.down nb t in
      let i = TVars_sub.anchor i tb.tvars in
      if has_sub i tb then
        ((*printf "    has_sub %s\n" (string_of_type (get_sub i tb) tb);*)
         uni t (get_sub i tb) 0;
         upgrade_dummy i t tb)
      else
        match t with
          Variable j when j < nvars ->
            do_sub1 i j
        | _ ->
            if i < nloc || satisfies t (concept i tb) tb then
              add_sub i t tb
            else
              raise Not_found
    and do_sub1 (i:int) (j:int): unit =
      assert (not (has_sub i tb));
      (*printf "    do_sub1 i %d, j %d\n" i j;*)
      if not (has_sub j tb) then
        do_sub_var i j tb
      else if i < nloc then
        add_sub i (Variable j) tb
      else
        do_sub0 i (get_sub j tb) 0
    in
    let do_dummy
        (dum_args:type_term array)
        (j:int) (j_args:type_term array): unit =
      assert (Array.length dum_args = 2);
      if j = pred_idx then begin
        assert (Array.length j_args = 1);
        uni dum_args.(0) j_args.(0) nb
      end else if j = func_idx then begin
        assert (Array.length j_args = 2);
        uni dum_args.(0) j_args.(0) nb;
        uni dum_args.(1) j_args.(1) nb
      end else
        raise Not_found
    in
    match t1,t2 with
      Variable i, _ when nb<=i && i<nb+nvars ->
        do_sub0 i t2 nb
    | _, Variable j when nb<=j && j<nb+nvars ->
        do_sub0 j t1 nb
    | Variable i, Variable j ->
        assert (i<nb||nb+nvars<=i);
        assert (j<nb||nb+nvars<=j);
        if i=j then
          ()
        else
          raise Not_found
    | Application(Variable i,args1,_), Application(Variable j,args2,_)
      when (i=dum_idx || j=dum_idx) && not (i=dum_idx && j=dum_idx) ->
        if i = dum_idx then
          do_dummy args1 j args2
        else
          do_dummy args2 i args1
    | Application(f1,args1,_), Application(f2,args2,_) ->
        let nargs = Array.length args1 in
        if nargs <> (Array.length args2) then
          raise Not_found;
        uni f1 f2 nb;
        for i = 0 to nargs-1 do
          uni args1.(i) args2.(i) nb
        done
    | Lam (_,_,_,_), _
    | _ , Lam (_,_,_,_) ->
        assert false (* lambda terms not used for types *)
    | _ ->
        raise Not_found
  in
  try
    uni t1 t2 0
  with Term_capture ->
    assert false



let adapt_arity (s:Sign.t) (n:int) (tb:t): Sign.t =
  assert (n < Sign.arity s);
  let args = Sign.arguments s
  and rt   = Sign.result_type s in
  let tup = Class_table.to_tuple (count_all tb) (n-1) args in
  let args =
    Array.init n
      (fun i ->
        if i < n - 1 then args.(i)
        else tup) in
  Sign.make args rt



let align_arity (s1:Sign.t) (s2:Sign.t) (tb:t): Sign.t * Sign.t =
  (* What if one of them is a predicate, dummy or function?  *)
  let n1,n2 = Sign.arity s1, Sign.arity s2 in
  if n1 < n2 then
    s1, adapt_arity s2 n1 tb
  else if n2 < n1 then
    adapt_arity s1 n2 tb, s2
  else
    s1,s2



let unify_sign_0
    (sig_req:Sign.t)
    (sig_act:Sign.t)
    (tb:t)
    : unit =
  (*printf "  unify sign 0 req %s\n" (string_of_complete_signature_sub sig_req tb);
  printf "               act %s\n" (string_of_complete_signature_sub sig_act tb);*)
  let sig_req,sig_act = align_arity sig_req sig_act tb in
  let has_res = Sign.has_result sig_req in
  if has_res <> Sign.has_result sig_act then
    raise Not_found;
  if has_res then
    unify (Sign.result sig_req) (Sign.result sig_act) tb;
  for i=0 to (Sign.arity sig_req)-1 do
    unify (Sign.arguments sig_req).(i) (Sign.arguments sig_act).(i) tb
  done



let downgrade (tp:type_term) (nargs:int) (tb:t): Sign.t =
  let ntvs  = count tb
  and nfgs  = Context.count_formal_generics tb.c
  and sign  = Sign.make_const tp
  in
  Class_table.downgrade_signature (ntvs+nfgs) sign nargs



let to_dummy (sign:Sign.t) (tb:t): type_term =
  assert (Sign.has_result sign);
  let n = Sign.arity sign in
  assert (0 < n);
  let ntvs_all = count tb + Context.count_formal_generics tb.c in
  Class_table.to_dummy ntvs_all sign







let unify_sign
    (sig_req:Sign.t)
    (sig_act:Sign.t)
    (tb:t)
    : unit =
  (** Unify the signatures [sig_req] and [sig_act] by adding substitutions
      to [tb] *)
  (*printf "unify sign req %s\n" (string_of_complete_signature_sub sig_req tb);
  printf "           act %s\n" (string_of_complete_signature_sub sig_act tb);*)
  let n_req = Sign.arity sig_req
  and n_act = Sign.arity sig_act
  in
  if n_req > 0 && n_act = 0 then begin
    (*printf ".. sig_req has to be upgraded\n";*)
    let tp_req = to_dummy sig_req tb
    and tp_act = Sign.result sig_act in
    unify tp_req tp_act tb
  end else if n_req = 0 && n_act > 0 then begin
    (*printf ".. sig_act has to be upgraded\n";*)
    let tp_req = Sign.result sig_req
    and tp_act = to_dummy sig_act tb in
    unify tp_req tp_act tb
  end else begin
    (*printf ".. both are constant or callable\n";*)
    unify_sign_0 sig_req sig_act tb
  end





let make (c:Context.t): t =
  (* New accumulator for an expression in the context [c] *)
  assert (Context.has_result c);
  {tlist = [];
   sign  = Sign.make_const (Context.result_type c);
   tvars = (Context.type_variables c);
   c     = c}


let make_boolean (c:Context.t): t =
  let tvs = Context.type_variables c in
  let ntvs = TVars_sub.count_all tvs in
  let bool = Variable (ntvs + Class_table.boolean_index) in
  {tlist = [];
   tvars = tvs;
   sign  = Sign.make_const bool;
   c     = c}


let add_global (cs:type_term array) (tb:t): t =
  (** Add the constraints [cs] to the accumulator [tb] *)
  let n = Array.length cs
  and start = TVars_sub.count tb.tvars in
  {tb with
   sign  = Sign.up_from n start tb.sign;
   tvars = TVars_sub.add_global cs tb.tvars}


let add_leaf
    (i:int)
    (tvs:Tvars.t)
    (s:Sign.t)
    (tb:t): t =
  (* If [i] comes from a global environment, then it has no local type
     variables and space must be made for all type variables (locals and
     globals) of [tb.tvars]. ??? Formal generics ???

     If [i] comes from a local environment then it has no global type
     variables. But the locals already in coincide with the locals of
     [tb.tvars]. Space has to be made for all type variables (globals
     and locals) of [tb.tvars] which are not yet in [tvs].

     tvs global:                       glob

     tvs local:         loc      +                        fgs

     builder:    bloc + loc  + glob0           +   garb + fgs

     builder:    bloc + loc  + glob0 + glob    +   garb + fgs
     after add_global
   *)
  assert (not (Tvars.count_local tvs > 0 && Tvars.count_global tvs > 0));
  let tb = add_global (Tvars.concepts tvs) tb (* empty, if [tvs] doesn't come from
                                                 global *)
  in
  let nloctb  = TVars_sub.count_local  tb.tvars
  and nglobtb = TVars_sub.count_global tb.tvars
  and nfgstb  = TVars_sub.count_fgs    tb.tvars
  and nloc    = Tvars.count_local  tvs
  and nglob   = Tvars.count_global tvs
  and nfgs    = Tvars.count_fgs    tvs
  in
  assert (nloc=0 || nglob=0);
  assert (nloc <= nloctb);
  assert (nfgs <= nfgstb);
  (*assert (nfgs=0 ||  nfgs=nfgstb);*)
  assert (nglob <= nglobtb);
  let s = Sign.up_from (nfgstb-nfgs) (nloc+nglob) s in
  let s = Sign.up_from (nglobtb-nglob) nloc s       in
  let s = Sign.up (nloctb-nloc) s in
  unify_sign tb.sign s tb;
  {tb with tlist = (Variable i)::tb.tlist}




let expect_function (nargs:int) (tb:t): unit =
  (** Convert the currently expected signature to a function signature
      with [nargs] arguments and add to the type variables [nargs] fresh
      type variables, one for each argument.
   *)
  add_local nargs tb;
  let s = tb.sign in
  let s =
    if Sign.is_constant s then
      s
    else
      Sign.make_const (to_dummy s tb)
  in
  tb.sign  <- Sign.to_function nargs s



let expect_argument (i:int) (tb:t): unit =
  (** Expect the [i]th argument of a function call [f(a,b,c,...)].  *)
  assert (i < (TVars_sub.count_local tb.tvars));
  tb.sign <- Sign.make_const (TVars_sub.get i tb.tvars)





let complete_function (nargs:int) (tb:t): unit =
  (** Complete the function call [f(a,b,c,...)] with [nargs] arguments. The
      function term and all arguments are on the top of the term list
      [tb.tlist] in reverse order, ie. [tb.tlist = [...,c,b,a,f]. The terms
      are popped of the list, the corresponding function application is
      generated and pushed onto the list and the [nargs] most recent type
      variables are removed.

      Note: The expected signature is no longer valid. This is no problem,
      because either we are ready, or the next action is a further call to
      [complete_function] or a call to [expect_argument]. *)
  let arglst = ref [] in
  for i = 1 to nargs do  (* pop arguments *)
    assert (tb.tlist <> []);
    let t = List.hd tb.tlist in
    tb.tlist <- List.tl tb.tlist;
    arglst := t :: !arglst;
  done;
  let f = List.hd tb.tlist in
  tb.tlist <- List.tl tb.tlist;
  tb.tlist <- (Application (f, Array.of_list !arglst,false)) :: tb.tlist;
  remove_local nargs tb





let expect_lambda
    (ntvs:int) (nfgs:int) (is_quant: bool) (is_pred:bool) (tb:t): unit =
  (* Expect the term of a lambda expression. It is assumed that all local
      variables of the lambda expression have been pushed to the context and
      the argument list of the lambda expression contained [ntvs] untyped
      variables and [nfgs] formal generics. *)

  assert (Sign.has_result tb.sign);
  add_local ntvs tb;
  add_fgs   nfgs tb;
  assert (TVars_sub.count_local tb.tvars =
          TVars_sub.count_local (Context.type_variables tb.c));
  let csig = context_signature tb in
  if not is_quant then begin
    let upsig = upgrade_signature csig is_pred tb in
    assert (Sign.has_result csig);
    try
      unify_sign tb.sign upsig tb
    with Not_found ->
      raise Not_found
  end;
  tb.sign <- Sign.make_const (Sign.result csig)





let complete_lambda (ntvs:int) (names:int array) (is_pred:bool) (tb:t): unit =
  assert (tb.tlist <> []);
  let nargs = Array.length names in
  assert (0 < nargs);
  remove_local ntvs tb;
  let t = List.hd tb.tlist in
  tb.tlist <- List.tl tb.tlist;
  tb.tlist <- Lam (nargs, names, t,is_pred) :: tb.tlist



let argument_type (i:int) (tb:t): type_term =
  (* The type of the argument [i] transformed into the term builder

     tvs context:         loc      +              fgs
     builder:      bloc + loc  + glob  +   garb + fgs
  *)
  assert (i < Context.count_arguments tb.c);
  let ntvs_ctxt = Context.count_type_variables tb.c
  and ntvs_loc  = count_local tb
  and nfgs_ctxt = Context.count_formal_generics tb.c
  and nfgs      = count_fgs tb
  and nglobs    = count_global tb
  in
  assert (ntvs_ctxt <= ntvs_loc);
  assert (nfgs_ctxt <= nfgs);
  let tp = Context.argument_type i tb.c in
  let tp = Term.upbound (nfgs-nfgs_ctxt+nglobs) ntvs_loc tp in
  Term.up (ntvs_loc-ntvs_ctxt) tp



let update_called_variables (tb:t): unit =
  (* Arguments of the context might be called. E.g. if [a] is an argument there might
     be a subexpression [a(x)]. This requires that [a] has either a function or a
     predicate type.

     If the argument has predicate type then the predicate flag will be set in the
     application.

     Only arguments of the inner context will be updated and it is assumed that the
     arguments of the inner context have a complete type (no dummy). Variables of
     outer context might still have dummy types.
  *)
  assert (has_term tb);
  let nargs     = Context.count_last_arguments tb.c
  and ntvs_loc  = count_local tb in
  assert (ntvs_loc = Context.count_type_variables tb.c);
  let ntvs_all  = count tb + Context.count_formal_generics tb.c
  in
  let dum_idx = ntvs_all + Class_table.dummy_index
  and f_idx   = ntvs_all + Class_table.function_index
  and p_idx   = ntvs_all + Class_table.predicate_index in
  let is_pred i =
    assert (i < nargs);
    let tp = argument_type i tb in
    let tp = TVars_sub.sub_star tp tb.tvars in
    match tp with
      Application(Variable idx,_,_) ->
        assert (idx <> dum_idx);
        assert (idx = p_idx || idx = f_idx);
        idx = p_idx
    | _ ->
        false
  in
  let rec update (t:term) (nb:int): term =
    match t with
      Variable _ ->
        t
    | Application (Variable i,args,pr)
      when not pr && nb <= i && i < nb + nargs ->
        let args = Array.map (fun a -> update a nb) args in
        Application (Variable i, args, is_pred (i-nb))
    | Application (f,args,pr) ->
        let f = update f nb
        and args = Array.map (fun a -> update a nb) args in
        Application (f,args,pr)
    | Lam(n,nms,t,pr) ->
        let t = update t (n+nb) in
        Lam(n,nms,t,pr)
  in
  let t = List.hd tb.tlist in
  tb.tlist <- List.tl tb.tlist;
  tb.tlist <- (update t 0) :: tb.tlist



exception Incomplete_type of int

let check_untyped_variables (tb:t): unit =
  let ntvs_loc  = count_local tb in
  assert (ntvs_loc = Context.count_type_variables tb.c);
  let ntvs_all = count tb + Context.count_formal_generics tb.c in
  let dum_idx  = ntvs_all + Class_table.dummy_index
  in
  for i = 0 to Context.count_last_arguments tb.c - 1 do
    match Context.argument_type i tb.c with
      Variable j when j < ntvs_loc -> begin
        match TVars_sub.get_star j tb.tvars with
          Application(Variable idx,_,_) when idx = dum_idx ->
            raise (Incomplete_type i)
        | _ -> ()
      end
    | _ -> ()
  done



let has_dummy (tb:t): bool =
  let n = count tb in
  let nall = count_all tb in
  let dum_idx = nall + Class_table.dummy_index in
  let rec has n =
    if n = 0 then false
    else
      let n = n - 1 in
      match TVars_sub.get n tb.tvars with
        Application(Variable idx,_,_)  when idx = dum_idx -> true
      | _ -> has n
  in
  has n



let specialize_term (tb:t): unit =
  (* Substitute all functions with the most specific ones. E.g. the term builder
     might have used [=] of ANY. But since the arguments are of type LATTICE it
     specializes [=] of ANY to [=] of LATTICE. *)
  assert (Mylist.is_singleton tb.tlist);
  let ft = Context.feature_table tb.c
  and tvs = TVars_sub.tvars tb.tvars
  in
  let rec upd (t:term) (nargs:int) (nglob:int): int*term =
    match t with
      Variable i when i < nargs ->
        nglob, t
    | Variable i ->
        let i = i - nargs in
        let nfgs = Feature_table.count_fgs i ft in
        begin
          try
            let anchor = Feature_table.anchor i ft in
            assert (anchor < nfgs);
            let tv  = Tvars.count_local tvs + nglob + anchor in
            assert (tv < Tvars.count_all tvs);
            let tvtp = TVars_sub.get_star tv tb.tvars in
            let pcls = Tvars.principal_class tvtp tvs in
            let i_var = Feature_table.variant i pcls ft in
            nglob+nfgs, Variable (nargs + i_var)
          with Not_found ->
            nglob+nfgs, t
        end
    | Application (f,args,pr) ->
        let nglob,f = upd f nargs nglob in
        let nglob,arglst = Array.fold_left
            (fun (nglob,lst) t ->
              let nglob,t = upd t nargs nglob in
              nglob, t::lst)
            (nglob,[])
            args
        in
        let args = Array.of_list (List.rev arglst) in
        nglob, Application (f,args,pr)
    | Lam (n,nms,t,pr) ->
        let nglob, t = upd t (nargs+n) nglob in
        nglob, Lam (n,nms,t,pr)
  in
  let nargs = Context.count_arguments tb.c
  and t     = List.hd tb.tlist in
  let nglob, t = upd t nargs 0 in
  assert (nglob = TVars_sub.count_global tb.tvars);
  tb.tlist <- [t]



let result (tb:t): term * TVars_sub.t =
  (** Return the term and the calculated substitutions for the type
      variables *)
  assert (Mylist.is_singleton tb.tlist);
  List.hd tb.tlist, tb.tvars




let upgrade_potential_dummy (i:int) (pr:bool) (tb:t): unit =
  (* Check if variable [i] is an untyped variable which has a dummy type. If
     yes, upgrade it to a function or a predicate depending on the flag [pr] *)
  let nall = count_all tb in
  let dum_idx  = nall + Class_table.dummy_index
  and p_idx    = nall + Class_table.predicate_index
  and f_idx    = nall + Class_table.function_index
  and bool_idx = nall + Class_table.boolean_index
  in
  let tp = argument_type i tb in
  match tp with
    Variable i when i < count_local tb ->
      let i  = TVars_sub.anchor i tb.tvars in
      let tp = TVars_sub.get i tb.tvars in
      begin match tp with
        Application (Variable j,args,_) when j = dum_idx ->
          assert (Array.length args = 2);
          assert (not pr || args.(1) = Variable bool_idx);
          let tp =
            if pr then Application(Variable p_idx, [|args.(0)|],false)
            else Application (Variable f_idx, args, false) in
          TVars_sub.update_sub i tp tb.tvars
      | _ ->
          ()
      end
  | _ ->
      ()


let check_term (t:term) (tb:t): t =
  let rec check t tb =
    let all_id  = Context.all_index tb.c
    and some_id = Context.some_index tb.c
    and nargs   = Context.count_last_arguments tb.c in
    let upgrade_potential_dummy f pr tb =
      match f with
        Variable i when i < nargs ->
          upgrade_potential_dummy i pr tb
      | _ ->
          ()
    in
    let lambda n nms t is_quant is_pred tb =
      let ntvs_gap = count_local tb - Context.count_type_variables tb.c
      and is_func = not is_pred in
      Context.push_untyped_with_gap nms is_func ntvs_gap tb.c;
      let ntvs    = Context.count_local_type_variables tb.c - ntvs_gap
      and nfgs    = 0 in
      expect_lambda ntvs nfgs is_quant is_pred tb;
      let tb = check t tb in
      begin try
        check_untyped_variables tb
      with Incomplete_type _ ->
        raise Not_found
      end;
      complete_lambda ntvs nms is_pred tb;
      Context.pop tb.c;
      tb
    in
    match t with
      Variable i ->
        let tvs,s = Context.variable_data i tb.c in
        begin try add_leaf i tvs s tb
        with Not_found ->
          let ct = Context.class_table tb.c in
          printf "illegal term \"%s\"\n" (string_of_term t tb);
          printf "  type     %s\n"
            (Class_table.string_of_complete_signature s tvs ct);
          printf "  expected %s\n" (complete_signature_string tb);
          assert false
        end
    | Application (Variable i, [|Lam(n,nms,t0,is_pred)|],_)
      when i = all_id || i = some_id ->
        assert is_pred;
        assert (n = Array.length nms);
        expect_function 1 tb;
        let tb = check (Variable i) tb in
        expect_argument 0 tb;
        let tb = lambda n nms t0 true is_pred tb in
        complete_function 1 tb;
        tb
    | Application (f,args,pr) ->
        let nargs = Array.length args in
        expect_function nargs tb;
        let tb = check f tb in
        let tb,_ = Array.fold_left
            (fun (tb,i) a ->
              expect_argument i tb;
              check a tb, i+1)
            (tb,0)
            args
        in
        complete_function nargs tb;
        upgrade_potential_dummy f pr tb;
        tb
    | Lam(n,nms,t,is_pred) ->
        lambda n nms t false is_pred tb
  in
  let depth = Context.depth tb.c in
  let tb = check t tb
  in
  assert (depth = Context.depth tb.c);
  tb
