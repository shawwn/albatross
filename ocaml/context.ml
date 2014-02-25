open Container
open Term
open Signature
open Support





module Global_context: sig

  type t
  val make: unit -> t
  val is_private: t -> bool
  val is_public:  t -> bool
  val set_visibility: visibility -> t -> unit
  val reset_visibility: t -> unit
  val ct:  t -> Class_table.t
  val ft:  t -> Feature_table.t
  val at:  t -> Assertion_table.t

end = struct
  type t = {
      mutable visi: visibility;
      ct: Class_table.t;
      ft: Feature_table.t;
      at: Assertion_table.t;
    }

  let make (): t =
    {visi = Public;
     ct = Class_table.base_table ();
     ft = Feature_table.empty ();
     at = Assertion_table.empty ()}

  let is_private (g:t): bool =
    match g.visi with
      Private -> true
    | _ -> false

  let is_public (g:t): bool = not (is_private g)

  let set_visibility (v:visibility) (g:t): unit =  g.visi <- v

  let reset_visibility (g:t): unit =  g.visi <- Public

  let ct (g:t): Class_table.t      = g.ct
  let ft (g:t): Feature_table.t    = g.ft
  let at (g:t): Assertion_table.t  = g.at
end (* Global_context *)








module Local_context: sig

  type t
  val make_first:
      entities list withinfo -> return_type -> Global_context.t -> t
  val make_next:
      entities list withinfo -> return_type -> t -> t
  val arity:     t -> int
  val argument:  int -> t -> int * TVars.t * Sign.t

  val nfgs:    t -> int
  val fgnames: t -> int array

  val tvars_sub: t -> TVars_sub.t

end = struct

  type t = {
      fgnames:   int array;        (* cumulated        *)
      concepts:  type_term array;  (* cumulated        *)
      argnames:  int array;        (* cumulated        *)
      signature: Sign.t;           (* from declaration *)
      tvars_sub: TVars_sub.t;      (* cumulated        *)
      ct:        Class_table.t
    }


  let make_first
      (entlst: entities list withinfo)
      (rt: return_type)
      (g: Global_context.t)
      : t =
    (** Make a first local context with the argument list [entlst] and the
        return type [rt] based on the global context [g]
     *)
    let ct = Global_context.ct g in
    let fgnames, concepts, argnames, ntvs, sign =
      Class_table.signature entlst rt [||] [||] [||] 0 ct
    in
    {fgnames    =  fgnames;
     concepts   =  concepts;
     argnames   =  argnames;
     signature  =  sign;
     tvars_sub  =  TVars_sub.make ntvs;
     ct         =  ct}



  let make_next
      (entlst: entities list withinfo)
      (rt: return_type)
      (loc: t)
      : t =
    (** Make a next local context with the argument list [entlst] and the
        return type [rt] based on previous local global context [loc]
     *)
    let fgnames, concepts, argnames, ntvs, sign =
      let ntvs0 = TVars_sub.count_local loc.tvars_sub in
      Class_table.signature entlst rt
        loc.fgnames loc.concepts loc.argnames ntvs0 loc.ct
    in
    {fgnames   =  fgnames;
     concepts  =  concepts;
     argnames  =  argnames;
     signature =  sign;
     tvars_sub =  TVars_sub.add_local ntvs loc.tvars_sub;
     ct        =  loc.ct}


  let arity     (loc:t): int = Sign.arity loc.signature

  let argument (name:int) (loc:t): int * TVars.t * Sign.t =
    (** The term and the signature of the argument named [name] *)
    let i = Search.array_find_min name loc.argnames in
    i, TVars_sub.tvars loc.tvars_sub, Sign.argument i loc.signature

  let nfgs (loc:t): int =
    (** The cumulated number of formal generics in this context and all
        previous contexts
     *)
    Array.length loc.fgnames

  let fgnames (loc:t): int array=
    (** The cumulated formal generic names of this context and all
        previous contexts
     *)
    loc.fgnames


  let tvars_sub (loc:t): TVars_sub.t = loc.tvars_sub

end (* Local_context *)







module Context: sig

  type t

  val make:  unit -> t

  val is_basic:     t -> bool
  val is_public:    t -> bool
  val is_private:   t -> bool
  val set_visibility:   visibility -> t -> unit
  val reset_visibility: t -> unit
  val push: entities list withinfo -> return_type -> t -> t

  val global:       t -> Global_context.t
  val local:        t -> Local_context.t

  val put_formal_generic: int withinfo -> type_t withinfo -> t -> unit
  val put_class: header_mark withinfo -> int withinfo -> t -> unit
  val put_feature: feature_name withinfo -> entities list withinfo
    -> return_type -> feature_body option -> t -> unit
  val print: t -> unit

  val find_identifier: int -> int -> t
    -> (int * TVars.t * Sign.t) list * int

  val find_feature:    feature_name -> int -> t
    -> (int * TVars.t * Sign.t) list * int

  val type_variables:  t -> TVars_sub.t

end = struct


  type t =
      Basic    of Global_context.t
    | Combined of Local_context.t * t


  let make (): t =
    Basic (Global_context.make ())


  let rec global (c:t): Global_context.t =
    match c with
      Basic g -> g
    | Combined (_,c) -> global c


  let is_basic (c:t): bool =
    match c with
      Basic _ -> true
    | _       -> false


  let local (c:t): Local_context.t =
    assert (not (is_basic c));
    match c with
      Basic _ -> assert false
    | Combined (loc,_) -> loc


  let is_private (c:t): bool =
    Global_context.is_private (global c)


  let is_public (c:t): bool =
    Global_context.is_public (global c)


  let set_visibility (v:visibility) (c:t): unit =
    assert (is_basic c);
    match c with
      Basic g -> Global_context.set_visibility v g
    | _       -> assert false (* illegal path *)


  let reset_visibility (c:t): unit =
    assert (is_basic c);
    match c with
      Basic g -> Global_context.reset_visibility g
    | _       -> assert false (* illegal path *)




  let push
      (entlst: entities list withinfo)
      (rt: return_type)
      (c:t)
      : t =
    (** Push the entity list [entlst] with the return type [rt] as a new
        local context onto the context [c]
     *)
    let loc =
      match c with
        Basic g ->           Local_context.make_first entlst rt g
      | Combined (loc,c) ->  Local_context.make_next  entlst rt loc
    in
    Combined (loc,c)


  let put_class (hm:header_mark withinfo) (cn:int withinfo) (c:t): unit =
    assert (is_basic c);
    Class_table.put hm cn (Global_context.ct (global c))




  let put_formal_generic
      (name:int withinfo)
      (concept:type_t withinfo)
      (c:t)
      : unit =
    (** Add the formal generic [name] with its [concept] to the formal
        generics.
     *)
    assert (is_basic c);
    Class_table.put_formal name concept (Global_context.ct (global c))




  let put_feature
      (fn: feature_name withinfo)
      (entlst: entities list withinfo)
      (rt: return_type)
      (bdy: feature_body option)
      (c: t): unit =
    (** Add the feature [fn] with [entlst] [rt] and [bdy] to the global context
     *)
    assert (is_basic c);
    let g = global c in
    let ct,ft = Global_context.ct g, Global_context.ft g in
    Feature_table.put fn entlst rt bdy (is_private c) ct ft

  let print (c:t): unit =
    assert (is_basic c);
    let g = global c in
    let ct,ft = Global_context.ct g, Global_context.ft g in
    Class_table.print ct;
    Feature_table.print ct ft


  let find_identifier
      (name:int)
      (nargs:int)
      (c:t)
      : (int * TVars.t * Sign.t) list * int =
    (** Find the identifier named [name] which accepts [nargs] arguments
        in one of the local contexts or in the global feature table. Return
        the list of variables together with their signature and the difference
        of the number of variables between the actual context [c] and the
        context where the identifier has been found
     *)
    let rec ident (nvars:int) (c:t)
        :(int * TVars.t * Sign.t) list * int =
      match c with
        Basic g ->
          (Feature_table.find_funcs (FNname name) nargs (Global_context.ft g),
           nvars)
      | Combined (loc,c) ->
          try
            let i,tvs,s = Local_context.argument name loc
            in
            if (Sign.arity s) = nargs then
              [i,tvs,s], nvars
            else
              raise Not_found
          with Not_found ->
            ident (Local_context.arity loc) c

    in
    ident 0 c


  let find_feature
      (fn:feature_name)
      (nargs:int)
      (c:t)
      : (int * TVars.t * Sign.t) list * int =
    (** Find the feature named [fn] which accepts [nargs] arguments global
        feature table. Return the list of variables together with their
        signature and the difference of the number of variables between the
        actual context [c] and the global context.
      *)
    let rec feat (nvars:int) (c:t)
        :(int * TVars.t * Sign.t) list * int =
      match c with
        Basic g ->
          (Feature_table.find_funcs fn nargs (Global_context.ft g),
           nvars)
      | Combined (loc,c) ->
            feat (Local_context.arity loc) c

    in
    feat 0 c


  let type_variables (c:t): TVars_sub.t =
    assert (not (is_basic c));
    match c with
      Basic _ -> assert false (* illegal path *)
    | Combined (loc,_) -> Local_context.tvars_sub loc

  let update_type_variables (tv:TVars_sub.t) (c:t): t =
    assert (not (is_basic c));
    assert false

end (* Context *)