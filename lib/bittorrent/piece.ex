defmodule Bittorrent.Piece do
  @block_size :math.pow(2, 14) |> round

  defstruct [:sha, :size, :number, :blocks]

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

  def update_with_bitfield(pieces, bitfield) do
    blocks_in_piece = ceil(List.first(pieces).size / @block_size)
    bit_list = for <<b::1 <- bitfield>>, into: [], do: if(b == 1, do: true, else: false)

    Enum.with_index(pieces)
    |> Enum.map(fn {piece, p_index} ->
      offset = p_index * blocks_in_piece
      blocks = Enum.slice(bit_list, offset..(offset + blocks_in_piece))
      %Bittorrent.Piece{piece | blocks: blocks}
    end)
  end

  def empty_blocks_for_size(size) do
    List.duplicate(false, ceil(size / @block_size))
  end
end
