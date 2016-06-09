(* Copyright (C) Helmut Brandl  <helmut dot brandl at gmx dot net>

   This file is distributed under the terms of the GNU General Public License
   version 2 (GPLv2) as published by the Free Software Foundation.
*)

open Support
open Term
open Signature
open Proof
open Container
open Printf

module PC = Proof_context

type info_term  = term withinfo
type info_terms = info_term list


let term_preconditions (it:info_term) (pc:PC.t): term list =
  let c = PC.context pc in
  try
    Context.term_preconditions it.v c
  with NYI ->
    not_yet_implemented it.i ("Calculation of the preconditions of " ^
                              (PC.string_of_term it.v pc))


let verify_preconditions (it:info_term) (pc:PC.t): unit =
  if PC.is_private pc then begin
    let pres = term_preconditions it pc in
    List.iter
      (fun p ->
        try
          Prover.prove p pc
        with Proof.Proof_failed msg ->
          error_info it.i ("Cannot prove precondition \"" ^
                           (PC.string_of_term p pc) ^
                           "\"\n  of term \"" ^
                           (PC.string_of_term it.v pc) ^ "\"" ^
                           msg))
      pres
  end


let get_boolean_term (ie: info_expression) (pc:Proof_context.t): info_term =
  let c = PC.context pc in
  let t = Typer.boolean_term ie c in
  withinfo ie.i t


let get_boolean_term_verified
    (ie: info_expression) (pc:Proof_context.t): info_term =
  let it = get_boolean_term ie pc in
  verify_preconditions it pc;
  it


let get_term (ie:info_expression) (pc:PC.t): info_term =
  let c = PC.context pc in
  let t = Typer.untyped_term ie c in
  withinfo ie.i t


let get_term_verified
    (ie: info_expression) (pc:Proof_context.t): info_term =
  let it = get_term ie pc in
  verify_preconditions it pc;
  it






let push
    (entlst: entities list withinfo)
    (rlst: compound)
    (elst: compound)
    (pc:PC.t)
    :  info_terms * info_terms * PC.t =
  let pc1 = PC.push entlst None false false false pc
  in
  let nvars = PC.count_last_arguments pc1
  and nms   = PC.local_argnames pc1
  in
  let get_bool ie = get_boolean_term ie pc1
  in
  let rlst = List.map get_bool rlst
  and elst = List.map get_bool elst
  in
  let used_vars t lst = Term.used_variables_0 t nvars lst
  in
  let used = List.fold_left (fun lst it -> used_vars it.v lst) [] rlst
  in
  let used = List.fold_left (fun lst it -> used_vars it.v lst) used elst
  in
  Array.iteri
    (fun i nme ->
      if not (List.mem i used) then
        error_info entlst.i ("Variable \"" ^ (ST.string nme) ^
                             "\" is not used, neither in assumptions nor in goals")
    )
    nms;
  rlst, elst, pc1


let add_assumptions (rlst:info_terms) (pc:PC.t): unit =
  List.iter
    (fun it ->
      verify_preconditions it pc;
      ignore (PC.add_assumption it.v true pc)
    )
    rlst


let add_axiom (it:info_term) (pc:PC.t): int =
  verify_preconditions it pc;
  PC.add_axiom it.v pc


let prove_insert_report (goal:info_term) (search:bool) (pc:PC.t): int =
  try
    let t,pt = Prover.proof_term goal.v pc in
    PC.add_proved_term t pt search pc
  with Proof.Proof_failed msg ->
    error_info goal.i ("Cannot prove" ^ msg)


let prove_insert_close (goal:info_term) (pc:PC.t): int =
  let idx = prove_insert_report goal true pc in
  PC.close pc;
  idx



let store_unproved
    (is_defer:bool)
    (elst: info_terms)
    (pc:PC.t)
    : unit =
  assert (PC.is_toplevel pc);
  let idx_lst = List.map (fun it -> add_axiom it pc) elst in
  let pair_lst = List.map (fun idx -> PC.discharged_bubbled idx pc) idx_lst in
  let anchor =
    if is_defer then
      PC.owner pc
    else
      -1
  in
  let pc0 = PC.pop pc in
  PC.add_proved_list is_defer anchor pair_lst pc0



let one_goal (elst: info_terms): info_term =
  match elst with
    [] ->
      assert false (* cannot happen *)
  | [goal] ->
      goal
  | _ :: tgt2 :: _ ->
      error_info tgt2.i "Only one goal allowed here"




let prove_goal (goal: info_term) (pc:PC.t): unit =
  verify_preconditions goal pc;
  let idx = prove_insert_report goal false pc in
  let t,pt = PC.discharged_bubbled idx pc in
  let pc0 = PC.pop pc in
  ignore (PC.add_proved false (-1) t pt pc0)


let prove_goals (elst: info_terms) (pc:PC.t): unit =
  let idx_list = List.map (fun it -> prove_insert_report it false pc) elst in
  let pair_list = List.map (fun idx -> PC.discharged_bubbled idx pc) idx_list in
  let pc0 = PC.pop pc in
  PC.add_proved_list false (-1) pair_list pc0





let analyze_type_inspect
    (info:info)
    (ivar:int) (* induction variable *)
    (goal:term)
    (pc:PC.t)
    : IntSet.t * int * type_term =
  (* constructor set, induction law, induction variable, inductive type *)
  let c     = PC.context pc in
  let nvars = Context.count_variables c
  and ct    = Context.class_table c
  in
  assert (ivar < nvars);
  let tvs,s = Context.variable_data ivar c
  in
  assert (ivar < nvars);
  assert (Sign.is_constant s);
  let cons_set, cls, tp =
    let tp = Sign.result s in
    let cls,_ = Class_table.split_type_term tp
    and ntvs = Tvars.count_all tvs in
    let set =
      if cls < ntvs then IntSet.empty
      else
        let cls = cls - ntvs in
        Class_table.constructors cls ct in
    if IntSet.is_empty set then begin
      let nms = Context.argnames c in
      let str = ST.string nms.(ivar) in
      error_info info ("Type of \"" ^ str ^ "\" is not inductive")
    end;
    set, cls-ntvs, tp
  in
  let ind_idx = PC.add_induction_law tp ivar goal pc in
  cons_set,ind_idx,tp


let analyze_type_case_pattern
    (ie:info_expression)
    (cons_set:IntSet.t)
    (tp:type_term)
    (pc:PC.t)
    : int * term * PC.t =
  (* cons_idx, pat, pc1 *)
  let c     = PC.context pc
  and nvars = PC.count_variables pc in
  let pat,nms = Typer.case_variables ie.i ie.v false c in
  let n = Array.length nms in
  let pc1 = PC.push_untyped nms pc in
  let c1  = PC.context pc1
  and tp  = Term.up n tp
  in
  let pat = Typer.typed_term (withinfo ie.i pat) tp c1 in
  let invalid_pat () =
    error_info ie.i
      ("Invalid pattern \"" ^ (string_of_expression ie.v) ^ "\"") in
  let cons_idx =
    match pat with
      VAppl(i,args,_) ->
        let argslen = Array.length args in
        if argslen <> n then invalid_pat ();
        for k = 0 to n-1 do
          if args.(k) <> Variable k then invalid_pat ()
        done;
        let cons_idx = i - nvars - n in
        if not (IntSet.mem cons_idx cons_set) then invalid_pat ();
        cons_idx
    | _ ->
        invalid_pat ()
  in cons_idx, pat, pc1




let beta_reduced (t:term) (pc:PC.t): term =
  match t with
    Application(Lam(n,_,_,t0,_,tp),args,_) ->
      assert (Array.length args = 1);
      PC.beta_reduce n t0 tp args 0 pc
  | _ ->
      t

type inductive_set_data =
    {pc:      PC.t;
     goal:    term;
     goal_predicate: term; (* [element in goal_predicate] reduces to [goal] *)
     nass: int;
     element: term;
     set:     term;        (* as written in the inpect expression *)
     set_expanded: term;   (* the inductive set '{(p): r0, r1, ... }' *)
     rules:  term array;   (* the rules *)
     induction_rule: int;  (* index of the assertion of the induction rule *)
     element_in_set: int   (* assertion which proves [element in set] *)
   }




let assumptions_for_variables
    (ind_vars: int array)
    (insp_vars: int list)
    (pc:PC.t)
    : int list * int list =
  (* All assumptions of the contexts which are needed to define the variables
     [ind_vars] and all the other variables which are not in [ind_vars] but in
     the contexts. *)
  let ind_vars  = Array.copy ind_vars
  and nvars = Array.length ind_vars in
  assert (0 < nvars);
  Array.sort Pervasives.compare ind_vars;
  let rec collect
      (i:int) (nargs:int) (ass:int list) (pc:PC.t)
      : int list * int =
    let idx_lst = PC.assumption_indices pc in
    let ass = List.rev_append idx_lst ass
    in
    let c = PC.context pc in
    let loc_nargs = Context.count_last_arguments c in
    let i =
      interval_fold
        (fun i k ->
          let k = k + nargs in
          assert (i <= nvars);
          if i = nvars || k <> ind_vars.(i) then
            i
          else
            i + 1
        )
        i 0 loc_nargs
    in
    if nvars = i then
      ass, loc_nargs+nargs
    else begin
      assert (PC.is_local pc);
      collect i (loc_nargs + nargs) ass (PC.pop pc)
    end
  in
  let ass, nvars = collect 0 0 [] pc in
  let used_lst =
    List.fold_left
      (fun lst idx -> Term.used_variables_0 (PC.term idx pc) nvars lst)
      []
      ass
  in
  let used_lst =
    let insp_vars = Array.of_list insp_vars in
    Array.sort Pervasives.compare insp_vars;
    List.filter
      (fun i ->
        try ignore(Search.binsearch i insp_vars); false
        with Not_found -> true
      )
      used_lst
  in
  ass, used_lst




let induction_goal_predicate
    (vars:int array)              (* induction variables *)
    (others:int list)             (* other variables *)
    (ass_lst:int list)            (* list of assumptions *)
    (filter: term -> bool)        (* which assumptions enter *)
    (goal: term)
    (pc:PC.t)
    : int * term =
  (*
    Generate the goal predicate and the number of assumptions:

        {vars: all(others) a1 ==> a2 ==> ... ==> goal}

    where all assumptions ai pass the filter.
   *)
  let c = PC.context pc in
  let nvars = PC.count_variables pc
  and argnames = Context.argnames c
  and argtypes = Context.argtypes c
  in
  let nass, ass_rev =
    List.fold_left
      (fun (n,lst) idx ->
        let p = PC.term idx pc in
        if filter p then
          1+n, p::lst
        else
          n,lst
      )
      (0,[])
      ass_lst
  and n_ind_vars = Array.length vars
  and all_vars = Array.append (Array.of_list others) vars
  in
  let n_all_vars = Array.length all_vars
  in
  let imp_id = n_all_vars + nvars + Feature_table.implication_index
  and n_other_vars = n_all_vars - n_ind_vars
  in
  let map,_ =
    Array.fold_left
      (fun (map,i) ivar -> IntMap.add ivar i map, i+1)
      (IntMap.empty,0)
      all_vars in
  let subst t = Term.lambda_inner_map t map in
  let nms_inner = Array.init n_other_vars (fun i -> argnames.(all_vars.(i)))
  and tps_inner = Array.init n_other_vars (fun i -> argtypes.(all_vars.(i)))
  and nms_outer =
    Array.init n_ind_vars (fun i -> argnames.(all_vars.(i+n_other_vars)))
  and tps_outer =
    Array.init n_ind_vars (fun i -> argtypes.(all_vars.(i+n_other_vars)))
  in
  let chn =
    List.fold_left
      (fun chn p ->
        let p = subst p in
        Term.binary imp_id p chn
      )
      (subst goal)
      ass_rev
  in
  let t =
    Term.all_quantified n_other_vars (nms_inner,tps_inner) empty_formals chn
  in
  let tp = Context.predicate_of_type (Context.tuple_of_types tps_outer c) c in
  let t = Context.make_lambda n_ind_vars nms_outer  [] t true 0 tp c in
  nass, t





let inductive_set
    (info:info) (set:term) (c:Context.t)
    : term * type_term * term array =
  try
    let set_exp = Context.inductive_set set c in
    begin
      match set_exp with
        Indset (nme,tp,rs) ->
          let rs = Array.map (fun r -> Term.apply r [|set|]) rs in
          set_exp, tp, rs
      | _ ->
          assert false (* cannot happen *)
    end
  with Not_found ->
    error_info info ("\"" ^ (Context.string_of_term set c) ^
                     "\" does not evaluate to an inductive set")






let inductive_set_context
    (info: info)
    (elem: term)
    (set:  term)
    (user_goal: term)
    (pc:PC.t)
    : inductive_set_data =
  (* Analyzes the outer part of an inductive set proof.

        inspect
            elem in set  -- elem must be either a variable or a tuple of variables
        ...
   *)
  assert (not (PC.is_global pc));
  let c    = PC.context pc in
  let set_expanded, set_tp, rules = inductive_set info set c
  in
  let nvars = Context.count_variables c in
  let goal_pred, nass =
    let ft = Context.feature_table c in
    let vars   = Feature_table.args_of_tuple elem nvars ft in
    let vars = Array.map
        (fun arg ->
          match arg with
            Variable i when i < nvars ->
              i
          | _ ->
              error_info info ("\"" ^ (PC.string_of_term arg pc) ^
                               "\" is not a variable")
        )
        vars
    in
    let ass_lst, var_lst =
      let insp_vars = Term.used_variables elem nvars in
      let insp_vars = Term.used_variables_0 set nvars insp_vars in
      assumptions_for_variables vars insp_vars pc in
    let nass,goal_pred =
      induction_goal_predicate
        vars
        var_lst
        ass_lst
        (fun t -> not (Term.equivalent t (Application(set,[|elem|],true))))
        user_goal
        pc
    in
    goal_pred, nass
  in
  let pa = Application(set,[|elem|],true) in
  let pa_idx =
    try PC.find_goal pa pc
    with Not_found ->
      error_info info ("\"" ^ (PC.string_of_term elem pc) ^
                       "\" is not in the inductive set") in
  let ind_idx = PC.add_set_induction_law set goal_pred elem pc in
  if PC.is_tracing pc then begin
    let prefix = PC.trace_prefix pc in
    printf "\n\n";
    printf "%sProof with inductively defined set\n\n" prefix;
    printf "%sensure\n" prefix;
    printf "%s    %s\n" prefix (PC.string_long_of_term user_goal pc);
    printf "%sinspect\n" prefix;
    printf "%s    %s\n\n"
      prefix
      (PC.string_long_of_term (Application(set,[|elem|],true)) pc)
  end;
  {pc             = pc;
   goal           = user_goal;
   goal_predicate = goal_pred;
   nass           = nass;
   set            = set;
   set_expanded   = set_expanded;
   element        = elem;
   rules          = rules;
   induction_rule = ind_idx;
   element_in_set = pa_idx;
 }



let inductive_set_case
    (case_exp: info_expression)
    (data: inductive_set_data)
    : int * term =
  let c = PC.context data.pc in
  let rule = Typer.boolean_term case_exp c in
  let irule =
    try
      interval_find
        (fun i -> Term.equivalent data.rules.(i) rule)
        0
        (Array.length data.rules)
    with Not_found ->
      error_info case_exp.i "Invalid case"
  in
  irule, rule





let error_string_case (ps_rev:term list) (goal:term) (pc:PC.t): string =
  let psstr = String.concat "\n"
      (List.rev_map
         (fun ass -> (PC.string_of_term (beta_reduced ass pc) pc))
         ps_rev)
  and tgtstr = PC.string_of_term (beta_reduced goal pc) pc in
  "\n" ^ psstr ^ "\n--------------------------\n" ^ tgtstr




let add_set_induction_hypothesis
    (hypo_idx:int)
    (pc:PC.t)
    : int =
  (* The induction hypothesis has the form

         all(hypo_vars) d1 ==> ... ==>
                {ind_vars: all(other_vars) a1 ==> ... ==> user_goal}(ind_vars)

     and has been added to the context of the case at [hypo_idx].

     We have to add the following assertion to the context and return its index:

         all(hypo_vars, other_vars) a1 ==> a2 ==> ... ==> d1 ==> ... ==> goal
    *)
  let hypo = PC.term hypo_idx pc
  in
  let n1,fargs1,ps_rev1,goal_redex1 =
    PC.split_general_implication_chain hypo pc
  in
  let pc1 = PC.push_typed fargs1 empty_formals pc
  in
  match goal_redex1 with
    Application(Lam(_),_,_) ->
      let outer_goal = PC.beta_reduce_term goal_redex1 pc1
      in
      let n2,fargs2,ps_rev2,user_goal =
        PC.split_general_implication_chain outer_goal pc1
      in
      let pc2 = PC.push_typed fargs2 empty_formals  pc1
      in
      (* Now we have two contexts: all(hypo_vars)  all(other_vars *)
      let alst_rev =
        List.rev_map
          (fun a -> PC.add_assumption a false pc2)
          (List.rev ps_rev2)
      in
      let dlst_rev =
        List.rev_map
          (fun d -> PC.add_assumption (Term.up n2 d) false pc2)
          (List.rev ps_rev1)
      in
      (* Now we have a1; a2; ... ; d1; d2, ... as assumptions in the context and
         can specialize the induction hypothesis hypo_idx.*)
      let gen_goalpred_idx =
        let spec_hypo_idx =
          let args = Array.init n1 (fun i -> Variable (i + n2)) in
          PC.specialized hypo_idx args [||] 0 pc2
        in
        List.fold_left
          (fun idx d_idx ->
            PC.add_mp d_idx idx false pc2)
          spec_hypo_idx
          (List.rev dlst_rev)
      in
      let gen_goal_idx = PC.add_beta_reduced gen_goalpred_idx false pc2 in
      let chn_goal_idx =
        let args = standard_substitution n2 in
        PC.specialized gen_goal_idx args [||] 0 pc2
      in
      let goal_idx =
        List.fold_left
          (fun idx a_idx -> PC.add_mp a_idx idx false pc2)
          chn_goal_idx
          (List.rev alst_rev)
      in
      let t,pt = PC.discharged_bubbled goal_idx pc2 in
      let idx = PC.add_proved_term t pt false pc1 in
      let t,pt = PC.discharged_bubbled idx pc1 in
      PC.add_proved_term t pt true pc
  | _ ->
      hypo_idx



let string_of_case_context
    (prefix: string)
    (ass_lst_rev: int list)
    (goal: term)
    (pc:PC.t)
    : string =
  let ass_str =
    String.concat
      ("\n" ^ prefix)
      (List.rev_map
         (fun a_idx -> PC.string_long_of_term_i a_idx pc)
         ass_lst_rev)
  and goal_str =
    PC.string_long_of_term goal pc
  in
  prefix ^ ass_str ^ "\n"
  ^ prefix ^ "---------------------\n"
  ^ prefix ^ goal_str ^ "\n"



let inductive_set_case_context
    (set:  term)
    (set_expanded: term)
    (rule:term)
    (irule:int)
    (nass: int)
    (goal_pred:term)
    (pc: PC.t):
    int list * term * term * PC.t  (* assumptions, goal, inner context *)
    =
  (*
    Prepare the inner context and return the reversed list of assumptions,
    the goal and the inner context (2 levels deeper than the inspect context).

    The rule has the form

        all(rule vars) c1 ==> c2 ==> ... ==> p(e)

    The goal predicate has the form

       {ind vars: all(other vars) a1 ==> a2 ==> ... ==> user_goal}

    with [nass] assumptions before the user goal.

    The new context has the form

        all(rule vars)
            require
                c1(set)
                c1(goal_pred)    -- ind hypo 1
                c2(set)
                c2(goal_pred)    -- ind hypo 2
                ...
                e in set
            proof
                all(other vars)
                    require
                        a1
                        a2
                        ...
                    proof
                        ind hypo 1 in user terms
                        ind hypo 2 in user terms
                        ...
                        ...  -- <-- here the user proof starts to prove the
                             --     goal

    where

         ci:
             all(hypo vars) d1i ==> d2i ==> ... ==> p(ei)

         ind hypo i:
             all(hypo vars) d1i ==> ... ==> goal_pred(ei)
   *)
  let n1,fargs1,ps,goal_pred1 =
    let nvars = PC.count_variables pc in
    let imp_id = nvars + Feature_table.implication_index in
    let n,(_,tps), ps, goal_pred1 =
      Term.induction_rule imp_id irule set_expanded set goal_pred
    in
    let m,(nms,_),_,_ = Term.all_quantifier_split_1 rule in
    assert (n = m);
    n,(nms,tps), ps, goal_pred1
  in
  let pc1 = PC.push_typed fargs1 empty_formals pc in
  (* add induction hypotheses *)
  let ass_lst_rev, hlst_rev, _ =
    List.fold_left
      (fun (alst, hlst, is_hypo) p ->
        if is_hypo then
          let idx = PC.add_assumption p false pc1 in
          alst, idx::hlst, false
        else begin
          let idx = PC.add_assumption p true pc1 in
          idx::alst, hlst, true
        end
      )
      ([],[],false)
      ps
  in
  let ass_lst_rev =
    List.fold_left
      (fun alst idx ->
        let hidx = add_set_induction_hypothesis idx pc1 in
        hidx::alst
      )
      ass_lst_rev
      (List.rev hlst_rev)
  in
  PC.close pc1;
  (* Now we have context [all(rule_vars) require c1(set); c1(q); ... set(e)] *)
  let stren_goal = PC.beta_reduce_term goal_pred1 pc1 in
  let n2,fargs2,fgs2,chn = Term.all_quantifier_split_1 stren_goal in
  let pc2 = PC.push_typed fargs2 fgs2 pc1 in
  let ass_lst_rev, goal =
    interval_fold
      (fun (alst,chn) _ ->
        let a,chn =
          try
            PC.split_implication chn pc2
          with Not_found ->
            assert false (* cannot happen *)
        in
        PC.add_assumption a true pc2 :: alst,
        chn
      )
      (ass_lst_rev, chn)
      0
      nass
  in
  (* Now we have context [all(other_vars) require a1; a2; ...] *)
  PC.close pc2;
  ass_lst_rev, goal, goal_pred1, pc2






let rec prove_and_store
    (entlst: entities list withinfo)
    (rlst: compound)
    (elst: compound)
    (prf:  proof_support_option)
    (pc:PC.t)
    : unit =
  if PC.is_public pc then begin
    match prf with
      None -> ()
    | Some prf when prf.v = PS_Deferred -> ()
    | Some prf ->
        error_info prf.i "Proof not allowed in interface file"
  end;
  let rlst, elst, pc1 = push entlst rlst elst pc in
  add_assumptions rlst pc1;
  let prove_goal () =
    PC.close pc1;
    let goal = one_goal elst in
    verify_preconditions goal pc1;
    let idx =
      try
        prove_one goal.v prf pc1
      with  Proof.Proof_failed msg ->
        error_info goal.i ("Cannot prove" ^ msg)
    in
    let t,pt = PC.discharged_bubbled idx pc1 in
    ignore (PC.add_proved false (-1) t pt pc)
  in
  match prf with
    None when PC.is_interface_use pc1 ->
      store_unproved false elst pc1
  | None when PC.is_interface_check pc1 ->
      PC.close pc1;
      prove_goals elst pc1
  | None ->
      prove_goal ()
  | Some prf1 ->
      match prf1.v with
        PS_Axiom ->
          store_unproved false elst pc1
      | PS_Deferred ->
          store_unproved true elst pc1
      | _ ->
          prove_goal ()


and prove_one
    (goal:term) (prf:proof_support_option) (pc:PC.t)
    : int =
  (* Prove [goal] with the proof support [prf]. Assume that the preconditions
     of the goal are already verified. *)
  assert (PC.is_private pc);
  match prf with
    None ->
      Prover.prove_and_insert goal pc
  | Some prf ->
      try
        begin
          match prf.v with
            PS_Axiom | PS_Deferred ->
              assert false (* cannot happen *)
          | PS_Sequence lst ->
              prove_sequence lst goal pc
          | PS_If (cond, prf1, prf2) ->
              prove_if prf.i goal cond prf1 prf2 pc
          | PS_Guarded_If (cond1, prf1, cond2, prf2) ->
              prove_guarded_if prf.i goal cond1 prf1 cond2 prf2  pc
          | PS_Inspect (insp, cases) ->
              prove_inspect prf.i goal insp cases pc
          | PS_Existential (entlst, reqs, prf1) ->
              prove_exist_elim prf.i goal entlst reqs prf1 pc
          | PS_Contradiction (exp,prf1) ->
              prove_contradiction prf.i goal exp prf1 pc
        end
      with Proof.Proof_failed msg ->
        error_info prf.i ("Does not prove \"" ^
                          (PC.string_of_term goal pc) ^
                          "\"" ^ msg)


and prove_sequence
    (lst: proof_step list)
    (goal: term)
    (pc: PC.t): int =
  List.iter
    (fun step ->
      begin match step with
        PS_Simple ie ->
          let it = get_boolean_term_verified ie pc in
          ignore (prove_insert_report it true pc)
      | PS_Structured (entlst,rlst,tgt,prf) ->
          let rlst, elst, pc1 = push entlst rlst [tgt] pc in
          add_assumptions rlst pc1;
          PC.close pc1;
          let goal = List.hd elst in
          verify_preconditions goal pc1;
          let idx =
            try
              prove_one goal.v prf pc1
            with Proof.Proof_failed msg ->
              error_info goal.i ("Cannot prove" ^ msg)
          in
          let t,pt = PC.discharged_bubbled idx pc1 in
          ignore(PC.add_proved false (-1) t pt pc)
      end;
      PC.close pc
    )
    lst;
  Prover.prove_and_insert goal pc


and prove_guarded_if
    (info: info)
    (goal: term)
    (c1:info_expression) (prf1:proof_support_option)
    (c2:info_expression) (prf2:proof_support_option)
    (pc:PC.t)
    : int =
  let c1 = get_boolean_term_verified c1 pc
  and c2 = get_boolean_term_verified c2 pc
  in
  let or_exp = PC.disjunction c1.v c2.v pc in
  let or_exp_idx =
    prove_insert_report (withinfo info or_exp) false pc
  and or_elim_idx =
    try
      PC.or_elimination pc
    with Not_found ->
      error_info info "Or elimination law not available"
  in
  let result_idx =
    PC.specialized or_elim_idx [|c1.v;c2.v;goal|] [||] 0 pc in
  let result_idx =
    PC.add_mp or_exp_idx result_idx false pc in
  let result_idx =
    let branch1_idx = prove_branch c1 goal prf1 pc in
    PC.add_mp branch1_idx result_idx false pc in
  let branch2_idx = prove_branch c2 goal prf2 pc in
  PC.add_mp branch2_idx result_idx false pc


and prove_if
    (info: info)
    (goal: term)
    (c1:info_expression)
    (prf1:proof_support_option)
    (prf2:proof_support_option)
    (pc:PC.t)
    : int =
  let c1 = get_boolean_term_verified c1 pc
  in
  let c1neg = PC.negation c1.v pc
  in
  let em_idx =
    try
      PC.excluded_middle pc
    with Not_found ->
      error_info info "Excluded middle law not available"
  and or_elim_idx =
    try
      PC.or_elimination pc
    with Not_found ->
      error_info info "Or elimination law not available"
  in
  let spec_em_idx =
    PC.specialized em_idx [|c1.v|] [||] 0 pc
  and spec_or_elim_idx =
    PC.specialized or_elim_idx [|c1.v;c1neg;goal|] [||] 0 pc
  in
  let result_idx =
    PC.add_mp spec_em_idx spec_or_elim_idx false pc in
  let result_idx =
    let branch1_idx = prove_branch c1 goal prf1 pc in
    PC.add_mp branch1_idx result_idx false pc in
  let branch2_idx = prove_branch (withinfo c1.i c1neg) goal prf2 pc in
  PC.add_mp branch2_idx result_idx false pc


and prove_branch
    (cond:info_term) (goal:term) (prf:proof_support_option) (pc:PC.t)
    : int =
  let pc1 = PC.push_empty pc in
  ignore (PC.add_assumption cond.v true pc1);
  PC.close pc1;
  let idx = prove_one goal prf pc1 in
  let t,pt = PC.discharged_bubbled idx pc1 in
  PC.add_proved_term t pt false pc


and prove_inspect
    (info:info)
    (goal:term)
    (insp:info_expression) (cases:one_case list) (pc:PC.t): int =
  let insp = get_term insp pc in
  match insp.v with
    Variable var_idx ->
      prove_inductive_type info goal var_idx cases pc
  | Application (set,args,pr) when pr ->
      assert (Array.length args = 1);
      prove_inductive_set info goal args.(0) set cases pc
  | _ ->
      error_info info "Illegal induction proof"


and prove_inductive_type
    (info:info)
    (goal:term)
    (ivar: int) (* induction variable *)
    (cases: one_case list)
    (pc:PC.t)
    : int =
  let cons_set, ind_idx, tp =
    analyze_type_inspect info ivar goal pc
  in
  let _,ags = Class_table.split_type_term tp in
  if PC.is_tracing pc then begin
    let prefix = PC.trace_prefix pc in
    printf "\n\n%sInduction Proof\n\n" prefix;
    printf "%sensure\n" prefix;
    printf "%s    %s\n" prefix (PC.string_long_of_term goal pc);
    printf "%sinspect\n" prefix;
    printf "%s    %s\n\n"
      prefix
      (ST.string (Context.argnames (PC.context pc)).(ivar))
  end;
  let pc_outer = pc in
  let pc = PC.push_untyped [||] pc_outer in
  let c  = PC.context pc in
  let nvars = Context.count_variables c
  and ft  = Context.feature_table c in
  let proved_cases =
    (* explicitly given cases *)
    List.fold_left
      (fun map (ie,prf) ->
        let cons_idx, pat, pc1 =
          analyze_type_case_pattern ie cons_set tp pc in
        let idx = prove_type_case cons_idx tp pat prf ivar goal pc1 pc in
        IntMap.add cons_idx idx map
      )
      IntMap.empty
      cases
  in
  let ind_idx =
    (* rest of the cases *)
    IntSet.fold
      (fun cons_idx ind_idx ->
        let idx =
          try
            IntMap.find cons_idx proved_cases
          with Not_found ->
            let n   = Feature_table.arity cons_idx ft
            and ntvs = PC.count_all_type_variables pc
            in
            let nms = anon_argnames n
            and tps = Feature_table.argument_types cons_idx ags ntvs ft
            in
            let pc1 = PC.push_typed (nms,tps) empty_formals pc in
            let pat =
              let args = standard_substitution n in
              Feature_table.feature_call cons_idx (nvars+n) args ags ft
            in
            prove_type_case cons_idx tp pat None ivar goal pc1 pc
        in
        PC.add_mp idx ind_idx false pc
      )
      cons_set
      ind_idx
  in
  let t,pt = PC.discharged_bubbled ind_idx pc in
  let idx = PC.add_proved_term t pt false pc_outer in
  PC.add_beta_reduced idx false pc_outer



and prove_type_case
    (cons_idx:int)
    (tp:type_term)  (* inductive type in the outer context *)
    (pat:term)      (* in the inner context *)
    (prf:proof_support_option)
    (ivar:int)
    (goal:term)     (* in the outer context *)
    (pc1:PC.t)      (* inner context *)
    (pc:PC.t)       (* outer context *)
    : int =
  (* Prove one case of an inductive type
   *)
  let nvars = PC.count_variables pc
  and ft    = PC.feature_table pc
  and c1    = PC.context pc1
  in
  (* The inner context might have type variables, therefore we adapt only the
     type part to the inner context. *)
  let ntvs_delta = Context.count_local_type_variables c1 in
  let tp1 = Term.up_type ntvs_delta tp
  and goal1 = Term.shift 0 ntvs_delta goal
  in
  let n,_,_,ps_rev,case_goal =
    let t0 = Term.lambda_inner goal1 ivar
    and p_tp = PC.predicate_of_type tp1 pc1 in
    let p   = Lam(1, anon_argnames 1, [], t0, true, p_tp)
    and _, ags = Class_table.split_type_term tp1 in
    Feature_table.constructor_rule cons_idx p ags nvars ft in
  assert (n = PC.count_last_arguments pc1);
  if PC.is_tracing pc then begin
    let prefix = PC.trace_prefix pc1 in
    printf "\n\n%scase\n" prefix;
    printf "%s    %s\n"   prefix (PC.string_long_of_term pat pc1);
    if List.length ps_rev <> 0 then begin
      printf "%srequire\n" prefix;
      List.iter
        (fun t ->
          let t = PC.beta_reduce_term t pc1 in
          printf "%s    %s\n" prefix (PC.string_long_of_term t pc1))
        (List.rev ps_rev)
    end;
    printf "%sensure\n" prefix;
    let t = PC.beta_reduce_term case_goal pc1 in
    printf "%s    %s\n\n" prefix (PC.string_long_of_term t pc1)
  end;
  List.iter
    (fun ass ->
      ignore (PC.add_assumption ass true pc1))
    (List.rev ps_rev);
  PC.close pc1;
  let case_goal_idx =
    prove_one case_goal prf pc1
  in
  let t,pt = PC.discharged case_goal_idx pc1 in
  PC.add_proved_term t pt false pc




and prove_inductive_set
    (info:info)
    (goal:term)
    (elem:term)
    (set: term)
    (cases: one_case list)
    (pc:PC.t)
    : int =
  (* Execute a proof with an inductive set:

         ensure
             ens
         inspect
             elem in set      -- 'elem in set' must be valid

         case         -- List of zero of more cases, each case represents a
             ...      -- rule for 'elem in set' to be valid
         proof
             ...

         ...
         end
   *)
  assert (not (PC.is_global pc));
  let data = inductive_set_context info elem set goal pc
  in
  let nrules = Array.length data.rules
  in
  let proved =
    List.fold_left
      (fun proved (ie,prf) ->
        let irule, rule = inductive_set_case ie data in
        let ass_lst_rev, goal, goal_pred, pc_inner =
          inductive_set_case_context
            data.set
            data.set_expanded
            rule
            irule
            data.nass
            data.goal_predicate
            pc in
        let idx =
          prove_inductive_set_case
            ie.i rule ass_lst_rev goal goal_pred prf pc_inner data.pc
        in
        IntMap.add irule idx proved
      )
      IntMap.empty
      cases
  in
  let ind_idx =
    interval_fold
      (fun ind_idx irule ->
        let rule_idx =
          try
            IntMap.find irule proved
          with Not_found ->
            let ass_lst_rev, goal, goal_pred, pc_inner =
              inductive_set_case_context
                data.set
                data.set_expanded
                data.rules.(irule)
                irule
                data.nass
                data.goal_predicate
                pc
            in
            prove_inductive_set_case
              info data.rules.(irule) ass_lst_rev goal goal_pred None pc_inner data.pc
        in
        PC.add_mp rule_idx ind_idx false data.pc
      )
      data.induction_rule 0 nrules
  in
  let gidx = PC.add_mp data.element_in_set ind_idx false data.pc
  in
  PC.add_beta_reduced gidx false pc



and prove_inductive_set_case
    (info:info)
    (rule:term)                   (* in the outer context *)
    (ass_lst_rev: int list)
    (goal: term)                  (* in the inner context *)
    (goal_pred: term)             (* in the middle context *)
    (prf:  proof_support_option)
    (pc1:PC.t)                    (* inner context *)
    (pc0:PC.t)                    (* outer context *)
    : int =
  if PC.is_tracing pc0 then begin
    let prefix = PC.trace_prefix pc0 in
    printf "\n\n";
    printf "%scase\n" prefix;
    printf "%s    %s\n" prefix (PC.string_long_of_term rule pc0);
    printf "%sgoal\n" prefix;
    printf "%s\n"
      (string_of_case_context (prefix ^ "    ") ass_lst_rev goal pc1);
  end;
  let gidx =
    try
      prove_one goal prf pc1
    with Proof.Proof_failed msg ->
      let casestr = string_of_case_context "" ass_lst_rev goal pc1
      and rulestr = PC.string_of_term rule pc0 in
      error_info info ("Cannot prove case \"" ^ rulestr ^ "\""
                       ^ msg ^ casestr)
  in
  let t,pt = PC.discharged gidx pc1 in
  let pc01 = PC.pop pc1 in
  let idx = PC.add_proved_term t pt false pc01 in
  let idx = PC.add_beta_redex goal_pred idx false pc01 in
  let t,pt = PC.discharged idx pc01 in
  PC.add_proved_term t pt false pc0



and prove_exist_elim
    (info: info)
    (goal: term)
    (entlst: entities list withinfo)
    (reqs: info_expression list)
    (prf:  proof_support_option)
    (pc:PC.t)
    : int =
  assert (reqs <> []);
  PC.close pc;
  let req =
    List.fold_left
      (fun left right ->
        let right = Expparen right.v in
        Binexp (Andop,left,right)
      )
      (Expparen (List.hd reqs).v)
      (List.tl reqs)
  in
  let someexp = (withinfo info (Expquantified (Existential,entlst,req))) in
  let someexp = get_boolean_term_verified someexp pc in
  let someexp_idx =
    try
      let t,pt = Prover.proof_term someexp.v pc in
      PC.add_proved_term t pt false pc
    with Proof.Proof_failed msg ->
      error_info
        someexp.i
        ("Cannot prove \"" ^ (PC.string_of_term someexp.v pc) ^
         "\"" ^ msg)
  in
  let elim_idx = PC.add_some_elim_specialized someexp_idx goal false pc in
  let n,fargs,t0 = Term.some_quantifier_split someexp.v in
  let pc1 = PC.push_typed fargs empty_formals pc in
  ignore (PC.add_assumption t0 true pc1);
  PC.close pc1;
  let goal = Term.up n goal in
  let goal_idx = prove_one goal prf pc1 in
  let t,pt = PC.discharged goal_idx pc1 in
  let all_idx = PC.add_proved_term t pt false pc in
  PC.add_mp all_idx elim_idx false pc





and prove_contradiction
    (info: info)
    (goal: term)
    (exp:  info_expression)
    (prf:  proof_support_option)
    (pc:PC.t)
    : int =
  let exp = get_boolean_term exp pc in
  let pc1 = PC.push_empty pc in
  ignore (PC.add_assumption exp.v true pc1);
  PC.close pc1;
  let false_idx =
    try
      prove_one (PC.false_constant pc1) prf pc1
    with Proof.Proof_failed msg ->
      error_info
        info
        ("Cannot derive \"false\" from \"" ^
         (PC.string_of_term exp.v pc1) ^ "\"")
  in
  let t,pt = PC.discharged false_idx pc1 in
  ignore(PC.add_proved_term t pt true pc);
  PC.close pc;
  prove_one goal None pc
