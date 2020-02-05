defmodule Bittorrent.Peer.Buffer do
  @in_flight :in_flight

  def init(piece) do
    :array.new(Bittorrent.Piece.block_count(piece))
  end

  def complete?(buffer) do
    :array.size(buffer) == :array.sparse_size(buffer) &&
      !Enum.member?(:array.to_list(buffer), @in_flight)
  end

  def progress(buffer) do
    "#{:array.sparse_size(buffer)}/#{:array.size(buffer)}"
  end

  def to_binary(buffer) do
    :array.to_list(buffer) |> Enum.reduce(fn block, piece -> piece <> block end)
  end

  def missing_block_index(buffer) do
    :array.foldl(&index_of_first_nil/3, nil, buffer)
  end

  defp index_of_first_nil(index, :undefined = _value, nil = _acc), do: index

  defp index_of_first_nil(_index, _value, acc) do
    acc
  end

  def add_block(buffer, begin, data) do
    block_index = Bittorrent.Piece.begin_to_block_index(begin)
    :array.set(block_index, data, buffer)
  end
end
