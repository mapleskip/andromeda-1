(* Even though there might be JSON libraries for OCaml, we implement our own
   because there really is not that much work to do, and not depending
   on a bunch of external libraries can be a Good Thing.
 *)


(** A simplified type for representing JSON values *)
type t =
  | String of string
  | Int of int
  | List of t list
  | Dict of (t * t) list

let tuple lst = List lst

let record lst =
  let lst = List.map (fun (key, value) -> (String key, value)) lst in
  Dict lst

let tag tag data = tuple ((String tag) :: data)

let rec print data ppf =
  match data with

  | String s -> Format.fprintf ppf "\"%s\"" (String.escaped s)

  | Int k -> Format.fprintf ppf "%d" k

  | List lst -> Format.fprintf ppf "[@[<hov>%t@]]" (Print.sequence print "," lst)

  | Dict lst ->
     Format.fprintf ppf "{@[<hv>%t@]}" (Print.sequence print_entry "," lst)

and print_entry (label, data) ppf =
  Format.fprintf ppf "@[<hv>%t :@ %t@]"
                 (print label)
                 (print data)
