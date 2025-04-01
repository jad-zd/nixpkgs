{
  lib,
  stdenv,
  fetchurl,
  writeText,
  graphviz,
  doxygen,
  ocamlPackages,
  ltl2ba,
  coq,
  why3,
  gdk-pixbuf,
  wrapGAppsHook3,

  yarn,
  nodejs_22,
  fetchYarnDeps,
  fixup-yarn-lock,
  makeWrapper,
  headache,
  electron,
}:

let
  mkocamlpath = p: "${p}/lib/ocaml/${ocamlPackages.ocaml.version}/site-lib";
  runtimeDeps = with ocamlPackages; [
    apron.dev
    bigarray-compat
    biniou
    camlzip
    easy-format
    menhirLib
    mlgmpidl
    num
    ocamlgraph
    ppx_deriving
    ppx_deriving_yojson
    ppx_import
    stdlib-shims
    why3.dev
    re
    result
    seq
    sexplib
    sexplib0
    parsexp
    base
    unionFind
    yojson
    zarith
  ];
  ocamlpath = lib.concatMapStringsSep ":" mkocamlpath runtimeDeps;
in

stdenv.mkDerivation rec {
  pname = "frama-c";
  version = "30.0";
  slang = "Zinc";

  src = fetchurl {
    url = "https://frama-c.com/download/frama-c-${version}-${slang}.tar.gz";
    hash = "sha256-OsD5lSYeyCmnvQQr9w/CmsY3kCnrnfMLzARHSOtNKlY=";
  };

  yarnOfflineCache = fetchYarnDeps {
    yarnLock = "ivette/yarn.lock";
    hash = "sha256-uRqexHP2b6fZCSksr/muz94SKA6M9FZnNvW4jWs4y6Q=";
  };

  preConfigure = ''
    substituteInPlace src/dune --replace-warn " bytes " " "
  '';

  postConfigure = "patchShebangs ivette/api.sh";

  strictDeps = true;

  nativeBuildInputs =
    [ wrapGAppsHook3 ]
    ++ (with ocamlPackages; [
      ocaml
      findlib
      dune_3
      menhir
    ])
    ++ [
      yarn
      nodejs_22
      fixup-yarn-lock
      makeWrapper
      headache
    ];

  buildInputs = with ocamlPackages; [
    dune-site
    dune-configurator
    ocamlgraph
    yojson
    menhirLib
    lablgtk3
    lablgtk3-sourceview3
    coq
    graphviz
    zarith
    apron
    why3
    mlgmpidl
    doxygen
    ppx_deriving
    ppx_deriving_yaml
    ppx_deriving_yojson
    gdk-pixbuf
    unionFind
  ];

  buildPhase = ''
    runHook preBuild

    export HOME=$(mktemp -d)
    (
    cd ivette;
    yarn config --offline set yarn-offline-mirror "$yarnOfflineCache";
    fixup-yarn-lock yarn.lock;
    # ERROR AS YARN TRIES TO FETCH A FILE WITH A DIFFERENT NAME, NAMELY: IT TRIES TO GET https___registry.npmjs.org_tslib___tslib_2.6.2.tgz but the file name is tslib___tslib_2.6.2.tgz
    yarn --offline --frozen-lockfile --ignore-platform --ignore-scripts --no-progress --non-interactive install;
    patchShebangs node_modules;
    )

    dune build -j$NIX_BUILD_CORES --release @install
    (
    cd ivette;
    yarn --offline run electron-builder --linux --dir \
      -c.electronDist=${electron.dist} \
      -c.electronVersion=${electron.version} \
      -c.compression=store
    )
    runHook postBuild
  '';

  installFlags = [ "PREFIX=$(out)" ];

  preFixup = ''
    gappsWrapperArgs+=(--prefix OCAMLPATH ':' ${ocamlpath}:$out/lib/)
  '';

  # Allow loading of external Frama-C plugins
  setupHook = writeText "setupHook.sh" ''
    addFramaCPath () {
      if test -d "''$1/lib/frama-c/plugins"; then
        export FRAMAC_PLUGIN="''${FRAMAC_PLUGIN-}''${FRAMAC_PLUGIN:+:}''$1/lib/frama-c/plugins"
        export OCAMLPATH="''${OCAMLPATH-}''${OCAMLPATH:+:}''$1/lib/frama-c/plugins"
      fi

      if test -d "''$1/lib/frama-c"; then
        export OCAMLPATH="''${OCAMLPATH-}''${OCAMLPATH:+:}''$1/lib/frama-c"
      fi

      if test -d "''$1/share/frama-c/"; then
        export FRAMAC_EXTRA_SHARE="''${FRAMAC_EXTRA_SHARE-}''${FRAMAC_EXTRA_SHARE:+:}''$1/share/frama-c"
      fi

    }

    addEnvHooks "$targetOffset" addFramaCPath
  '';

  meta = {
    description = "Extensible and collaborative platform dedicated to source-code analysis of C software";
    homepage = "http://frama-c.com/";
    license = lib.licenses.lgpl21;
    maintainers = with lib.maintainers; [
      thoughtpolice
      amiddelk
    ];
    platforms = lib.platforms.unix;
  };
}
