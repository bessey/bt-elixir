defmodule Bittorrent.Piece do
  @moduledoc """
  A piece, as defined in the BitTorrent protocol. A torrent is made up of a fixed number of pieces of an equal fixed size.
  """

  @block_size :math.pow(2, 14) |> round

  defstruct [:sha, :size, :number, blocks: MapSet.new()]

  def block_size, do: @block_size

  def from_shas([sha | rest], torrent_size, piece_size) do
    [
      %Bittorrent.Piece{
        sha: sha,
        number: 1,
        size: piece_size
      }
    ] ++
      from_shas(rest, torrent_size - piece_size, piece_size, 2)
  end

  def from_shas([sha | rest], remaining_size, piece_size, piece_number)
      when length(rest) > 0 do
    [
      %Bittorrent.Piece{
        sha: sha,
        number: piece_number,
        size: piece_size
      }
    ] ++
      from_shas(rest, remaining_size - piece_size, piece_size, piece_number + 1)
  end

  def from_shas([sha], remaining_size, _piece_size, piece_number) do
    [
      %Bittorrent.Piece{
        sha: sha,
        number: piece_number,
        size: remaining_size
      }
    ]
  end

  def to_bitfield(pieces) do
    Enum.map(pieces, &piece_complete?/1)
  end

  def block_for_begin(begin) do
    block = begin / @block_size

    if block != round(block) do
      nil
    else
      round(block)
    end
  end

  def missing_blocks(piece) do
    MapSet.new(0..(block_count(piece) - 1)) |> MapSet.difference(piece.blocks)
  end

  def piece_complete?(piece) do
    MapSet.size(piece.blocks) == block_count(piece)
  end

  defp block_count(piece) do
    ceil(piece.size / @block_size)
  end
end
