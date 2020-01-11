defmodule Bittorrent.Torrent do
  defstruct [:info_sha, :pieces, :piece_size, :name, :files, uploaded: 0, downloaded: 0]

  def left(%Bittorrent.Torrent{files: files}) do
    Enum.map(files, & &1.size) |> Enum.sum()
  end

  def empty_pieces(%Bittorrent.Torrent{} = torrent) do
    List.duplicate(false, length(torrent.pieces))
  end

  def bitfield_pieces(bitfield) do
    for <<b::1 <- bitfield>>, into: [], do: if(b == 1, do: true, else: false)
  end

  def size(%Bittorrent.Torrent{} = torrent) do
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
end
