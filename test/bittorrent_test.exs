defmodule BittorrentTest do
  use ExUnit.Case
  doctest Bittorrent

  test "downloads Arch linux" do
    torrent = Path.join(__DIR__, "archlinux-2020.01.01-x86_64.iso.torrent")
    output = Path.join(__DIR__, "output/")
    assert Bittorrent.download(torrent, output) == nil
  end
end
