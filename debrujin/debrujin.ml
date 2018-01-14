type name = string

let eq_name n1 n2 = (n1 = n2)

type ty =
  | K of name
  | Arrow of ty * ty

let gen_type =
  let v = ref 0 in
  incr v;
  K(string_of_int !v)

let rec eq_typ t1 t2 =
  match t1, t2 with
  | K(n1), K(n2) -> eq_name n1 n2
  | Arrow(ty11, ty12), Arrow(ty21, ty22) ->
    eq_typ ty11 ty21 && eq_typ ty12 ty22
  | _ -> false

type context = ty list

let get_type_c i c = List.nth c (i-1)

type term =
  | Var  of int
  | XVar of name
  | Abs  of ty * term
  | App  of term * term

let rec height (t : term) (n : int) =
  match t with
  | Var(_) -> n
  | XVar(_) -> n
  | Abs(ty, t) -> height t (n+1)
  | App(t1, t2) -> max (height t1 n) (height t2 n)

let rec lift (t : term) (i : int) =
  match t with
  | Var(n) -> if n > i then Var(n+1) else t
  | XVar(_) -> t
  | Abs(ty, t) -> Abs(ty, lift t (i+1))
  | App(t1, t2) -> App((lift t1 i), (lift t2 i))

let lift_plus (t : term) = lift t 0

let rec subst (a: term) (b: term) (n: int) =
  match a with
  | Var(m) -> if m > n then Var(n-1)
    else (if n = m then b else Var(m))
  | XVar(_) -> a
  | Abs(ty, t1) -> Abs(ty, subst t1 (lift_plus b) (n+1))
  | App(t1, t2) -> App((subst t1 b n), (subst t2 b n))

let beta_red (t: term) =
  match t with
  | App(Abs(ty, a), b) -> subst a b 1
  | _ -> t

let rec free_var (t : term) (i : int) =
  match t with
  | Var(m) -> if m > i then 1 else 0
  | XVar(_) -> 0
  | Abs(ty, t1) -> free_var t1 (i+1)
  | App(t1, t2) -> (free_var t1 i) + (free_var t2 i)

(*------------------------------ lsgima --------------------------------*)

type s_subst =
  (*| Yvar of name *)
  | Id
  | Shift
  | Cons of s_term * s_subst
  | Comp of s_subst * s_subst
and s_term =
  | S_One
  | S_Xvar of name
  | S_App of s_term * s_term
  | S_Abs of ty * s_term
  | S_Tsub of s_term * s_subst

let rec s_shift_n (n : int) =
  match n with
  | 0 -> Id
  | 1 -> Shift
  | n -> Comp(Shift, s_shift_n (n-1))

let rec precooking (l_t : term) (n : int) : s_term =
  match l_t with
  | Var(k) -> S_Tsub (S_One, s_shift_n (k-1)) (* Var k *)
  | XVar(nam) -> S_Tsub (S_Xvar(nam), s_shift_n (n))
  | Abs(ty, t1) -> S_Abs(ty, precooking t1 (n+1))
  | App(t1, t2) -> S_App((precooking t1 n), (precooking t2 n))



(* -------------------- reduction Hugo-style ------------------ *)

let app_red (t: s_term) =
  match t with
  | S_Tsub (S_App(a,b), s) -> S_App(S_Tsub(a,s), S_Tsub (b,s))
  | _ -> t

let varcons_red (t: s_term) =
  match t with
  | S_Tsub (S_One, Cons(a,b)) -> a
  | _ -> t

let id_red (t: s_term) =
  match t with
  | S_Tsub (a, Id) -> a
  | _ -> t

let abs_red (t: s_term) =
  match t with
  | S_Tsub (S_Abs(ty, a), s) -> S_Abs(ty, S_Tsub(a, Cons(S_One, Comp(s, Shift))))
  | _ -> t

let clos_red (t: s_term) =
  match t with
  | S_Tsub(S_Tsub(a,s),t) -> S_Tsub(a, Comp(s,t))
  | _ -> t

let idl_red (s: s_subst) =
  match s with
  | Comp(Id, s1) -> s1
  | _ -> s

let shiftcons_red (s: s_subst) =
  match s with
  | Comp(Shift, Cons(a,s1)) -> s1
  | _ -> s

let assenv_red (s: s_subst) =
  match s with
  | Comp(Comp(s1, s2), s3) -> Comp(s1, Comp(s2,s3))
  | _ -> s

let mapenv_red (s: s_subst) =
  match s with
  | Comp(Cons(a,s1),t) -> Cons(S_Tsub(a,t), Comp(s1,t))
  | _ -> s

let idr_red (s: s_subst) =
  match s with
  | Comp(s1, Id) -> s1
  | _ -> s

let varshift_red (s: s_subst) =
  match s with
  | Cons(S_One, Shift) -> Id
  | _ -> s

let scons_red (s: s_subst) =
  match s with
  | Cons(S_Tsub(S_One, s1), Comp(Shift, s2)) -> if s1 = s2 then s1 else s
  | _ -> s

exception No_inference

let rec type_check_inf c t_term =
  match t_term with
  | S_One -> get_type_c 1 c
  | S_Xvar(n) -> K(n)               (* TODO : Not really sure about this one, should be an unique type Tx AND an unique context Cx, cf. dowek1 p18*)
  | S_Abs(ty_abs, te_abs) ->
    type_check_inf (ty_abs::c) te_abs
  | S_App(a, b) -> let ty_A = type_check_inf c b in
    let ty_arr = type_check_inf c a in
    (match ty_arr with
     | Arrow(ty_A2, ty_B) -> if eq_typ ty_A ty_A2 then ty_B else raise No_inference
     | _ -> raise No_inference)
  | S_Tsub(t, s) -> let c_s = type_check_cont c s in
    type_check_inf c_s t 
and type_check_cont c t_sub =
  match t_sub with
  (*| Yvar(n)      -> *)            (* TODO : Do not remember why this variant was added. Removed for the moment *)
  | Id           -> c
  | Shift        -> (match c with
      | []     -> raise No_inference
      | hd::tl -> tl)
  | Cons(t, s)   -> let c_s = type_check_cont c s in
    let ty_t = type_check_inf c t in
    ty_t::c_s
  | Comp(s1, s2) -> let c_s2 = type_check_cont c s2 in
    type_check_cont c_s2 s1 