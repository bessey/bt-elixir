defmodule BittorrentWeb.PageController do
  use BittorrentWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
