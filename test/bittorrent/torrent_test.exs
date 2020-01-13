defmodule TorrentTest do
  use ExUnit.Case, async: true
  doctest Bittorrent.Torrent

  describe "Torrent.blocks_we_need_that_peer_has/2" do
    test "it filters out pieces the peer doesn't have" do
      assert Bittorrent.Torrent.blocks_we_need_that_peer_has(
               [
                 %Bittorrent.Piece{
                   number: 0,
                   blocks: [false, false],
                   sha: "123",
                   size: 1
                 },
                 %Bittorrent.Piece{
                   number: 1,
                   blocks: [false, false],
                   sha: "123",
                   size: 1
                 }
               ],
               [false, true]
             ) == [2, 3]
    end

    test "it filters out blocks we already have" do
      assert Bittorrent.Torrent.blocks_we_need_that_peer_has(
               [
                 %Bittorrent.Piece{
                   number: 0,
                   blocks: [false, true],
                   sha: "123",
                   size: 1
                 },
                 %Bittorrent.Piece{
                   number: 1,
                   blocks: [true, false],
                   sha: "123",
                   size: 1
                 }
               ],
               [false, true]
             ) == [3]
    end
  end
end
