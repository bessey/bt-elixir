# Bittorrent

A work in progress implementation of the [BitTorrent Specification](https://wiki.theory.org/index.php/BitTorrentSpecification#Info_Dictionary) as a method to learn Elixir.

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
- Smarter connection handling
- Get working as a script using escript

## To Do

- Use MapSets of piece indexes for pieces rather than arrays
- Send have / cancel on completion of piece
- Respond to requests for blocks
- Listen for incoming connections
- Web UI

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

