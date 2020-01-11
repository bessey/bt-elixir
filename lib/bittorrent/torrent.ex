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
end
