defmodule Bittorrent.Torrent do
  defstruct [:info_sha, :pieces, :piece_length, :name, :files, uploaded: 0, downloaded: 0]

  def left(%{files: files}) do
    Enum.map(files, & &1.length) |> Enum.sum()
  end
end
