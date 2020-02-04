# Bittorrent

A work in progress implementation of the [BitTorrent Specification](https://wiki.theory.org/index.php/BitTorrentSpecification#Info_Dictionary) as a method to learn Elixir. Inspired by [Building a BitTorrent client from the ground up in Go](https://blog.jse.li/posts/torrent/).

## Usage
```sh
> mix escript.build
> ./bittorrent --path ./my.torrent --output ./my_torrents/
```

## Working

- Parse a tracker file and use it to request peers from the tracker
- Connect to peers and handshake with them
- Record what pieces individual peers actually have
- Send requests for blocks
- Respect choke / unchoke
- Respect interested / not interested
- Save downloaded pieces to disk
- Dropped / timeout connection recovery
- Get working as a script
- Rearchitect focussing on one piece per peer

## To Do

- Store pieces in ETS / DETS / Mnesia
- Listen for incoming connections
- Send bitfield message on connection
- Respond to requests for blocks (actually seed!)
- Send have / cancel on completion of piece
- Web UI

## Architecture
`Bittorrent` supervises one
`Bittorrent.Client`, in charge of downloading the contents of a given .torrent file. It supervises N
`Bittorrent.PeerDownloader`, who each are responsible for communications with a given peer.

`Bittorrent.PeerDownloader` does all of the following forever:
1. Fetching an available peer from the `Client`.
2. Once a peer is acquired use a `Task` to establish connection to this peer asynchronously.
3. Once a connection is established, fetch an available piece from the `Client`
4. Once a piece is acquired, use a `Task` to run the TCP socket loop between themselves and the peer, fetching blocks of the piece until is complete, and is reported back to the `Client`.
5. (Loop back to step 3)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `bittorrent` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:bittorrent, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/bittorrent](https://hexdocs.pm/bittorrent).

