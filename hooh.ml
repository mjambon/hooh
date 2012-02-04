open Printf

let ( // ) = Filename.concat

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

type param = {
  confname : string;
  workdir : string;
  gitdir : string;
  tgzdir : string;
}  

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
  cd p.gitdir (
    fun () ->
      run (sprintf "git clone %s %s" (q url) (q pkg));
      run (sprintf "cd %s && git tag -l > %s/tags" (q pkg) (q p.gitdir));
      let tags = filter_version_tags (load_lines (p.gitdir // "tags")) in
      run (sprintf "rm tags");
      create_dir (p.tgzdir // pkg);
      List.iter (
        fun (tag, version) ->
          run (sprintf "cd %s && git checkout %s" (q pkg) (q tag));
          run (sprintf "mv %s/.git dotgit" (q pkg));
          run (sprintf "tar czf %s-%s.tar.gz %s" (q pkg) (q version) (q pkg));
          let pkg_dir = p.tgzdir // pkg in
          run (sprintf "mv %s-%s.tar.gz %s"
                 (q pkg) (q version) (q pkg_dir));
          let base = sprintf "%s/%s-%s" (q pkg_dir) (q pkg) (q version) in
          run (sprintf "md5sum -b %s.tar.gz | cut -f1 -d' ' > %s.md5"
                 base base);
          run (sprintf "mv dotgit %s/.git" (q pkg));
      ) tags;
      run (sprintf "rm -rf %s" (q pkg));
  )

let make_absolute path =
  if Filename.is_relative path then
    Sys.getcwd () // path
  else
    path

let main () =
  let workdir = make_absolute "hooh.work" in
  let param = {
    confname = make_absolute "hooh.conf";
    workdir;
    gitdir = workdir // "git";
    tgzdir = workdir // "tgz"
  }
  in
  create_dir workdir;
  create_dir param.gitdir;
  create_dir param.tgzdir;
  let config = load_config param.confname in
  List.iter (update_package param) config

let () = main ()
