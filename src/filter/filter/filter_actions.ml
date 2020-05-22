(************************* MIT License HEADER ************************************
    Copyright ANSSI (2013-2015)
    Contributors : Ryad BENADJILA [ryadbenadjila@gmail.com],
    Thomas CALDERON [calderon.thomas@gmail.com]
    Marion DAUBIGNARD [marion.daubignard@ssi.gouv.fr]

    This software is a computer program whose purpose is to implement
    a PKCS#11 proxy as well as a PKCS#11 filter with security features
    in mind. The project source tree is subdivided in six parts.
    There are five main parts:
      1] OCaml/C PKCS#11 bindings (using OCaml IDL).
      2] XDR RPC generators (to be used with ocamlrpcgen and/or rpcgen).
      3] A PKCS#11 RPC server (daemon) in OCaml using a Netplex RPC basis.
      4] A PKCS#11 filtering module used as a backend to the RPC server.
      5] A PKCS#11 client module that comes as a dynamic library offering
         the PKCS#11 API to the software.
    There is one "optional" part:
      6] Tests in C and OCaml to be used with client module 5] or with the
         bindings 1]

    Here is a big picture of how the PKCS#11 proxy works:

 ----------------------   --------  socket (TCP or Unix)  --------------------
| 3] PKCS#11 RPC server|-|2] RPC  |<+++++++++++++++++++> | 5] Client library  |
 ----------------------  |  Layer | [SSL/TLS optional]   |  --------          |
           |              --------                       | |2] RPC  | PKCS#11 |
 ----------------------                                  | |  Layer |functions|
| 4] PKCS#11 filter    |                                 |  --------          |
 ----------------------                                   --------------------
           |                                                        |
 ----------------------                                             |
| 1] PKCS#11 OCaml     |                                  { PKCS#11 INTERFACE }
|       bindings       |                                            |
 ----------------------                                       APPLICATION
           |
           |
 { PKCS#11 INTERFACE }
           |
 REAL PKCS#11 MIDDLEWARE
    (shared library)

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.

    Except as contained in this notice, the name(s) of the above copyright holders
    shall not be used in advertising or otherwise to promote the sale, use or other
    dealings in this Software without prior written authorization.

    The current source code is part of the PKCS#11 filter 4] source tree:

           |
 ----------------------
| 4] PKCS#11 filter    |
 ----------------------
           |

    Project: PKCS#11 Filtering Proxy
    File:    src/filter/filter/filter_actions.ml

************************** MIT License HEADER ***********************************)
(* The following file can be seen as a "plugins" extension    *)
(* to the fiter rules. All the actions described here after   *)
(* can be called from within the filter engine BEFORE any     *)
(* filtering rule is applied: in that sense, actions can be   *)
(* seen as a full extension and/or replacement of the genuine *)
(* rules that are already offered by the filter. See the      *)
(* documentation for more details on how to add new actions   *)
(* and how they interact with the filter engine.              *)  

open Config_file
open Filter_common

(* WARNING: marshalling is type unsafe: care must be taken *)
(* when defining custom actions!                           *)
(* In any case, if the serialize or deserialize fail, we   *)
(* force a container exit!                                 *)
let serialize x = try Marshal.to_string x [] with _ -> print_error "MARSHALLING ERROR when serializing! Check your custom functions! KILLING the container ..."; exit 0
let deserialize x = try Marshal.from_string x 0 with _ -> print_error "MARSHALLING ERROR when deserializing! Check your custom functions! KILLING the container ..."; exit 0


(********* CUSTOM actions ******)
let c_Initialize_hook fun_name _ = 
  let s = Printf.sprintf " ########## Hooking %s!" fun_name in
  print_debug s 1; 
  let return_value = serialize (false, ()) in
  (return_value)

let c_Login_hook fun_name arg = 
  let (cksessionhandlet_, ckusertypet_, pin) = (deserialize arg) in
  if compare (Pkcs11.char_array_to_string pin) "1234" = 0 then
    (* Passtrhough if pin is 1234 *)
    let s = Printf.sprintf " ######### Passthrough %s with pin %s!" fun_name (Pkcs11.char_array_to_string pin) in
    print_debug s 1;
    (serialize (false, ()))
  else
  begin
    (* Hook the call if pin != 1234 *)
    let s = Printf.sprintf " ######### Hooking %s with pin %s!" fun_name (Pkcs11.char_array_to_string pin) in
    print_debug s 1;
    let return_value = serialize (true, Pkcs11.cKR_PIN_LOCKED) in
    (return_value)
  end

let identity fun_name _ = 
  let s = Printf.sprintf " ######### Identity hook called for %s!" fun_name in
  print_debug s 1;
  let return_value = serialize (false, ()) in
  (return_value)


(*** Common helpers for the patches *****)
INCLUDE "filter_actions_helpers/helpers_patch.ml"

(***********************************************************************)
(***** CryptokiX patches as user defined actions ******)

(***********************************************************************)
(* The patch preventing directly reading sensitive or extractable keys *)
(* see http://secgroup.dais.unive.it/projects/security-apis/cryptokix/ *)
INCLUDE "p11fix_patches/sensitive_leak_patch.ml"

(***********************************************************************)
(* We sanitize the creation templates to avoid default values          *)
(* Default attributes we want to apply when not defined by a creation template *)
INCLUDE "p11fix_patches/sanitize_creation_templates_patch.ml"

(***********************************************************************)
(* The conflicting attributes patch:                                   *)
(* see http://secgroup.dais.unive.it/projects/security-apis/cryptokix/ *)
INCLUDE "p11fix_patches/conflicting_attributes_patch.ml"


(***********************************************************************)
(* The sticky attributes patch:                                        *)
(* see http://secgroup.dais.unive.it/projects/security-apis/cryptokix/ *)
INCLUDE "p11fix_patches/sticky_attributes_patch.ml"


(***********************************************************************)
(* The wrapping format patch:                                          *)
(* see http://secgroup.dais.unive.it/projects/security-apis/cryptokix/ *)
INCLUDE "p11fix_patches/wrapping_format_patch.ml"

(***********************************************************************)
(* The local and non local objects patch:                              *)
INCLUDE "p11fix_patches/non_local_objects_patch.ml"

(***********************************************************************)
(* The secure templates patch:                                         *)
(* see http://secgroup.dais.unive.it/projects/security-apis/cryptokix/ *)
INCLUDE "p11fix_patches/secure_templates_patch.ml"

(***********************************************************************)
(* The existing sensitive keys patch:                                  *)
INCLUDE "p11fix_patches/existing_sensitive_keys_patch.ml"


(***********************************************************************)
(********* CUSTOM actions wrappers for the configuration file ******)
let execute_action fun_name action argument = match action with
  "c_Initialize_hook" -> c_Initialize_hook fun_name argument
| "c_Login_hook" -> c_Login_hook fun_name argument
| "identity" -> identity fun_name argument
| "conflicting_attributes_patch" -> conflicting_attributes_patch fun_name argument
| "conflicting_attributes_patch_on_existing_objects" -> conflicting_attributes_patch_on_existing_objects fun_name argument
| "sticky_attributes_patch" -> sticky_attributes_patch fun_name argument
| "sanitize_creation_templates_patch" -> sanitize_creation_templates_patch fun_name argument
| "prevent_sensitive_leak_patch" -> prevent_sensitive_leak_patch fun_name argument
| "wrapping_format_patch" -> wrapping_format_patch fun_name argument
| "non_local_objects_patch" -> non_local_objects_patch fun_name argument
| "do_segregate_usage" -> do_segregate_usage fun_name argument
| "secure_templates_patch" -> secure_templates_patch fun_name argument
| "dangerous_sensitive_keys_paranoid" -> dangerous_sensitive_keys_paranoid fun_name argument
| "dangerous_sensitive_keys_escrow_encrypt" -> dangerous_sensitive_keys_escrow_encrypt fun_name argument
| "dangerous_sensitive_keys_escrow_all" -> dangerous_sensitive_keys_escrow_all fun_name argument
| _ -> identity fun_name argument

let string_check_action a = match a with
  "c_Initialize_hook" -> a
| "c_Login_hook" -> a
| "identity" -> a
| "conflicting_attributes_patch" -> a
| "conflicting_attributes_patch_on_existing_objects" -> a
| "sticky_attributes_patch" -> a
| "sanitize_creation_templates_patch" -> a
| "prevent_sensitive_leak_patch" -> a
| "wrapping_format_patch" -> a
| "non_local_objects_patch" -> a
| "do_segregate_usage" -> a
| "secure_templates_patch" -> a
| "dangerous_sensitive_keys_paranoid" -> a
| "dangerous_sensitive_keys_escrow_encrypt" -> a
| "dangerous_sensitive_keys_escrow_all" -> a
| _ -> let error_string = Printf.sprintf "Error: unknown action option '%s'!" a in netplex_log_critical error_string; raise Config_file_wrong_type


(* Wrapper for actions defined in the plugin *)
let actions_wrappers = {
  to_raw = (fun input -> Config_file.Raw.String input);
  of_raw = function
    | Config_file.Raw.String input -> string_check_action input
    | _ -> netplex_log_critical "Error: got wrong action type!"; raise Config_file_wrong_type
}
