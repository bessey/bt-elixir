defmodule Mix.Tasks.Try do
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    torrent = Path.join(__DIR__, "../../test/archlinux-2020.01.01-x86_64.iso.torrent")
    output = Path.join(__DIR__, "../../test/output/")
    Bittorrent.download(torrent, output)
  end
end
