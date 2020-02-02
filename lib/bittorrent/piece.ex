defmodule Bittorrent.Piece do
  @moduledoc """
  A piece, as defined in the BitTorrent protocol. A torrent is made up of a fixed number of pieces of an equal fixed size.
  """

  alias Bittorrent.Piece

  @block_size :math.pow(2, 14) |> round

  defstruct [:sha, :size, :number, have: false]

  def block_size, do: @block_size

  def from_shas([sha | rest], torrent_size, piece_size) do
    [
      %Piece{
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
      %Piece{
        sha: sha,
        number: piece_number,
        size: piece_size
      }
    ] ++
      from_shas(rest, remaining_size - piece_size, piece_size, piece_number + 1)
  end

  def from_shas([sha], remaining_size, _piece_size, piece_number) do
    [
      %Piece{
        sha: sha,
        number: piece_number,
        size: remaining_size
      }
    ]
  end

  def complete(piece) do
    %Piece{piece | have: true}
  end

  def to_bitfield(pieces) do
    Enum.map(pieces, &piece_complete?/1)
  end

  def piece_complete?(piece) do
    piece.have
  end
end
