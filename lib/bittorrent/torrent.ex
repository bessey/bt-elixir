defmodule Bittorrent.Torrent do
  defstruct [
    :announce,
    :info_sha,
    :pieces,
    :piece_size,
    :name,
    :files,
    :output_path,
    uploaded: 0,
    downloaded: 0
  ]

  alias Bittorrent.Torrent

  def fetch_info_from_tracker(%Torrent{} = torrent, peer_id, port) do
    params = %{
      peer_id: peer_id,
      port: to_string(port),
      info_hash: torrent.info_sha,
      uploaded: torrent.uploaded,
      downloaded: torrent.downloaded,
      left: Torrent.left(torrent),
      compact: "1",
      no_peer_id: "true",
      event: "started"
    }

    HTTPoison.get!(torrent.announce, [], params: params).body |> Bento.decode!()
  end

  def left(%Torrent{files: files}) do
    Enum.map(files, & &1.size) |> Enum.sum()
  end

  def empty_pieces(%Torrent{} = torrent) do
    List.duplicate(false, length(torrent.pieces))
  end

  def bitfield_pieces(bitfield) do
    for <<b::1 <- bitfield>>, into: [], do: if(b == 1, do: true, else: false)
  end

  def size(%Torrent{} = torrent) do
    List.first(torrent.files).size
  end

  # Get the indexes of all the blocks the given torrent needs, that the piece_set provided has
  def blocks_for_pieces(torrent, piece_set) do
    torrent.pieces
    |> Enum.filter(fn piece ->
      # Don't consider blocks the peer doesn't have
      Enum.at(piece_set, piece.number)
    end)
    |> Enum.flat_map(fn piece ->
      piece.blocks
      |> Enum.with_index()
      |> Enum.filter(& &1)
      |> Enum.map(fn {_have_piece, index} -> index end)
    end)
  end

  def request_for_block(torrent, block) do
    block_size = Bittorrent.Piece.block_size()
    full_size = size(torrent)
    begin = block * Bittorrent.Piece.block_size()

    block_size =
      if begin + block_size > full_size do
        size(torrent) - block_size
      else
        block_size
      end

    {block, begin, block_size}
  end

  def pieces_with_block_downloaded(pieces, block) do
    {piece_index, block_index_in_piece} =
      piece_index_and_block_index_in_piece_for_block(pieces, block)

    Enum.map(pieces, fn piece ->
      if piece.number == piece_index do
        %Bittorrent.Piece{
          piece
          | blocks: List.replace_at(piece.blocks, block_index_in_piece, true)
        }
      else
        piece
      end
    end)
  end

  defp piece_index_and_block_index_in_piece_for_block(pieces, block) do
    blocks_in_piece = length(Enum.at(pieces, 0).blocks)
    piece_index = floor(block / blocks_in_piece)
    block_index_in_piece = block - piece_index * blocks_in_piece
    {piece_index, block_index_in_piece}
  end
end
