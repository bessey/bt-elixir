defmodule Bittorrent.Piece do
  @moduledoc """
  A piece, as defined in the BitTorrent protocol. A torrent is made up of a fixed number of pieces of an equal fixed size.
  """

  alias Bittorrent.Piece

  @block_size :math.pow(2, 14) |> round
  @pieces_in_progress_path "_pieces"
  @tmp_extension ".tmp"

  defstruct [:sha, :size, :number, have: false]

  def block_size, do: @block_size

  # Pretty sure this is wrong and causes an extra piece
  def from_shas(shas, remaining_size, piece_size, index \\ 0)

  def from_shas([sha | rest], remaining_size, piece_size, index) do
    [
      %Piece{
        sha: sha,
        number: index,
        size: piece_size
      }
      | from_shas(rest, remaining_size - piece_size, piece_size, index + 1)
    ]
  end

  def from_shas([], _remaining_size, _piece_size, _index), do: []

  def complete(piece) do
    %Piece{piece | have: true}
  end

  def to_bitfield(pieces) do
    Enum.map(pieces, &piece_complete?/1)
  end

  def piece_complete?(piece) do
    piece.have
  end

  def block_count(piece) do
    ceil(piece.size / @block_size)
  end

  def begin_to_block_index(begin) do
    ceil(begin / @block_size)
  end

  def request_for_block_index(%Piece{} = piece, index) do
    begin = index * @block_size
    block_size = min(@block_size, piece.size - begin)
    {piece.number, begin, block_size}
  end

  # File Utils

  def path_for_piece(output_path, number) do
    Path.join([
      in_progress_path(output_path),
      "#{number}#{@tmp_extension}"
    ])
  end

  def in_progress_path(output_path) do
    Path.join([
      output_path,
      @pieces_in_progress_path
    ])
  end

  def store_data(piece, data, output_path) do
    computed_sha = :crypto.hash(:sha, data)

    if computed_sha == piece.sha do
      File.write(path_for_piece(output_path, piece.number), data)
    else
      {:error, :sha_mismatch}
    end
  end

  def stored_piece_numbers(output_path) do
    tmp_extension_index = -(String.length(@tmp_extension) + 1)

    {:ok, existing_pieces} = File.ls(in_progress_path(output_path))

    existing_pieces
    |> Enum.map(&String.slice(&1, 0..tmp_extension_index))
    |> Enum.map(&String.to_integer/1)
  end
end
