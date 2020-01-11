defmodule Bittorrent.Torrent do
  defstruct [:info_sha, :pieces, :piece_size, :name, :files, uploaded: 0, downloaded: 0]
  alias Bittorrent.Piece

  def left(%Bittorrent.Torrent{files: files}) do
    Enum.map(files, & &1.size) |> Enum.sum()
  end

  # Convert a list of booleans to a bitfield
  def bitfield(%Bittorrent.Torrent{} = torrent) do
    torrent.pieces
    |> Enum.flat_map(& &1.blocks)
    |> Enum.map(fn block -> if block, do: 1, else: 0 end)
    |> Enum.into(<<>>, fn bit -> <<bit::1>> end)
  end

  def empty_pieces(%Bittorrent.Torrent{} = torrent) do
    Enum.map(torrent.pieces, fn piece ->
      block_count = length(piece.blocks)
      %Piece{piece | blocks: List.duplicate(false, block_count)}
    end)
  end

  def size(%Bittorrent.Torrent{} = torrent) do
    List.first(torrent.files).size
  end
end
