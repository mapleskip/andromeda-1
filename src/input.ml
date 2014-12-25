(** The abstract syntax of input as typed by the user. At this stage
    there is no distinction between computations, expressions, and types.
    However, we define type aliases for these for better readability.
    There are no de Bruijn indices either.
*)

type term = term' * Position.t
and term' =
  (* expressions *)
  | Var of Common.name
  | Type
  (* computations *)
  | Let of Common.name * comp * comp
  | Ascribe of comp * ty
  | Lambda of (Common.name * ty) list * comp
  | Spine of expr * expr list
  | Prod of (Common.name * ty) list * ty
  | Eq of expr * expr
  | Refl of expr

and ty = term
and comp = term
and expr = term

(** Toplevel commands *)
type toplevel = toplevel' * Position.t
and toplevel' =
  | Parameter of Common.name list * ty (** introduce parameters into the context *)
  | TopLet of Common.name * comp (** global let binding *)
  | TopCheck of comp (** infer the type of a computation *)
  | Quit
  | Help
  | Context

