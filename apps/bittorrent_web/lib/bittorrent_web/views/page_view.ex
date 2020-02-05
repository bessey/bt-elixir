defmodule BittorrentWeb.PageView do
  use BittorrentWeb, :view

  def torrent_debug() do
    torrent_state() |> inspect()
  end

  def in_progress_pieces() do
    torrent_state().in_progress_pieces
  end

  defp torrent_state() do
    {:ok, state} = Bittorrent.Client.get_state()
    state
  end
end
