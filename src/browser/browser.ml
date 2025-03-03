(* This module handles all calls to javascript

*)

open Fmlib_js
open Fmlib_js.Dom




(* Basic definitions
   ============================================================
*)



type element             = Element.t * Handler.EventHs.t

type node                = Node.t * element option

type 'msg dom            = ('msg, node) Vdom.t1

type 'msg dom_operations = ('msg, node) Vdom.operations


let document (): Document.t = Window.(get () |> document)

type ('state, 'msg) view1 = 'state -> 'msg Vdom.t
type ('state, 'msg) view2 = 'state -> 'msg Vdom.t * string

type ('state, 'msg) update1 = 'state -> 'msg -> 'state
type ('state, 'msg) update2 = 'state -> 'msg -> 'state * 'msg Command.t



type ('s, 'm) operations =
    | Sandbox of
          ('s, 'm) view1
          * ('s -> 'm Subscription.t)
          * ('s, 'm) update1
    | Element of
          ('s, 'm) view1
          * ('s -> 'm Subscription.t)
          * ('s, 'm) update2
          * (Base.Value.t -> unit)
    | App     of
          ('s, 'm) view2
          * ('s -> 'm Subscription.t)
          * ('s, 'm) update2
          * (Base.Value.t -> unit)



type ('state, 'msg) data =
    {
        mutable state: 'state;
        mutable dirty: bool;
        mutable dom:   'msg dom option;
        mutable subs:  'msg Subscriptions.t option;
        root:          Element.t;
        operations:    ('state, 'msg) operations;
    }





(* Dom operations
   ============================================================

   Accessing the real dom.

   Operations are needed for the module [Vdom].
*)


let dom_operations (dispatch: 'msg -> unit): 'msg dom_operations =
    let get_both:
        node -> element
        =
        function
        | (_, Some el) ->
          el
        | _ ->
            assert false (* Illegal call *)
    in
    let get_element:
        Node.t * element option -> Element.t
        =
        function
        | (_, Some (el, _)) ->
          el
        | _ ->
            assert false (* Illegal call *)
    in
    {
        make_text =
            (fun s -> Document.create_text_node s (document ()), None);

        make_element =
            (fun tag (lst: node list) ->
                 let open Document in
                 let open Element in
                 let open Node in
                 let doc = document () in
                 let el  = create_element tag doc in
                 List.iter
                     (fun (child, _) ->
                          append child (node el))
                     lst;
                 node el, Some (el, Handler.EventHs.empty ()));

        make_element_ns =
            (fun namespace tag (lst: node list) ->
                 let open Document in
                 let open Element in
                 let open Node in
                 let doc = document () in
                 let el  = create_element_ns namespace tag doc in
                 List.iter
                     (fun (child, _) ->
                          append child (node el))
                     lst;
                 node el, Some (el, Handler.EventHs.empty ()));

        add_child =
            (fun (child, _) (par, _) ->
                 Node.append child par);

        remove_child =
            (fun (child, _) (par, _) ->
                 Node.remove child par);

        remove_children =
            (fun (par, _) ->
                 Node.remove_children par);

        replace_child =
            (fun (old_child, _) (new_child, _) (par, _) ->
                 Node.replace new_child old_child par);

        set_style =
            (fun el key value ->
                Style.set key value (Element.style (get_element el)));

        set_attribute =
            (fun el key value ->
                 Element.set_attribute key value (get_element el));

        set_property =
            (fun el key value ->
                 Element.set_property key value (get_element el));


        remove_style =
            (fun el key ->
                 Style.remove
                     key
                     (Element.style (get_element el)));


        remove_attribute =
            (fun el key ->
                 Element.remove_attribute key (get_element el));


        remove_property =
            (fun el key ->
                 Element.delete_property key (get_element el));


        set_handlers =
            (fun el dict ->
                 let el, reals = get_both el in
                 let target = Node.event_target (Element.node el) in
                 Handler.EventHs.set target dispatch dict reals
            );

        update_handlers =
            (fun el dict1 dict2 ->
                 let el, reals = get_both el in
                 let target = Node.event_target (Element.node el) in
                 Handler.EventHs.update target dispatch dict1 dict2 reals);
    }





(* Dispatching messages to the application
   ============================================================

   - call the update function

        state -> msg -> state * cmd

   - update the subscriptions

        state might have changed, therefore subscriptions might have changed.

   - execute commands

*)

let rec dispatch (data: ('state, 'msg) data) (msg: 'msg): unit =
    let update_data state =
        let state_different = not (state == data.state)
        in
        data.dirty <- data.dirty || state_different;
        if state_different then begin
            data.state <- state;
            update_subscriptions data
        end
    in
    match data.operations with
    | Sandbox (_, _, update) ->
        update_data (update data.state msg);

    | Element (_, _, update, post) ->
        let state, cmd = update data.state msg in
        update_data state;
        Command.execute post (dispatch_next data) cmd

    | App (_, _, update, post) ->
        let state, cmd = update data.state msg in
        update_data state;
        Command.execute post (dispatch_next data) cmd


and dispatch_next (data: ('state, 'msg) data) (msg: 'msg): unit =
    ignore ( Timer.set (fun () -> dispatch data msg) 0 )


and update_subscriptions (data: ('s, 'm) data): unit =
    (* create or update the subscriptions, i.e. install all necessary handlers. *)
    let update () =
        match data.operations, data.subs with
        | Sandbox (_, sub, _),    None
        | App (_, sub, _, _),     None
        | Element (_, sub, _, _), None ->
            data.subs <-
                Some (Subscriptions.make (dispatch data) (sub data.state))

        | Sandbox (_, sub, _),    Some subs
        | App (_, sub, _, _),     Some subs
        | Element (_, sub, _, _), Some subs
            when data.dirty ->
            data.subs <-
                Some (Subscriptions.update (dispatch data) (sub data.state) subs)

        | _, _ ->
            ()
    in
    Assert_failure.attempt
        "Exception in 'update_subscriptions' of Fmlib_browser"
        update
        (fun () -> ())










(* Produce the real dom i.e. render the dom
   ============================================================

   This is there the access to the real dom of the browser happens.
*)


let put_below_root (data: ('state, 'msg) data) (dom: 'msg dom): unit =
    let root_node = Element.node data.root in
    Node.remove_children root_node;
    Node.append (Vdom.element dom |> fst) root_node





let vdom (data: ('s, 'm) data): 'm Vdom.t * (unit -> unit) =
    (* Get the virtual dom from the state and the title update function. *)
    match data.operations with
    | Sandbox (view, _, _) ->
        view data.state, (fun () -> ())
    | Element (view, _, _, _) ->
        view data.state, (fun () -> ())
    | App (view, _, _, _) ->
        let vdom, title = view data.state in
        vdom, (fun () -> Document.set_title title (document ()))




let update_dom (data: ('state, 'msg) data): unit =
    (* Create or update the real dom based on the state. First create a virtual
       dom from the state and then create or update the real dom. *)
    let update () =
        let vdom data =
            let vdom, set_title = vdom data in
            set_title ();
            vdom
        in
        match data.dom with
        | None ->
            let dom =
                Vdom.make
                    (dom_operations (dispatch data))
                    (vdom data)
            in
            data.dom <- Some dom;
            put_below_root data dom;

        | Some dom ->
            if data.dirty then begin
                let dom, created =
                    Vdom.update
                        (dom_operations (dispatch data))
                        (vdom data)
                        dom
                in
                if created then
                    put_below_root data dom;
                data.dom <- Some dom;
            end
    and cleanup () =
        data.dirty <- false
    in
    Assert_failure.attempt
        "Exception in 'update_dom' of Fmlib_browser"
        update
        cleanup;
    cleanup ();
    assert (not data.dirty)


let on_next_animation (f: float -> unit): unit =
    (* Call 'f' on next animation frame. *)
    Window.(on_next_animation f (get ()))



let rec animate (data: ('state, 'msg) data): float -> unit =
    fun _ ->
    update_dom data;
    assert (not data.dirty);
    on_next_animation (animate data)





(* Helper function to wrap user supplied functions
   ============================================================
 *)

let wrap_state_fun (str: string) (f: 's -> 'a) (state: 's): 'a =
    Assert_failure.attempt
        ("Exception in '" ^ str ^ "'")
        (fun () -> f state)
        (fun () -> ())


let wrap_view (view: 's -> 'a) (state: 's): 'a =
    wrap_state_fun "view" view state


let wrap_subscription (view: 's -> 'a) (state: 's): 'a =
    wrap_state_fun "subscriptioin" view state


let wrap_update (update: 's -> 'm -> 'a) (state: 's) (message: 'm): 'a =
    Assert_failure.attempt
        "Exception in 'update'"
        (fun () -> update state message)
        (fun () -> ())







(* Helper function to receive messages from javascript
   ============================================================
 *)

let receive_message
        (data: ('s, 'm) data option ref)
    : Base.Value.t
    =
    (* Handler for incoming messages from javascript. *)
    let open Base
    in
    let post (v: Value.t): Value.t =
        match !data with
        | None ->
            Main.log_string "receive_message: application not yet initialized";
            Value.null
        | Some data ->
            match data.subs with
            | None ->
                Main.log_string
                    "receive_message: subscriptions not yet initialized";
                Value.null
            | Some subs ->
                match subs.subs.message with
                | None ->
                    Main.log_string
                        "receive_message: event not subscribed";
                    Value.null
                | Some decode ->
                    match decode v with
                    | None ->
                        Main.log_string
                            "receive_message: cannot decode message from \
                             javascript";
                        Main.log_value v;
                        Value.null
                    | Some m ->
                        dispatch data m;
                        Value.null
    in
    Value.function1 post






(* Helper function to start an application (element or single page app)
   =======================================================================
 *)



let start_application
        (data: ('s, 'm) data)
        (command: 'm Command.t)
        (post: Base.Value.t -> unit): unit =
    update_subscriptions data;
    update_dom data;
    Command.execute post (dispatch_next data) command;
    on_next_animation (animate data)








(* Sandbox application
 * ============================================================
 *)

let make_sandbox
        (state: 's)
        (view:   ('s, 'm) view1)
        (sub:    'state -> 'msg Subscription.t)
        (update: ('s, 'm) update1)
        (_: 'a)
    : unit
    =
    (* This function is processed within the onload event of the browser
       window.
     *)

    (* Make the data for the application. *)
    let data = {
        state;
        dirty      = false;
        root       = Document.body (document ());
        dom        = None;
        subs       = None;
        operations =
            Sandbox (wrap_view view, wrap_subscription sub, wrap_update update)
    }
    in
    update_subscriptions data; (* Initial subscriptions *)
    update_dom data;           (* Initial dom. *)

    (* Processing for requestAnimationFrame *)
    on_next_animation (animate data)



let sandbox
        (state: 'state)
        (view: ('state, 'msg) view1)
        (update: ('state, 'msg) update1)
    : unit
    =
    Event_target.add
        "load"
        (make_sandbox state view (fun _ -> Subscription.none) update)
        Window.(event_target (get ()))



let sandbox_plus
        (state:  'state)
        (view:   ('state, 'msg) view1)
        (sub:    'state -> 'msg Subscription.t)
        (update: ('state, 'msg) update1)
    : unit
    =
    Event_target.add
        "load"
        (make_sandbox state view sub update)
        Window.(event_target (get ()))










(* Element application
 * ============================================================
 *)



let init_element
        (dataref: ('s, 'm) data option ref)
        (decode:  ('s * 'm Command.t) Base.Decode.t)
        (view:    ('s, 'm) view1)
        (sub:     's -> 'm Subscription.t)
        (update:  ('s, 'm) update2)
    : Base.Value.t
    =
    let open Base in
    let decode =
        let open Decode in
        let* post       = field "onMessage" _function in
        let* state, cmd = field "data" decode in
        let* element_id = field "element_id" string in
        return (element_id, state, cmd, fun v -> ignore (post [|v|]))
    in
    let init (v: Value.t): Value.t =
        match !dataref with
        | None -> begin
            match decode v with
            | None ->
                Main.log_string "cannot decode initialisation data";
                Main.log_value v;
                Value.null
            | Some (element_id, state, command, post) ->
                Event_target.add
                    "load"
                    (fun _ ->
                         match Dom.Document.find element_id (document ()) with
                         | None ->
                             Main.log_string
                                 ("Cannot find element " ^ element_id)
                         | Some root ->
                             let data = {
                                 state;
                                 dirty = false;
                                 root;
                                 dom   = None;
                                 subs  = None;
                                 operations =
                                     Element (
                                         wrap_view view,
                                         wrap_subscription sub,
                                         wrap_update update,
                                         post);
                             }
                             in
                             dataref := Some data;
                             start_application data command post
                    )
                    Window.(event_target (get ()));
                Value.null
        end
        | Some _ ->
            Main.log_string "application already initialized";
            Value.null
    in
    Value.function1 init




let element
        (name: string)
        (decode: ('s * 'm Command.t) Base.Decode.t)
        (view:   ('s, 'm) view1)
        (subs:   's -> 'm Subscription.t)
        (update: ('s, 'm) update2)
    : unit
    =
    let _ = decode, view, subs, update in
    let app = ref None in
    Base.Main.make_global
        name
        Base.Value.(
            _object
                [| "init", init_element app decode view subs update
                 ; "post", receive_message app
                |]
        )







(* Single Page Application
 * ============================================================
 *)





let init_application
        (dataref: ('s, 'm) data option ref)
        (decode:  ('s * 'm Command.t) Base.Decode.t)
        (view:    ('s, 'm) view2)
        (sub:     's -> 'm Subscription.t)
        (update:  ('s, 'm) update2)
    : Base.Value.t
    =
    let open Base in
    let decode =
        let open Decode in
        let* post       = field "onMessage" _function in
        let* state, cmd = field "data" decode in
        return (state, cmd, fun v -> ignore (post [|v|]))
    in
    let init (v: Value.t): Value.t =
        match !dataref with
        | None -> begin
            match decode v with
            | None ->
                Main.log_string "cannot decode initialisation data";
                Main.log_value v;
                Value.null
            | Some (state, command, post) ->
                Event_target.add
                    "load"
                    (fun _ ->
                         let data = {
                             state;
                             dirty = false;
                             root  = Document.body (document ());
                             dom   = None;
                             subs  = None;
                             operations =
                                 App (
                                     wrap_view view,
                                     wrap_subscription sub,
                                     wrap_update update,
                                     post);
                         }
                         in
                         dataref := Some data;
                         start_application data command post
                    )
                    Window.(event_target (get ()));
                Value.null
        end
        | Some _ ->
            Main.log_string "application already initialized";
            Value.null
    in
    Value.function1 init






let application
        (name: string)
        (decode: ('s * 'm Command.t) Base.Decode.t)
        (view:   ('s, 'm) view2)
        (subs:   's -> 'm Subscription.t)
        (update: ('s, 'm) update2)
    : unit
    =
    let app = ref None in
    Base.Main.make_global
        name
        Base.Value.(
            _object
                [| "init", init_application app decode view subs update
                 ; "post", receive_message app
                |]
        )






let basic_application
        (state:   's)
        (command: 'm Command.t)
        (view:    ('s, 'm) view2)
        (sub:     's -> 'm Subscription.t)
        (update:  ('s, 'm) update2)
    : unit
    =
    let post _ = ()
    in
    Event_target.add
        "load"
        (fun _ ->
             let data = {
                 state;
                 dirty = false;
                 root  = Document.body (document ());
                 dom   = None;
                 subs  = None;
                 operations =
                     App (
                         wrap_view view,
                         wrap_subscription sub,
                         wrap_update update,
                         post);
             }
             in
             start_application data command post
        )
        Window.(event_target (get ()));
