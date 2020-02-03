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
- Save downloaded blocks to disk
- Dropped / timeout connection recovery
- Get working as a script
- Rearchitect focussing on one piece per peer

## To Do

- Move peer assignment from pull to push
- Store pieces in ETS / DETS / Mnesia
- Listen for incoming connections
- Send bitfield message on connection
- Respond to requests for blocks (actually seed!)
- Send have / cancel on completion of piece
- Web UI

## Architecture
The supervision tree is architected as follows:
`Bittorrent` supervises one
`Bittorrent.Client`, in charge of downloading the contents of a given .torrent file. It supervises N
`Bittorrent.PeerDownloader`, who each are responsible for fetching an available peer from the `Client`. They each supervise a single
`Task.Async`, which runs the TCP socket loop between themselves and the peer, fetching available blocks from the `Client` and reporting fetched blocks back to it.

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

