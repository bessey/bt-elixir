defmodule Bittorrent.Torrent do
  defstruct [
    # Tracker Info
    :announce,
    # Torrent Info
    :info_sha,
    :pieces,
    :piece_size,
    :name,
    :files,
    :output_path,
    # Config
    :peer_id,
    # Live stats,
    uploaded: 0,
    downloaded: 0,
    peers: [],
    peer_downloader_pids: [],
    assigned_peers: []
  ]

  alias Bittorrent.Torrent
  use Bitwise, only_operators: true

  def update_with_tracker_info(%Torrent{} = torrent, port) do
    params = %{
      peer_id: torrent.peer_id,
      port: to_string(port),
      info_hash: torrent.info_sha,
      uploaded: torrent.uploaded,
      downloaded: torrent.downloaded,
      left: Torrent.left(torrent),
      compact: "1",
      no_peer_id: "true",
      event: "started"
    }

    response = HTTPoison.get!(torrent.announce, [], params: params).body |> Bento.decode!()
    %Torrent{torrent | peers: peers_from_binary(response["peers"])}
  end

  def left(%Torrent{files: files}) do
    Enum.map(files, & &1.size) |> Enum.sum()
  end

  def bitfield_pieces(bitfield) do
    for <<b::1 <- bitfield>>, into: [], do: if(b == 1, do: true, else: false)
  end

  def size(%Torrent{} = torrent) do
    List.first(torrent.files).size
  end

  def blocks_we_need_that_peer_has(pieces, piece_set) do
    pieces
    |> Enum.filter(fn piece -> Enum.at(piece_set, piece.number) end)
    |> Enum.flat_map(fn piece -> blocks_we_need_in_piece(piece) end)
  end

  defp blocks_we_need_in_piece(piece) do
    piece.blocks
    |> Enum.with_index()
    |> Enum.reject(fn {we_have_block?, _block_index} -> we_have_block? end)
    |> Enum.map(fn {_we_have_block?, block_index} -> {piece.number, block_index} end)
  end

  def request_for_block(torrent, piece_index, block_index) do
    block_size = Bittorrent.Piece.block_size()
    full_size = size(torrent)
    begin = block_index * Bittorrent.Piece.block_size()

    block_size =
      if begin + block_size > full_size do
        size(torrent) - begin
      else
        block_size
      end

    {piece_index, block_index * block_size, block_size}
  end

  def update_with_block_downloaded(torrent, piece_index, block_index, block_size) do
    pieces =
      Enum.map(torrent.pieces, fn piece ->
        if piece.number == piece_index do
          %Bittorrent.Piece{
            piece
            | blocks: List.replace_at(piece.blocks, block_index, true)
          }
        else
          piece
        end
      end)

    %Torrent{torrent | pieces: pieces, downloaded: torrent.downloaded + block_size}
  end

  # The peers value may be a string consisting of multiples of 6 bytes.
  # First 4 bytes are the IP address and last 2 bytes are the port number.
  # All in network (big endian) notation.
  defp peers_from_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(6)
    |> Enum.map(&peer_from_binary/1)
    # Shuffle so we can push/pop peers without bias toward first in original list
    |> Enum.shuffle()
    # Turn into a queue so we can use it in a FIFO way
    |> :queue.from_list()
  end

  defp peer_from_binary(binary) do
    ip = Enum.slice(binary, 0, 4) |> List.to_tuple() |> :inet_parse.ntoa()
    port_bytes = Enum.slice(binary, 4, 2)
    port = (Enum.fetch!(port_bytes, 0) <<< 8) + Enum.fetch!(port_bytes, 1)

    {ip, port}
  end
end
