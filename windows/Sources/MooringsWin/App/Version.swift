// version is the build's version, shown by the version probe and the About item, and compared with the
// latest release by the update check. The release workflow writes the tag's version here before it
// builds, and any other build is "dev", which never checks.
let version = "dev"
