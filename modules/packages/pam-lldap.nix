{
  lib,
  rustPlatform,
  openldap,
  linux-pam,
}:

rustPlatform.buildRustPackage {
  pname = "pam-lldap";
  version = "0.1.0";
  src = ./pam-lldap;
  cargoHash = "sha256-+Du65HEaZSKbafS21q/TVPJGS28jd0FENP3+PsSF7F4=";
  buildInputs = [
    linux-pam
    openldap
  ];
  postInstall = ''
    mkdir -p $out/lib/security
    mv $out/lib/libpam_lldap.so $out/lib/security/pam_lldap.so
  '';
  meta = {
    description = "Minimal PAM password provider with LLDAP and offline Argon2id cache";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
