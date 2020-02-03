defmodule Bittorrent.TrackerInfo do
  @moduledoc """
  Capture data returned from tracker for a given torrent
  """

  alias Bittorrent.{Torrent, Peer.Address}
  use Bitwise, only_operators: true

  defstruct [:announce, :peers]

  def for_torrent(%Torrent{} = torrent, port) do
    params = %{
      peer_id: torrent.peer_id,
      port: to_string(port),
      info_hash: torrent.info_sha,
      uploaded: torrent.uploaded,
      downloaded: torrent.downloaded,
      left: left(torrent),
      compact: "1",
      no_peer_id: "true",
      event: "started"
    }

    response = Tesla.get!(torrent.announce, query: params).body |> Bento.decode!()

    %Bittorrent.TrackerInfo{
      announce: torrent.announce,
      peers: peers_from_binary(response["peers"])
    }
  end

  defp left(%Torrent{files: files}) do
    Enum.map(files, & &1.size) |> Enum.sum()
  end

  # The peers value may be a string consisting of multiples of 6 bytes.
  # First 4 bytes are the IP address and last 2 bytes are the port number.
  # All in network (big endian) notation.
  defp peers_from_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(6)
    |> Enum.map(&peer_from_binary/1)
    # Shuffle so we can push/pop peers without bias toward first in original list
    |> Enum.shuffle()
    # Turn into a queue so we can use it in a FIFO way
    |> :queue.from_list()
  end

  defp peer_from_binary(binary) do
    ip = Enum.slice(binary, 0, 4) |> List.to_tuple() |> :inet_parse.ntoa()
    port_bytes = Enum.slice(binary, 4, 2)
    port = (Enum.fetch!(port_bytes, 0) <<< 8) + Enum.fetch!(port_bytes, 1)

    %Address{ip: ip, port: port}
  end
end
