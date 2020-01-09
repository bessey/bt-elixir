defmodule Bittorrent do
  @moduledoc """
  BitTorrent File Downloader.
  """

  @doc """
  Download the given Torrent to the given directory.
  """
  def download(file_path, output_path) do
    torrent = File.read!(file_path) |> Bento.decode!()
    IO.inspect(torrent)
    nil
  end
end
