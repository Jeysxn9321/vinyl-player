import Foundation
import MusicKit
import MediaPlayer

/// One row in the Apple Music library browser.
struct AMItem: Identifiable, Hashable {
    var id: String
    var name: String
    var subtitle: String
    var imageURL: URL?
    var isAlbum: Bool
    /// Library artwork is a musicKit:// URL that AsyncImage cannot load; MusicKit's own view can.
    var artwork: Artwork? = nil
    static func == (a: AMItem, b: AMItem) -> Bool { a.id == b.id && a.isAlbum == b.isAlbum }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(isAlbum) }
}

struct AMArtist: Identifiable, Hashable { var id: String; var name: String }

/// Everything a search finds, grouped for the library screen.
struct AMSearch {
    var songs: [SongItem] = []
    var albums: [CatalogAlbum] = []
    var artists: [AMArtist] = []
    var playlists: [AMItem] = []
    var isEmpty: Bool { songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty }
}

/// Controls the app's own ApplicationMusicPlayer. MusicKit does not expose the
/// system Music app's playback to third parties, so playback must start in this app.
final class AppleMusicProvider: MusicProvider {
    let kind = ProviderKind.appleMusic
    var onState: ((MusicState) -> Void)?
    private let player = ApplicationMusicPlayer.shared
    private var timer: Timer?

    /// Up-next list from the app's own player queue (empty when playback goes through the system-player fallback).
    func queue() -> SpotifyProvider.Queue {
        let entries = Array(player.queue.entries)
        let cur = player.queue.currentEntry
        let idx = entries.firstIndex { $0.id == cur?.id } ?? -1
        func item(_ e: ApplicationMusicPlayer.Queue.Entry, _ n: Int) -> SpotifyProvider.QueueItem {
            .init(id: n, title: e.title, subtitle: e.subtitle ?? "", imageURL: nil, artwork: e.artwork)
        }
        let up = entries.enumerated().filter { $0.offset > idx }.prefix(50).map { item($0.element, $0.offset) }
        return .init(now: cur.map { item($0, max(idx, 0)) }, upNext: Array(up))
    }
    /// Jump to a row of the up-next list (row id = position in the queue entries).
    func jump(toRow n: Int, from now: Int) async {
        if useMP {
            for _ in 0..<max(1, min(n - now, 50)) { mp.skipToNextItem() }
        } else {
            let entries = Array(player.queue.entries)
            guard entries.indices.contains(n) else { return }
            player.queue.currentEntry = entries[n]
            try? await player.play()
        }
        publish()
    }
    /// Adds a song after the current one (`next`) or at the end of the queue.
    func enqueue(_ s: SongItem, next: Bool) async -> String? {
        if useMP {
            guard itunes[s.id] != nil else { return "This song can't join the current queue. Start it from its own list." }
            let d = MPMusicPlayerStoreQueueDescriptor(storeIDs: [s.id])
            if next { mp.prepend(d) } else { mp.append(d) }
            publish(); return nil
        }
        guard player.queue.currentEntry != nil else { return "Start playing something first, then queue songs." }
        let pos: ApplicationMusicPlayer.Queue.EntryInsertionPosition = next ? .afterCurrentEntry : .tail
        do {
            if let t = current.first(where: { $0.id.rawValue == s.id }) { try await player.queue.insert(t, position: pos) }
            else if let song = found[s.id] { try await player.queue.insert(song, position: pos) }
            else { return "This song can't join the current queue. Start it from its own list." }
            return nil
        } catch { return "Couldn't add it: \(error.localizedDescription)" }
    }
    private var playlists: [String: Playlist] = [:]
    private var albums: [String: Album] = [:]
    private var current: [MusicKit.Track] = []   // songs of the album/playlist whose list is open
    private var found: [String: Song] = [:]      // last catalog search
    /// Fallback when MusicKit catalog search is refused (no developer token on a sideloaded build): results come
    /// from the free iTunes Search API and play through the system music player by store ID.
    private let mp = MPMusicPlayerController.applicationMusicPlayer
    private var useMP = false
    private var itunes: [String: (title: String, artist: String, album: String, art: URL?, dur: Double)] = [:]

    func authorize() async throws {
        let s = await MusicAuthorization.request()
        guard s == .authorized else { throw MusicError.denied }
        await MainActor.run { startPolling() }
    }
    func disconnect() { timer?.invalidate(); player.stop(); mp.stop(); useMP = false; onState?(MusicState()) }

    func play() async { if useMP { mp.play() } else { try? await player.play() }; publish() }
    func pause() async { if useMP { mp.pause() } else { player.pause() }; publish() }
    func next() async { if useMP { mp.skipToNextItem() } else { try? await player.skipToNextEntry() }; publish() }
    func previous() async { if useMP { mp.skipToPreviousItem() } else { try? await player.skipToPreviousEntry() }; publish() }
    func setShuffle(_ on: Bool) async {
        if useMP { mp.shuffleMode = on ? .songs : .off } else { player.state.shuffleMode = on ? .songs : .off }
        publish()
    }
    func setRepeat(_ mode: RepeatMode) async {
        if useMP { mp.repeatMode = mode == .all ? .all : (mode == .one ? .one : .none); publish(); return }
        player.state.repeatMode = mode == .all ? .all : (mode == .one ? .one : MusicKit.MusicPlayer.RepeatMode.none)
        publish()
    }
    func seek(to t: TimeInterval) async { if useMP { mp.currentPlaybackTime = t } else { player.playbackTime = t }; publish() }

    /// Every library playlist and album (no cap; needs an Apple Music library, empty without one).
    func library() async throws -> [AMItem] {
        var pReq = MusicLibraryRequest<Playlist>()
        let pRes = try await pReq.response()
        var aReq = MusicLibraryRequest<Album>()
        let aRes = try await aReq.response()
        playlists = [:]; albums = [:]
        var out: [AMItem] = []
        for p in pRes.items {
            playlists[p.id.rawValue] = p
            out.append(AMItem(id: p.id.rawValue, name: p.name, subtitle: "Playlist",
                              imageURL: p.artwork?.url(width: 600, height: 600), isAlbum: false, artwork: p.artwork))
        }
        for a in aRes.items {
            albums[a.id.rawValue] = a
            out.append(AMItem(id: a.id.rawValue, name: a.title, subtitle: a.artistName,
                              imageURL: a.artwork?.url(width: 600, height: 600), isAlbum: true, artwork: a.artwork))
        }
        return out
    }

    func tracks(of item: AMItem) async throws -> [SongItem] {
        var list: [MusicKit.Track] = []
        if item.isAlbum, let a = albums[item.id] { list = Array(try await a.with([.tracks]).tracks ?? []) }
        else if let p = playlists[item.id] { list = Array(try await p.with([.tracks]).tracks ?? []) }
        current = list
        return list.map { SongItem(id: $0.id.rawValue, title: $0.title, artist: $0.artistName,
                                   imageURL: $0.artwork?.url(width: 200, height: 200), artwork: $0.artwork) }
    }

    /// Apple Music catalog song search. Falls back to the iTunes Search API when MusicKit refuses.
    func search(_ q: String) async throws -> [SongItem] {
        do {
            var r = MusicCatalogSearchRequest(term: q, types: [Song.self])
            r.limit = 25
            let res = try await r.response()
            found = [:]
            for s in res.songs { found[s.id.rawValue] = s }
            return res.songs.map { SongItem(id: $0.id.rawValue, title: $0.title, artist: $0.artistName,
                                            imageURL: $0.artwork?.url(width: 200, height: 200)) }
        } catch {
            return try await itunesSearch(q)
        }
    }

    private func itunesSearch(_ q: String) async throws -> [SongItem] {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [.init(name: "term", value: q), .init(name: "media", value: "music"),
                        .init(name: "entity", value: "song"), .init(name: "limit", value: "50")]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        struct R: Decodable { var results: [I] }
        struct I: Decodable {
            var trackId: Int?; var trackName: String?; var artistName: String?
            var collectionName: String?; var artworkUrl100: String?; var trackTimeMillis: Int?
        }
        let items = try JSONDecoder().decode(R.self, from: data).results
        found = [:]
        var out: [SongItem] = []
        for i in items {
            guard let id = i.trackId, let t = i.trackName else { continue }
            let key = String(id)
            let art = i.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100", with: "1200x1200")) }
            itunes[key] = (t, i.artistName ?? "", i.collectionName ?? "", art, Double(i.trackTimeMillis ?? 0) / 1000)
            out.append(SongItem(id: key, title: t, artist: i.artistName ?? "",
                                imageURL: i.artworkUrl100.flatMap { URL(string: $0) }))
        }
        return out
    }

    /// Plays one song: inside its open album/playlist (fromList) or alone from search results.
    func play(songID: String, fromList: Bool) async -> String? {
        do {
            if fromList, let t = current.first(where: { $0.id.rawValue == songID }) {
                useMP = false; mp.stop()
                player.queue = ApplicationMusicPlayer.Queue(for: current, startingAt: t)
            } else if let s = found[songID] {
                useMP = false; mp.stop()
                player.queue = ApplicationMusicPlayer.Queue(for: [s])
            } else if itunes[songID] != nil {
                player.stop(); useMP = true
                if MPMediaLibrary.authorizationStatus() == .notDetermined { _ = await withCheckedContinuation { c in MPMediaLibrary.requestAuthorization { c.resume(returning: $0) } } }
                mp.setQueue(with: [songID])
                mp.play()
                publish()
                return nil
            } else { return "That song is no longer available. Go back and reopen it." }
            try await player.play()
            publish()
            return nil
        } catch {
            return "Couldn't start playback: \(error.localizedDescription)"
        }
    }

    /// Starts playback of a library item. Returns an error message, or nil on success.
    func play(_ item: AMItem) async -> String? {
        do {
            useMP = false; mp.stop()
            if item.isAlbum, let a = albums[item.id] { player.queue = ApplicationMusicPlayer.Queue(for: [a]) }
            else if let p = playlists[item.id] { player.queue = ApplicationMusicPlayer.Queue(for: [p]) }
            else { return "That item is no longer available. Reopen the library." }
            try await player.play()
            publish()
            return nil
        } catch {
            return "Couldn't start playback: \(error.localizedDescription)"
        }
    }

    // MARK: wide catalog search, charts
    /// Songs, albums, artists and playlists for one query. Albums and artists come from the iTunes Search API
    /// (works without a developer token); playlists only from MusicKit, so they may be missing on a sideloaded build.
    func searchAll(_ q: String) async throws -> AMSearch {
        async let alb = try? itunesGet("search", ["term": q, "media": "music", "entity": "album", "limit": "25"])
        async let art = try? itunesGet("search", ["term": q, "media": "music", "entity": "musicArtist", "limit": "8"])
        var out = AMSearch()
        out.songs = try await search(q)
        out.playlists = await catalogPlaylists(q)
        out.albums = (await alb ?? []).compactMap(Self.album)
        var seen = Set<Int>()
        out.artists = (await art ?? []).compactMap { r in
            guard let id = r.artistId, let n = r.artistName, seen.insert(id).inserted else { return nil }
            return AMArtist(id: String(id), name: n)
        }
        return out
    }

    private func catalogPlaylists(_ q: String) async -> [AMItem] {
        var r = MusicCatalogSearchRequest(term: q, types: [Playlist.self])
        r.limit = 15
        guard let res = try? await r.response() else { return [] }
        return res.playlists.map { p in
            playlists[p.id.rawValue] = p
            return AMItem(id: p.id.rawValue, name: p.name, subtitle: p.curatorName.map { "Playlist, \($0)" } ?? "Playlist",
                          imageURL: p.artwork?.url(width: 600, height: 600), isAlbum: false, artwork: p.artwork)
        }
    }

    /// Current top albums of the user's store (Apple's public RSS feed); falls back to the US store.
    func topAlbums() async throws -> [CatalogAlbum] {
        let region = (Locale.current.region?.identifier ?? "US").lowercased()
        for cc in [region, "us"] {
            guard let u = URL(string: "https://itunes.apple.com/\(cc)/rss/topalbums/limit=50/json"),
                  let (d, _) = try? await URLSession.shared.data(from: u),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let entries = (j["feed"] as? [String: Any])?["entry"] as? [[String: Any]], !entries.isEmpty else { continue }
            func label(_ e: [String: Any], _ k: String) -> String? { (e[k] as? [String: Any])?["label"] as? String }
            return entries.compactMap { e in
                guard let id = ((e["id"] as? [String: Any])?["attributes"] as? [String: Any])?["im:id"] as? String,
                      let name = label(e, "im:name") else { return nil }
                let img = ((e["im:image"] as? [[String: Any]])?.last?["label"] as? String)
                    .flatMap { URL(string: $0.replacingOccurrences(of: "170x170bb", with: "400x400bb")) }
                return CatalogAlbum(id: id, title: name, artist: label(e, "im:artist") ?? "",
                                    year: String((label(e, "im:releaseDate") ?? "").prefix(4)), imageURL: img)
            }
        }
        return []
    }

    // MARK: artist / album browsing (tap the artist or title on the player)
    // Uses the public iTunes Search API (no sign-in), like the search fallback; playback goes through the system player.
    private struct ITResult: Decodable {
        var wrapperType: String?; var artistId: Int?; var collectionId: Int?; var collectionName: String?
        var artistName: String?; var artworkUrl100: String?; var releaseDate: String?
        var trackId: Int?; var trackName: String?; var trackTimeMillis: Int?; var trackNumber: Int?
    }
    private func itunesGet(_ path: String, _ q: [String: String]) async throws -> [ITResult] {
        var c = URLComponents(string: "https://itunes.apple.com/\(path)")!
        c.queryItems = q.map { .init(name: $0.key, value: $0.value) }
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        struct R: Decodable { var results: [ITResult] }
        return try JSONDecoder().decode(R.self, from: data).results
    }
    private static func album(_ r: ITResult) -> CatalogAlbum? {
        guard let id = r.collectionId, let t = r.collectionName else { return nil }
        let art = r.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100", with: "400x400")) }
        return CatalogAlbum(id: String(id), title: t, artist: r.artistName ?? "", year: String((r.releaseDate ?? "").prefix(4)), imageURL: art)
    }
    func artistAlbums(name: String, id: String?) async throws -> [CatalogAlbum] {
        let first = name.components(separatedBy: CharacterSet(charactersIn: ",&")).first?.trimmingCharacters(in: .whitespaces) ?? name
        var known = id.flatMap { Int($0) }
        if known == nil {
            known = try await itunesGet("search", ["term": first, "media": "music", "entity": "musicArtist", "limit": "1"]).first?.artistId
        }
        guard let aid = known else { return [] }
        let res = try await itunesGet("lookup", ["id": String(aid), "entity": "album", "limit": "200"])
        var seen = Set<String>()
        return res.filter { $0.wrapperType == "collection" }.compactMap(Self.album)
            .filter { seen.insert($0.title.lowercased()).inserted }
            .sorted { $0.year > $1.year }
    }
    func findAlbum(title: String, artist: String, id: String?) async throws -> CatalogAlbum? {
        let res = try await itunesGet("search", ["term": "\(title) \(artist)", "media": "music", "entity": "album", "limit": "10"])
        let hit = res.first { ($0.collectionName ?? "").lowercased() == title.lowercased() } ?? res.first
        return hit.flatMap(Self.album)
    }
    func albumTracks(_ a: CatalogAlbum) async throws -> [SongItem] {
        let res = try await itunesGet("lookup", ["id": a.id, "entity": "song", "limit": "200"])
        return res.filter { $0.wrapperType == "track" }.sorted { ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) }.compactMap { r in
            guard let id = r.trackId, let t = r.trackName else { return nil }
            let key = String(id)
            itunes[key] = (t, r.artistName ?? "", a.title, a.imageURL, Double(r.trackTimeMillis ?? 0) / 1000)
            return SongItem(id: key, title: t, artist: r.artistName ?? "", imageURL: a.imageURL)
        }
    }
    /// Plays the album's songs in order, starting at `start` when given.
    func play(album songs: [SongItem], start: SongItem?) async -> String? {
        guard !songs.isEmpty else { return "No songs to play." }
        player.stop(); useMP = true
        if MPMediaLibrary.authorizationStatus() == .notDetermined { _ = await withCheckedContinuation { c in MPMediaLibrary.requestAuthorization { c.resume(returning: $0) } } }
        let d = MPMusicPlayerStoreQueueDescriptor(storeIDs: songs.map(\.id))
        if let start { d.startItemID = start.id }
        mp.setQueue(with: d)
        mp.play()
        publish()
        return nil
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.publish() }
    }

    private func publish() {
        var st = MusicState(provider: .appleMusic)
        if useMP {
            st.isPlaying = mp.playbackState == .playing
            st.shuffle = mp.shuffleMode != .off && mp.shuffleMode != .default
            switch mp.repeatMode { case .all: st.repeatMode = .all; case .one: st.repeatMode = .one; default: st.repeatMode = .off }
            st.progress = mp.currentPlaybackTime
            if let it = mp.nowPlayingItem {
                let key = it.playbackStoreID
                let m = itunes[key]
                st.track = Track(id: key, title: m?.title ?? (it.title ?? ""), artist: m?.artist ?? (it.artist ?? ""),
                                 album: m?.album ?? (it.albumTitle ?? ""), artworkURL: m?.art,
                                 duration: it.playbackDuration > 0 ? it.playbackDuration : (m?.dur ?? 0))
            }
            onState?(st)
            return
        }
        st.isPlaying = player.state.playbackStatus == .playing
        st.shuffle = player.state.shuffleMode == .songs
        switch player.state.repeatMode { case .all?: st.repeatMode = .all; case .one?: st.repeatMode = .one; default: st.repeatMode = .off }
        st.progress = player.playbackTime
        if let entry = player.queue.currentEntry {
            if case .song(let song)? = entry.item {
                st.track = Track(id: song.id.rawValue, title: song.title, artist: song.artistName,
                                 album: song.albumTitle ?? "",
                                 artworkURL: song.artwork?.url(width: 1200, height: 1200),
                                 duration: song.duration ?? 0)
            } else {
                // Entry not resolved to a song yet: show what the queue knows so the record is not blank.
                st.track = Track(id: entry.id, title: entry.title, artist: entry.subtitle ?? "", album: "",
                                 artworkURL: entry.artwork?.url(width: 1200, height: 1200), duration: 0)
            }
        }
        onState?(st)
    }
}
