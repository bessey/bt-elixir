defmodule BittorrentWeb.IndexLive do
  use Phoenix.LiveView

  def render(assigns) do
    BittorrentWeb.PageView.render("index.html", assigns)
  end

  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(100, self(), :update)

    {:ok, build_assigns(socket)}
  end

  def handle_info(:update, socket) do
    state = torrent_state()

    {:noreply, build_assigns(socket)}
  end

  defp build_assigns(socket) do
    state = torrent_state()

    assign(socket,
      torrent_debug: torrent_debug(state),
      in_progress_pieces: in_progress_pieces(state)
    )
  end

  defp torrent_state() do
    {:ok, state} = Bittorrent.Client.get_state()
    state
  end

  def torrent_debug(torrent_state) do
    torrent_state |> inspect()
  end

  def in_progress_pieces(torrent_state) do
    torrent_state.in_progress_pieces
  end
end
