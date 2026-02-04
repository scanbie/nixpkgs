{
  lib,
  fetchFromGitea,
  stdenvNoCC,
  yarnConfigHook,
  yarnBuildHook,
  nodejs,
  fetchYarnDeps,
  buildGoModule,
  versionCheckHook,
  nixosTests,
}:
let
  pname = "flamenco";
  version = "3.8.2";

  src = fetchFromGitea {
    domain = "projects.blender.org";
    owner = "studio";
    repo = "flamenco";
    tag = "v${version}";
    hash = "sha256-rqBB6JBSQkoBVZO4EyrrWV6ccvvL6FHPyL26L5OSnEY=";
  };

  frontend = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "${pname}-frontend";
    inherit version;

    src = "${src}/web/app";

    nativeBuildInputs = [
      yarnConfigHook
      yarnBuildHook
      nodejs
    ];

    yarnOfflineCache = fetchYarnDeps {
      yarnLock = finalAttrs.src + "/yarn.lock";
      hash = "sha256-9g7cClQD6/lorjIfljgj3lVcUbj+V+7RhrR9BYF25sc=";
    };

    yarnBuildFlags = "--base=/app/";

    installPhase = ''
      runHook preInstall

      cp -r dist $out

      runHook postInstall
    '';
  });
in
buildGoModule (finalAttrs: {
  inherit pname version src;

  vendorHash = "sha256-BvYidVHATEgxAcqQiud0OdSE+w1HywgFAfaBWRIO+EQ=";

  ldflags = [
    "-X projects.blender.org/studio/flamenco/internal/appinfo.ApplicationVersion=${finalAttrs.version}"
    "-X projects.blender.org/studio/flamenco/internal/appinfo.ApplicationGitHash=${src.rev}"
    "-X projects.blender.org/studio/flamenco/internal/appinfo.ReleaseCycle=release"
  ];

  preBuild = ''
    cp -r ${frontend}/* web/static
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru = {
    inherit frontend;
    tests = {
      inherit (nixosTests) flamenco;
    };
  };

  meta = {
    homepage = "https://flamenco.blender.org/";
    changelog = "https://projects.blender.org/studio/flamenco/src/tag/v${finalAttrs.version}/CHANGELOG.md";
    description = "Production render farm manager";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [ bddvlpr ];
    mainProgram = "flamenco-manager";
  };
})
