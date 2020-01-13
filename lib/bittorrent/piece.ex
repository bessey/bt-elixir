defmodule Bittorrent.Piece do
  @block_size :math.pow(2, 14) |> round

  defstruct [:sha, :size, :number, :blocks]

  def block_size, do: @block_size

  def from_shas([sha | rest], torrent_size, piece_size) do
    [
      %Bittorrent.Piece{
        sha: sha,
        number: 1,
        size: piece_size,
        blocks: empty_blocks_for_size(piece_size)
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
        size: piece_size,
        blocks: empty_blocks_for_size(piece_size)
      }
    ] ++
      from_shas(rest, remaining_size - piece_size, piece_size, piece_number + 1)
  end

  def from_shas([sha], remaining_size, _piece_size, piece_number) do
    [
      %Bittorrent.Piece{
        sha: sha,
        number: piece_number,
        size: remaining_size,
        blocks: empty_blocks_for_size(remaining_size)
      }
    ]
  end

  def to_bitfield(pieces) do
    pieces |> Enum.map(& &1.blocks) |> Enum.map(&Enum.all?/1)
  end

  def empty_blocks_for_size(size) do
    List.duplicate(false, ceil(size / @block_size))
  end

  def block_for_begin(begin) do
    block = begin / @block_size

    if block != round(block) do
      nil
    else
      round(block)
    end
  end
end
