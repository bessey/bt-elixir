defmodule BittorrentWeb.IndexLive do
  use Phoenix.LiveView

  @topic "torrents"

  def render(assigns) do
    BittorrentWeb.PageView.render("index.html", assigns)
  end

  def mount(_params, _session, socket) do
    BittorrentWeb.Endpoint.subscribe(@topic)

    {:ok, build_assigns(socket)}
  end

  def handle_info(%{topic: @topic, event: "update", payload: torrent}, socket) do
    {:noreply, build_assigns_from_state(torrent, socket)}
  end

  defp build_assigns(socket) do
    state = torrent_state()

    build_assigns_from_state(state, socket)
  end

  defp build_assigns_from_state(state, socket) do
    assign(socket,
      torrent_state: state,
      in_progress_pieces: in_progress_pieces(state),
      torrent_completion: completion(state)
    )
  end

  defp torrent_state() do
    Bittorrent.Client.get()
  end

  defp in_progress_pieces(torrent_state) do
    torrent_state.in_progress_pieces
  end

  defp completion(torrent_state) do
    downloaded =
      torrent_state.pieces
      |> Enum.filter(& &1.have)
      |> length()

    total = length(torrent_state.pieces)
    "#{Float.round(downloaded / total * 100, 1)}%"
  end
end
