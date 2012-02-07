open Printf

let ( // ) = Filename.concat

type param = {
  conf_file : string;
  tmp_dir : string;
  dst_dir : string;
}  

let q s =
  let buf = Buffer.create (2 * String.length s) in
  Buffer.add_char buf '\'';
  String.iter (
    function
        '\'' -> Buffer.add_string buf "'\\''"
      | c -> Buffer.add_char buf c
  ) s;
  Buffer.add_char buf '\'';
  Buffer.contents buf

let load_lines fname =
  let ic = open_in fname in
  let l = ref [] in
  try
    while true do
      l := input_line ic :: !l
    done;
    assert false
  with End_of_file ->
    close_in ic;
    List.rev !l

let comment = Pcre.regexp "^[\\t ]*#"
let sep = Pcre.regexp "[\\t ]+"

let parse_line s =
  if Pcre.pmatch ~rex:comment s then []
  else
    match Pcre.split ~rex:sep s with
        [ pkg; url ]
      | [ ""; pkg; url; ]
      | [ pkg; url; ""]
      | [ ""; pkg; url; "" ] -> [ (pkg, url) ]
      | _ ->
          eprintf "Bad config line:\n%S\n%!" s;
          exit 1

let load_config fname =
  let l = load_lines fname in
  List.flatten (List.map parse_line l)

let create_dir s =
  if not (Sys.file_exists s) then
    Unix.mkdir s 0o777

let chdir s =
  eprintf "cd %s\n%!" s;
  Sys.chdir s

let cd dir f =
  let dir0 = Sys.getcwd () in
  chdir dir;
  try f (); chdir dir0
  with e -> chdir dir0; raise e

let run cmd =
  eprintf "%s\n%!" cmd;
  match Sys.command cmd with
      0 -> ()
    | n ->
        eprintf "Command exited with status %i\n" n;
        exit 1

let version_rex = Pcre.regexp "^[vV][0-9][^ \\t]*$"

let filter_version_tags l =
  let l = 
    List.map (
      fun s ->
        if Pcre.pmatch ~rex:version_rex s then
          [ (s, String.sub s 1 (String.length s - 1)) ]
        else
          []
    ) l
  in
  List.flatten l

let update_package p (pkg, url) =
  let gitdir = p.tmp_dir in
  let tgzdir = p.dst_dir in
  cd p.tmp_dir (
    fun () ->
      run (sprintf "git clone %s %s" (q url) (q pkg));
      run (sprintf "cd %s && git tag -l > %s/tags" (q pkg) (q gitdir));
      let tags = filter_version_tags (load_lines (gitdir // "tags")) in
      run (sprintf "rm tags");
      let pkg_dir = tgzdir // pkg in
      create_dir pkg_dir;
      List.iter (
        fun (tag, version) ->
          let base = sprintf "%s/%s-%s" (q pkg_dir) (q pkg) (q version) in
          run (sprintf
                 "cd %s && \
                  git archive --format=tar --prefix=%s-%s/ \
                  %s \
                    > %s.tar; \
                  gzip -nf %s.tar"
                 (q pkg)
                 (q pkg) (q version)
                 (q tag)
                 base
                 base);
          run (sprintf "md5sum -b %s.tar.gz | cut -f1 -d' ' > %s.md5"
                 base base);
      ) tags;
      run (sprintf "rm -rf %s" (q pkg));
  )

let make_absolute path =
  if Filename.is_relative path then
    Sys.getcwd () // path
  else
    path

let random_bits =
  let state = Random.State.make_self_init () in
  fun () -> Random.State.bits state

let rec make_tmpdir () =
  let dir = Filename.temp_dir_name // sprintf "hooh-%08x" (random_bits ()) in
  Unix.mkdir dir 0o700;
  dir

let with_tmpdir f =
  let tmp_dir = make_absolute (make_tmpdir ()) in
  try
    let x = f tmp_dir in
    Unix.rmdir tmp_dir;
    x
  with e ->
    (try Unix.rmdir tmp_dir
     with _ ->
       eprintf "*** Temporary directory %s needs to be removed manually.\n%!"
         tmp_dir);
    raise e

let main () =
  let conf = ref "releases.conf" in
  let dst = ref "releases" in
  let options = [
    "-conf", Arg.Set_string conf,
    "<config file>
          Configuration file name (default: releases.conf)";
    
    "-dst", Arg.Set_string dst,
    "<destination directory>
          Destination directory for the .tar.gz and .md5 files
          (default: releases)";
  ]
  in
  let err_msg = sprintf "\
Usage: %s [options]
Options:"
    Sys.argv.(0)
  in
  let anon_fun s =
    eprintf "Don't what to do with %s\n%!" s;
    Arg.usage options err_msg;
    exit 1
  in
  Arg.parse options anon_fun err_msg;

  let conf_file = make_absolute !conf in
  let dst_dir = make_absolute !dst in

  with_tmpdir (
    fun tmp_dir ->
      let param = {
        conf_file;
        tmp_dir;
        dst_dir;
      }
      in
      create_dir param.dst_dir;
      let config = load_config param.conf_file in
      List.iter (update_package param) config
  )

let () = main ()
