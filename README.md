# StreamVerse Android / Fire TV

This repository is the public build and orchestration layer for StreamVerse on Android TV and Fire TV. It applies the StreamVerse patch set to a pinned NuvioTV revision, runs source and contract validation, builds a universal ARM APK, and performs final packaged-APK verification before a workflow can finish successfully.

StreamVerse is designed as a remote-first media client with no required account sign-in for basic use.

## Current shared feature set

The shared build includes:

- StreamVerse branding and remote-first TV navigation
- Movies, TV, Anime, custom catalogs, and metadata-driven discovery
- Stremio-compatible community add-ons
- configurable-provider setup instead of installing empty generic manifests
- TMDB metadata and catalog integration
- IMDb/MDBList rating integrations
- Trakt and Simkl tracking/scrobbling support
- Live TV support
- built-in playback plus optional external-player handoff
- duplicate-source suppression and debrid/direct-aware source ordering
- playback diagnostics and stall monitoring
- Community Add-ons as a first-class navigation destination
- provider/debrid settings
- Adult add-on gate with PIN/session controls
- restart/settings improvements
- Fire TV compatible ARM packaging for `armeabi-v7a` and `arm64-v8a`

## Public privacy boundary

This public repository must not contain a user's personal manifest URLs, provider tokens, private AIOStreams configuration, or private bootstrap data.

Public builds contain only the shared StreamVerse feature set and public/community defaults. Personal configuration is applied separately by a private caller workflow and is never required for this repository to build.

The mandatory contract tests include public-build checks that reject known personal bootstrap markers if they appear in the public patched source.

## Build pipeline

The main workflow is `.github/workflows/build-streamverse.yml`.

It:

1. checks out this orchestration repository
2. checks out the pinned Android TV upstream source
3. applies the StreamVerse patch set
4. optionally applies a caller-provided private overlay
5. optionally changes the package ID for isolated clean-install testing
6. stamps build/version information
7. audits the patched source
8. runs mandatory StreamVerse contract tests
9. builds `:app:assembleFullRelease`
10. locates the universal APK
11. validates package identity, size, and ARM ABIs
12. uploads the APK artifact
13. runs the final end-to-end verification gate

A Gradle success by itself is not treated as a verified APK.

## Final verification gate

The final workflow gate rechecks the packaged APK after the artifact step and fails the run if any required condition is missing.

It verifies:

- APK exists and is non-empty
- APK ZIP integrity
- exact expected Android package ID
- exact stamped version code and version name
- a launchable activity is present
- both required ARM ABI directories are packaged
- the source audit report exists and contains no failures
- mandatory StreamVerse contracts still pass after packaging
- the APK artifact step completed before the final gate

The gate also records the final APK size and SHA-256 digest in the GitHub Actions job summary.

## Clean-install workflow

`.github/workflows/clean-install-test.yml` is the clean-room test path.

Each clean-test run uses a unique package ID such as:

```text
com.akahwaj.streamverse.clean.r<run-number>
```

That forces Android to create fresh application storage for every clean test. It prevents previously installed add-ons, QR state, provider configuration, tracking state, or DataStore preferences from being mistaken for data bundled in the APK.

Use this workflow when validating first-launch setup behavior.

## QR and configurable-provider expectations

The StreamVerse setup model distinguishes between simple manifest installation and configuration-required services.

A configurable add-on or provider must route the user through its configuration flow and return the configured result to StreamVerse. QR setup should be considered successful only when the resulting configuration is handed back to the app and persisted correctly.

Tracking services such as Trakt and Simkl are expected to complete the full authentication/configuration flow rather than merely exposing a settings screen.

## Build variants

### Public/shared build

Uses the normal package ID:

```text
com.akahwaj.streamverse
```

Contains all shared StreamVerse functionality and public/community defaults, but no personal private overlay.

### Personal build

A private workflow in `Akahwaj/StreamVerse` calls this reusable workflow and supplies an additional private patch. The personal APK should have the same shared features as the public build plus personal configuration.

### Clean-install build

Uses a per-run isolated package ID and separate artifact name so it can coexist with the normal app and always starts with a new data sandbox.

## Artifacts

The normal universal ARM artifact is named:

```text
StreamVerse-Fire-TV-universal-arm
```

Clean-test artifacts use a run-specific clean-install name.

Do not describe an APK as verified unless its workflow reaches the final end-to-end verification step successfully.

## Repository layout

```text
.github/workflows/
  build-streamverse.yml      # reusable/main Android build
  clean-install-test.yml     # isolated fresh-storage build
  build-report.yml           # build reporting
scripts/
  verify-streamverse-source.sh
  test-streamverse-contracts.sh
  verify-fire-tv-apk.sh
streamverse.patch
streamverse-*.patch
```

The patch files are part of the active orchestration model. Standalone duplicate patches that were fully absorbed into active companion patches are intentionally removed instead of being retained as stale copies.

## Third-party streaming disclaimer

StreamVerse does not host, upload, index, sell, or supply third-party streams or copyrighted media. It is a media client that can connect to user-selected add-ons, manifests, providers, playlists, APIs, tracking services, and external players.

Third-party services are independently operated and may change, fail, disappear, restrict access, or impose their own terms. A provider, add-on, manifest, service name, configuration option, or external link appearing in StreamVerse does not imply endorsement, ownership, affiliation, or authorization by StreamVerse.

Users are solely responsible for the services and sources they configure, for complying with applicable laws and third-party terms, and for ensuring they have the rights or permission needed to access or play content.

## Upstream and licensing

StreamVerse Android is built as a modification of NuvioTV. Preserve upstream attribution and applicable GPLv3 obligations when distributing modified builds.

## Responsible use

StreamVerse does not grant rights to third-party content. Users are responsible for the add-ons, accounts, playlists, providers, and media they configure and for ensuring they have permission to use them.
