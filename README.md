# StreamVerse

StreamVerse is a personal Android TV and Fire TV media hub with a cinematic, remote-first layout. It is built as a GPLv3 modification of [NuvioTV](https://github.com/NuvioMedia/NuvioTV).

## Highlights

- Dark cinematic home screen with featured artwork and D-pad focus states
- Poster rows for Movies, TV Shows, Anime, Continue Watching, and custom collections
- Stremio-compatible add-on support
- User-installable community manifests and compatible open-source GitHub plugin repositories
- TMDB movie/TV discovery, lists, collections, artwork, companies, and network catalogs
- IMDb IDs and ratings, with MDBList aggregation for IMDb, TMDB, Rotten Tomatoes, Metacritic, Letterboxd, Trakt, and MyAnimeList ratings
- Trakt and Simkl account tracking, library/history synchronization, public lists, and playback scrobbling
- Add, reorder, rename, hide, or remove catalog rows from the TV app
- HLS/M3U live-stream playback and Android TV EPG integration
- Phone-accessible web tools for add-ons, repositories, stream badges, and debrid formatting
- GitHub Release update checks and guided APK installation
- Optional external-player handoff where a device has a compatible player installed
- No required account sign-in for a new Fire TV install

## Build

GitHub Actions fetches a pinned GPLv3 upstream source revision, applies the StreamVerse patch, audits the native UI, embedded web tools, TMDB/IMDb/MDBList catalogs and ratings, Trakt/Simkl tracking, HLS/M3U playback, EPG declarations, and updater modules, then builds and verifies one ARM64 Fire TV APK.

Release-critical StreamVerse catalog, add-on, tracking, and playback contract tests are blocking. The complete pinned-upstream unit-test suite also runs and its report is always uploaded; known upstream failures remain visible as advisory results instead of being hidden or preventing exact APK inspection.

Regular branch and pull-request builds are CI-signed test artifacts. A `vX.Y.Z` tag requires the repository's stable StreamVerse signing secrets, publishes one verified APK to GitHub Releases, and supplies the release used by the in-app updater. The signing key must remain identical across releases or Android will reject the update.

The embedded web tools are part of the Fire TV app. A standalone iPhone/PWA client and a complete XMLTV/Xtream channel-library manager are separate deliverables and are not claimed by this build.

See [Actions](https://github.com/Akahwaj/StreamVerse-app/actions) for build progress and APK artifacts.

## Privacy and setup

Your add-on URLs, playlists, provider credentials, and API keys are personal configuration. They are not committed to this public repository. Add them on your own device or through the companion transfer flow. Ratings from Rotten Tomatoes and the other MDBList providers use the user's authorized MDBList API access; StreamVerse does not scrape provider websites.

## License

StreamVerse is distributed under the GNU GPL v3.0. See the upstream project and included notices for attribution and license terms.
