(** The abstract syntax of Andromedan type theory (TT). *)

type ('a, 'b) abstraction = (Name.ident * 'a) * 'b

type term = {
  term : term';
  (* raw term *)

  assumptions : Assumption.t;
  (* set of atoms on which the term depends *)

  loc : Location.t
  (* the location in input where the term appeared, as much as that makes sense *)
}

and term' =
  | Type
  | Atom of Name.atom
  | Bound of Syntax.bound
  | Constant of Name.ident
  | Lambda of (term * ty) ty_abstraction
  | Apply of term * ty ty_abstraction * term
  | Prod of ty ty_abstraction
  | Eq of ty * term * term
  | Refl of ty * term
  | Signature of Name.ident
  | Structure of structure
  | Projection of term * Name.ident * Name.label

and ty = Ty of term

and 'a ty_abstraction = (ty, 'a) abstraction

and signature = (Name.ident * Name.ident * ty) list

and structure = Name.signature * term list

(** We disallow direct creation of terms (using the [private] qualifier in the interface
    file), so we provide these constructors instead. *)

(* Helpers *)
let ty_hyps (Ty e) = e.assumptions
let rec hyp_union acc = function
  | [] -> acc
  | x::rem -> hyp_union (Assumption.union acc x) rem

let mk_atom ~loc x = {
  term = Atom x;
  assumptions = Assumption.singleton x;
  loc = loc
}

let mk_constant ~loc x = {
  term = Constant x;
  assumptions=Assumption.empty;
  loc = loc
}

let mk_lambda ~loc x a e b = {
  term = Lambda ((x, a), (e, b)) ;
  assumptions=hyp_union (ty_hyps a) (List.map (Assumption.bind 1) [ty_hyps b;e.assumptions]) ;
  loc = loc
}

let mk_prod ~loc x a b = {
  term = Prod ((x, a), b) ;
  assumptions=hyp_union (ty_hyps a) [Assumption.bind 1 (ty_hyps b)] ;
  loc = loc
}

let mk_apply ~loc e1 x a b e2 = {
  term = Apply (e1, ((x, a),b), e2);
  assumptions = hyp_union (ty_hyps a) [Assumption.bind 1 (ty_hyps b);e1.assumptions;e2.assumptions] ;
  loc = loc
}

let mk_type ~loc =
  { term = Type;
    assumptions = Assumption.empty;
    loc = loc }

let mk_eq ~loc t e1 e2 =
  { term = Eq (t, e1, e2);
    assumptions = hyp_union (ty_hyps t) [e1.assumptions;e2.assumptions];
    loc = loc }

let mk_refl ~loc t e =
  { term = Refl (t, e);
    assumptions = hyp_union (ty_hyps t) [e.assumptions];
    loc = loc }

let mk_signature ~loc s =
  { term = Signature s;
    assumptions = Assumption.empty;
    loc = loc }

let mk_structure ~loc s es =
  { term = Structure (s, es);
    assumptions = List.fold_left (fun acc e -> Assumption.union acc e.assumptions)
                                 Assumption.empty es;
    loc = loc }

let mk_projection ~loc e s l =
  { term = Projection (e, s, l);
    assumptions = e.assumptions;
    loc = loc }

(** Convert a term to a type. *)
let ty e = Ty e

let mk_eq_ty ~loc t e1 e2 = ty (mk_eq ~loc t e1 e2)
let mk_prod_ty ~loc x a b = ty (mk_prod ~loc x a b)
let mk_type_ty ~loc = ty (mk_type ~loc)
let mk_signature_ty ~loc s = ty (mk_signature ~loc s)

(** The [Type] constant, without a location. *)
let typ = Ty (mk_type ~loc:Location.unknown)

let mention_atoms a e =
  { e with assumptions = Assumption.add_atoms a e.assumptions }

let mention a e =
  { e with assumptions = Assumption.union e.assumptions a }

let gather_assumptions {assumptions;_} = assumptions

let assumptions_term ({loc;_} as e) =
  let a = gather_assumptions e in
  Assumption.as_atom_set ~loc a

let assumptions_ty (Ty t) = assumptions_term t


(** Generic fold on a term. The functions [atom], [bound] and
    [hyps] tell it what to do with atoms, bound variables, and
    assumptions, respectively. *)
let rec at_var atom bound hyps ~lvl {term=e';assumptions;loc} =
  let assumptions = hyps ~lvl assumptions in
  match e' with
    | (Type | Constant _ | Signature _) as term -> {term;assumptions;loc}
    | Atom x -> atom ~lvl x assumptions loc
    | Bound k -> bound ~lvl k assumptions loc
    | Prod ((x,a),b) ->
      let a = at_var_ty atom bound hyps ~lvl a
      and b = at_var_ty atom bound hyps ~lvl:(lvl+1) b in
      let term = Prod ((x,a),b) in
      {term;assumptions;loc}
    | Lambda ((x,a),(e,b)) ->
      let a = at_var_ty atom bound hyps ~lvl a
      and b = at_var_ty atom bound hyps ~lvl:(lvl+1) b
      and e = at_var atom bound hyps ~lvl:(lvl+1) e in
      let term = Lambda ((x,a),(e,b)) in
      {term;assumptions;loc}
    | Apply (e1,((x,a),b),e2) ->
      let a = at_var_ty atom bound hyps ~lvl a
      and b = at_var_ty atom bound hyps ~lvl:(lvl+1) b
      and e1 = at_var atom bound hyps ~lvl e1
      and e2 = at_var atom bound hyps ~lvl e2 in
      let term = Apply (e1,((x,a),b),e2) in
      {term;assumptions;loc}
    | Eq (a,e1,e2) ->
      let a = at_var_ty atom bound hyps ~lvl a
      and e1 = at_var atom bound hyps ~lvl e1
      and e2 = at_var atom bound hyps ~lvl e2 in
      let term = Eq (a,e1,e2) in
      {term;assumptions;loc}
    | Refl (a,e) ->
      let a = at_var_ty atom bound hyps ~lvl a
      and e = at_var atom bound hyps ~lvl e in
      let term = Refl (a,e) in
      {term;assumptions;loc}
    | Structure (s, es) ->
      let es = at_var_struct atom bound hyps ~lvl es in
      let term = Structure (s, es) in
      {term;assumptions;loc}
    | Projection (e,s,l) ->
      let e = at_var atom bound hyps ~lvl e in
      let term = Projection (e,s,l) in
      {term;assumptions;loc}

and at_var_ty atom bound hyps ~lvl (Ty a) =
  Ty (at_var atom bound hyps ~lvl a)

and at_var_struct atom bound hyps ~lvl es =
  List.map (at_var atom bound hyps ~lvl) es

(** Instantiate *)
let instantiate_atom ~lvl x assumptions loc =
  {term=Atom x;assumptions;loc}

let instantiate_bound es ~lvl k assumptions loc =
  if k < lvl
  then
    {term=Bound k;assumptions;loc}
    (* this is a variable bound in an abstraction inside the
    instantiated term, so we leave it as it is *)
  else
    let n = List.length es in
    if k < lvl + n
    then (* variable corresponds to a substituted term, replace it *)
      let e = List.nth es (k - lvl) in
      mention assumptions e
    else
      {term = Bound (k - n); assumptions; loc}
      (* this is a variable bound in an abstraction outside the
         instantiated term, so it remains bound, but its index decreases
         by the number of bound variables replaced by terms *)

let instantiate_hyps es =
  let hs = List.map gather_assumptions es in
  fun ~lvl h -> Assumption.instantiate hs lvl h

let instantiate es ?(lvl=0) e =
  if es = [] then e else
  at_var instantiate_atom (instantiate_bound es) (instantiate_hyps es) ~lvl e

let instantiate_ty es ?(lvl=0) (Ty t) =
  let t = instantiate es ~lvl t
  in Ty t

let unabstract xs ?(lvl=0) e =
  let es = List.map (mk_atom ~loc:Location.unknown) xs
  in instantiate es ~lvl e

let unabstract_ty xs ?(lvl=0) (Ty t) =
  let t = unabstract xs ~lvl t
  in Ty t


(** Abstract *)
let abstract_atom xs ~lvl x assumptions loc =
  begin
    match Name.index_of_atom x xs with
      | None -> {term=Atom x;assumptions;loc}
      | Some k -> {term = Bound (lvl + k); assumptions; loc}
  end

let abstract_bound ~lvl k assumptions loc =
  {term=Bound k;assumptions;loc}

let abstract_hyps xs ~lvl h =
  Assumption.abstract xs lvl h

let abstract xs ?(lvl=0) e =
  if xs = [] then e else
  at_var (abstract_atom xs) abstract_bound (abstract_hyps xs) ~lvl e

let abstract_ty xs ?(lvl=0) (Ty t) =
  let t = abstract xs ~lvl t
  in Ty t

(** Substitute *)
let substitute xs es t =
  if xs = [] && es = []
  then t
  else
    let t = abstract xs ~lvl:0 t in
    instantiate es ~lvl:0 t

let substitute_ty xs es (Ty ty) =
  Ty (substitute xs es ty)

(** Occurs (for printing) *)
let occurs_abstraction occurs_u occurs_v k ((x,u), v) =
  occurs_u k u + occurs_v (k+1) v

(* How many times does bound variable [k] occur in an expression? Used only for printing. *)
let rec occurs k {term=e';_} =
  match e' with
  | Type -> 0
  | Atom _ -> 0
  | Signature _ -> 0
  | Bound m -> if k = m then 1 else 0
  | Constant x -> 0
  | Lambda a -> occurs_abstraction occurs_ty occurs_term_ty k a
  | Apply (e1, xtst, e2) ->
    occurs k e1 +
    occurs_abstraction occurs_ty occurs_ty k xtst +
    occurs k e2
  | Prod a ->
    occurs_abstraction occurs_ty occurs_ty k a
  | Eq (t, e1, e2) ->
    occurs_ty k t + occurs k e1 + occurs k e2
  | Refl (t, e) ->
    occurs_ty k t + occurs k e
  | Structure (_, es) ->
     let rec fold res = function
       | [] -> res
       | e :: es ->
          let j = occurs k e in
          fold (res+j) es
     in
     fold 0 es
  | Projection (e,_,_) -> occurs k e

and occurs_ty k (Ty t) = occurs k t

and occurs_term_ty k (e, t) =
  occurs k e + occurs_ty k t

let occurs_ty_abstraction f = occurs_abstraction occurs_ty f


(****** Alpha equality ******)

(* Currently, the only difference between alpha and structural equality is that
   the names of variables in abstractions are ignored. *)
let alpha_equal_abstraction alpha_equal_u alpha_equal_v ((x,u), v) ((x,u'), v') =
  alpha_equal_u u u' &&
  alpha_equal_v v v'

let rec alpha_equal {term=e1;_} {term=e2;_} =
  e1 == e2 || (* a shortcut in case the terms are identical *)
  begin match e1, e2 with

    | Atom x, Atom y -> Name.eq_atom x y

    | Bound i, Bound j -> i = j

    | Constant x, Constant y -> Name.eq_ident x y

    | Lambda abs, Lambda abs' ->
      alpha_equal_abstraction alpha_equal_ty alpha_equal_term_ty abs abs'

    | Apply (e1, xts, e2), Apply (e1', xts', e2') ->
      alpha_equal e1 e1' &&
      alpha_equal_abstraction alpha_equal_ty alpha_equal_ty xts xts' &&
      alpha_equal e2 e2'

    | Type, Type -> true

    | Prod abs, Prod abs' ->
      alpha_equal_abstraction alpha_equal_ty alpha_equal_ty abs abs'

    | Eq (t, e1, e2), Eq (t', e1', e2') ->
      alpha_equal_ty t t' &&
      alpha_equal e1 e1' &&
      alpha_equal e2 e2'

    | Refl (t, e), Refl (t', e') ->
      alpha_equal_ty t t' &&
      alpha_equal e e'

    | Signature s1, Signature s2 -> Name.eq_ident s1 s2

    | Structure (s1, lst1), Structure (s2, lst2) ->
       Name.eq_ident s1 s2 &&
         begin
           let rec fold lst1 lst2 =
             match lst1, lst2 with
             | [], [] -> true
             | e1::lst1, e2::lst2 -> alpha_equal e1 e2 && fold lst1 lst2
             | [],_::_ | _::_,[] -> Error.impossible ~loc:Location.unknown "alpha_equal: malformed structures"
           in
           fold lst1 lst2
         end

    | Projection (e1, s1, l1), Projection (e2, s2, l2) ->
       Name.eq_ident s1 s2 &&
       Name.eq_ident l1 l2 &&
       alpha_equal e1 e2

    | (Atom _ | Bound _ | Constant _ | Lambda _ | Apply _ |
        Type | Prod _ | Eq _ | Refl _ |
        Signature _ | Structure _ | Projection _), _ ->
      false
  end

and alpha_equal_ty (Ty t1) (Ty t2) = alpha_equal t1 t2

and alpha_equal_term_ty (e, t) (e', t') = alpha_equal e e' && alpha_equal_ty t t'


(****** Printing routines *****)

type print_env =
  { forbidden : Name.ident list ;
    sigs : Name.signature -> Name.label list }

let add_forbidden x penv = { penv with forbidden = x :: penv.forbidden }

(** Optionally print a typing annotation in brackets. *)
let print_annot ?(prefix="") k ppf =
  if !Config.annotate then
    Format.fprintf ppf "%s[@[%t@]]" prefix k
  else
    Format.fprintf ppf ""

(*

  Level 0: Type, name, bound
  Level 1: apply (0,0), refl (0)
  Level 2: eq (1,1)
  Level 3: lambda, prod, arrow

  let, ascribe

*)

let print_binder1  ~penv print_u x u ppf =
  Print.print ppf "(@[<hv>%t :@ %t@])"
    (Name.print_ident x) (print_u ~penv u)

let print_binders ~penv print_xu print_v (x,u) ppf =
  let x = Name.refresh penv.forbidden x in
  Print.print ppf "%t,@ %t"
    (print_xu ~penv x u)
    (print_v ~penv:(add_forbidden x penv))

let rec print_term ~penv ?max_level {term=e;assumptions;_} ppf =
  if !Config.print_dependencies && not (Assumption.is_empty assumptions)
  then
    Print.print ppf ?max_level ~at_level:3 "(%t)^{{%t}}"
                (print_term' ~penv ~max_level:3 e)
                (Assumption.print penv.forbidden assumptions)
  else
    print_term' ~penv ?max_level e ppf

and print_term' ~penv ?max_level e ppf =
  let print ?at_level = Print.print ?max_level ?at_level ppf in
    match e with
      | Type ->
        print ~at_level:0 "Type"

      | Atom x ->
        print ~at_level:0 "%t" (Name.print_atom x)

      | Constant x ->
        print ~at_level:0 "%t" (Name.print_ident x)

      | Bound k ->
        begin
          try
            if !Config.debruijn
            then print ~at_level:0 "%t[%d]" (Name.print_ident (List.nth penv.forbidden k)) k
            else print ~at_level:0 "%t" (Name.print_ident (List.nth penv.forbidden k))
          with
          | Not_found | Failure "nth" ->
              (** XXX this should never get printed *)
              print ~at_level:0 "DEBRUIJN[%d]" k
        end

      | Lambda a -> print ~at_level:3 "%t" (print_lambda penv a)

      | Apply (e, xtst, es) -> print ~at_level:1 "%t" (print_apply penv e xtst es)

      | Prod xts -> print ~at_level:3 "%t" (print_prod penv xts)

      | Eq (t, e1, e2) ->
        print ~at_level:2 "@[<hv 2>%t@ %s%t %t@]"
          (print_term ~penv ~max_level:1 e1)
          (Print.char_equal ())
          (print_annot (print_ty ~penv t))
          (print_term ~penv ~max_level:1 e2)

      | Refl (t, e) ->
        print ~at_level:1 "refl%t %t"
          (print_annot (print_ty ~penv t))
          (print_term ~penv ~max_level:0 e)

      | Signature s ->
        print ~at_level:0 "%t" (Name.print_ident s)

      | Structure (s, es) ->
         print_structure ~penv s es ppf

      | Projection (e, s, l) ->
         print ~at_level:0 "%t%t.%t"
               (print_term ~penv ~max_level:0 e)
               (print_annot (Name.print_ident s))
               (Name.print_ident l)

and print_ty ~penv ?max_level (Ty t) ppf = print_term ~penv ?max_level t ppf

(** [print_lambda a e t ppf] prints a lambda abstraction using formatter [ppf]. *)
and print_lambda penv (yus, (e, t)) ppf =
  Print.print ppf "@[<hov 2>%s %t@]"
    (Print.char_lambda ())
    (print_binders ~penv
      (print_binder1 (print_ty ~max_level:999))
      (fun ~penv ppf -> Print.print ppf "%t%t"
        (print_annot (print_ty ~penv t))
        (print_term ~penv e))
      yus)

(** [print_prod penv ts t ppf] prints a dependent product using formatter [ppf]. *)
and print_prod penv ((y,u),t) ppf =
  if occurs_ty 0 t > 0
  then
    Print.print ppf "@[<hov 2>%s %t@]"
      (Print.char_prod ())
      (print_binders ~penv
        (print_binder1 (print_ty ~max_level:999))
        (fun ~penv -> print_ty ~penv t)
        (y,u))
  else
    Print.print ppf "@[<hov 2>%t@ %s@ %t@]"
          (print_ty ~penv ~max_level:2 u)
          (Print.char_arrow ())
          (print_ty ~penv:(add_forbidden Name.anonymous penv) t)

and print_apply penv e1 (yts, u) e2 ppf =
  let rec collect_args es e =
    match e.term with
    | Apply (e, _, e') -> collect_args (e' :: es) e
    | (Type | Atom _ | Bound _ | Constant _ | Lambda _
    | Prod _ | Eq _ | Refl _ | Signature _ | Structure _ | Projection _) ->
       e, es
  in
  let e, es = collect_args [e2] e1 in
  Print.print ppf "@[<hov 2>%t@ %t@]"
              (print_term ~penv ~max_level:0 e)
              (Print.sequence (print_term ~penv ~max_level:0) "" es)

and print_signature_clause penv x y t ppf =
  if Name.eq_ident x y then
    Print.print ppf "@[<h>%t :@ %t@]"
      (Name.print_ident x)
      (print_ty ~penv t)
  else
    Print.print ppf "@[<h>%t as %t :@ %t@]"
      (Name.print_ident x)
      (Name.print_ident y)
      (print_ty ~penv t)

and print_signature ~penv xts ppf =
  match xts with
  | [] -> ()
  | [x,y,t] ->
     let y = Name.refresh penv.forbidden y in
     print_signature_clause penv x y t ppf
  | (x,y,t) :: lst ->
     let y = Name.refresh penv.forbidden y in
     Print.print ppf "%t,@ %t"
        (print_signature_clause penv x y t)
        (print_signature ~penv:(add_forbidden y penv) lst)

and print_structure_clause ~penv (l,e) ppf =
  Print.print ppf "@[<h>%t@ =@ %t@]"
              (Name.print_ident l)
              (print_term ~penv e)

and print_structure ~penv s es ppf =
  let les = List.combine (penv.sigs s) es in
  Print.print ppf "{@[<hv>%t@]}"
       (Print.sequence (print_structure_clause ~penv) "," les)

(****** Structure stuff ********)

let field_value ~loc s_def lst l =
  match Name.index_of_ident l (List.map (fun (l, _, _) -> l) s_def) with
  | Some n ->
     begin
       try
         List.nth lst n
       with Failure _ -> Error.impossible ~loc "Tt.field_value: too few fields"
     end
  | None -> Error.impossible ~loc "Tt.field_value: field %t not found"
                             (Name.print_ident l)
                             (* XXX print signature as well? *)

let field_type ~loc s s_def e p =
  let rec fold vs = function
    | [] -> Error.impossible ~loc "field_type no such field %t" (Name.print_ident p)
    | (l,x,t)::rem ->
      if Name.eq_ident p l
      then instantiate_ty vs t
      else
        let el = mk_projection ~loc e s l in
        fold (el::vs) rem
    in
  fold [] s_def

