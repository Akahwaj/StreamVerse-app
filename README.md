# StreamVerse

StreamVerse is a personal Android TV and Fire TV media hub with a cinematic, remote-first layout. It is built as a GPLv3 modification of [NuvioTV](https://github.com/NuvioMedia/NuvioTV).

## Highlights

- Dark cinematic home screen with featured artwork and D-pad focus states
- Poster rows for Movies, TV Shows, Anime, Live TV/IPTV, Continue Watching, and custom collections
- Stremio-compatible add-on support
- Add, reorder, rename, hide, or remove catalog rows from the TV app
- Support for your own playlist, IPTV, and metadata sources
- Optional external-player handoff where a device has a compatible player installed
- No required account sign-in for a new Fire TV install

## Build

GitHub Actions fetches the GPLv3 upstream source, applies `streamverse.patch`, and builds a universal debug APK for Fire TV and Android TV.

See [Actions](https://github.com/Akahwaj/StreamVerse-app/actions) for build progress and APK artifacts.

## Privacy and setup

Your add-on URLs, playlists, provider credentials, and API keys are personal configuration. They are not committed to this public repository. Add them on your own device or through the companion transfer flow.

## License

StreamVerse is distributed under the GNU GPL v3.0. See the upstream project and included notices for attribution and license terms.
