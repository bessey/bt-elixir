defmodule Bittorrent.Piece do
  @block_size :math.pow(2, 14) |> round

  defstruct [:sha, :length, :number, :blocks]

  def from_shas([sha | rest], torrent_length, piece_length) do
    [
      %Bittorrent.Piece{
        sha: sha,
        number: 1,
        length: piece_length,
        blocks: blocks_for_length(piece_length)
      }
    ] ++
      from_shas(rest, torrent_length - piece_length, piece_length, 2)
  end

  def from_shas([sha | rest], remaining_length, piece_length, piece_number)
      when length(rest) > 0 do
    [
      %Bittorrent.Piece{
        sha: sha,
        number: piece_number,
        length: piece_length,
        blocks: blocks_for_length(piece_length)
      }
    ] ++
      from_shas(rest, remaining_length - piece_length, piece_length, piece_number + 1)
  end

  def from_shas([sha], remaining_length, _piece_length, piece_number) do
    [
      %Bittorrent.Piece{
        sha: sha,
        number: piece_number,
        length: remaining_length,
        blocks: blocks_for_length(remaining_length)
      }
    ]
  end

  defp blocks_for_length(length) do
    List.duplicate(false, ceil(length / @block_size))
  end
end
