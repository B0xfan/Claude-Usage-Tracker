# Top Shelf Now Playing helper

From John Hesch's Top Shelf app. Built by the "Top Shelf Now Playing helper" build phase into the app's
Resources (`libTopShelfNowPlaying.dylib` and `nowplaying.pl`); not compiled into the app itself.

Now Playing on macOS 15.4 and later works by loading this small helper into `/usr/bin/perl`, a system program
that may still read the system Now Playing service. The technique comes from
[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD 3-Clause); the helper here is
written from scratch.
