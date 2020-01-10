defmodule Bittorrent do
  @port 6881
  use Bitwise, only_operators: true
  require Logger
  alias Bittorrent.Peer

  @moduledoc """
  BitTorrent File Downloader.
  """

  @doc """
  Download the given Torrent to the given directory.
  """
  def download(file_path, output_path) do
    torrent = File.read!(file_path) |> Bento.decode!()
    File.rm_rf!(output_path)

    HTTPoison.start()

    # info_hash: urlencoded 20-byte SHA1 hash of the value of the info key from the Metainfo file. Note that the value will be a bencoded dictionary, given the definition of the info key above.
    # peer_id: urlencoded 20-byte string used as a unique ID for the client, generated by the client at startup. This is allowed to be any value, and may be binary data. There are currently no guidelines for generating this peer ID. However, one may rightly presume that it must at least be unique for your local machine, thus should probably incorporate things like process ID and perhaps a timestamp recorded at startup. See peer_id below for common client encodings of this field.
    # port: The port number that the client is listening on. Ports reserved for BitTorrent are typically 6881-6889. Clients may choose to give up if it cannot establish a port within this range.
    # uploaded: The total amount uploaded (since the client sent the 'started' event to the tracker) in base ten ASCII. While not explicitly stated in the official specification, the concensus is that this should be the total number of bytes uploaded.
    # downloaded: The total amount downloaded (since the client sent the 'started' event to the tracker) in base ten ASCII. While not explicitly stated in the official specification, the consensus is that this should be the total number of bytes downloaded.
    # left: The number of bytes this client still has to download in base ten ASCII. Clarification: The number of bytes needed to download to be 100% complete and get all the included files in the torrent.
    # compact: Setting this to 1 indicates that the client accepts a compact response. The peers list is replaced by a peers string with 6 bytes per peer. The first four bytes are the host (in network byte order), the last two bytes are the port (again in network byte order). It should be noted that some trackers only support compact responses (for saving bandwidth) and either refuse requests without "compact=1" or simply send a compact response unless the request contains "compact=0" (in which case they will refuse the request.)
    # no_peer_id: Indicates that the tracker can omit peer id field in peers dictionary. This option is ignored if compact is enabled.
    # event: If specified, must be one of started, completed, stopped, (or empty which is the same as not being specified). If not specified, then this request is one performed at regular intervals.
    #     started: The first request to the tracker must include the event key with this value.
    #     stopped: Must be sent to the tracker if the client is shutting down gracefully.
    #     completed: Must be sent to the tracker when the download completes. However, must not be sent if the download was already 100% complete when the client started. Presumably, this is to allow the tracker to increment the "completed downloads" metric based solely on this event.
    # ip: Optional. The true IP address of the client machine, in dotted quad format or rfc3513 defined hexed IPv6 address. Notes: In general this parameter is not necessary as the address of the client can be determined from the IP address from which the HTTP request came. The parameter is only needed in the case where the IP address that the request came in on is not the IP address of the client. This happens if the client is communicating to the tracker through a proxy (or a transparent web proxy/cache.) It also is necessary when both the client and the tracker are on the same local side of a NAT gateway. The reason for this is that otherwise the tracker would give out the internal (RFC1918) address of the client, which is not routable. Therefore the client must explicitly state its (external, routable) IP address to be given out to external peers. Various trackers treat this parameter differently. Some only honor it only if the IP address that the request came in on is in RFC1918 space. Others honor it unconditionally, while others ignore it completely. In case of IPv6 address (e.g.: 2001:db8:1:2::100) it indicates only that client can communicate via IPv6.
    # numwant: Optional. Number of peers that the client would like to receive from the tracker. This value is permitted to be zero. If omitted, typically defaults to 50 peers.
    # key: Optional. An additional identification that is not shared with any other peers. It is intended to allow a client to prove their identity should their IP address change.
    # trackerid: Optional. If a previous announce contained a tracker id, it should be set here.
    pid = peer_id()
    info_sha = info_hash(torrent["info"])

    params = %{
      info_hash: info_sha,
      peer_id: pid,
      port: to_string(@port),
      uploaded: "0",
      downloaded: "0",
      left: left(torrent["info"]),
      compact: "1",
      no_peer_id: "true",
      event: "started"
    }

    response = HTTPoison.get!(torrent["announce"], [], params: params).body |> Bento.decode!()
    peers = peers_from_binary(response["peers"])

    File.mkdir_p!(output_path)

    # {:ok, socket} = :gen_tcp.listen(@port, [:binary, packet: 4, active: false, reuseaddr: true])

    Enum.slice(peers, 0..3)
    |> Enum.map(fn peer ->
      Task.async(fn -> PeerCommunication.connect_to_peer(peer, info_sha, pid) end)
    end)
    |> Enum.map(&Task.await/1)

    nil
  end

  defp info_hash(info) do
    bencoded = Bento.encode!(info)
    :crypto.hash(:sha, bencoded)
  end

  defp peer_id() do
    length = 20
    :crypto.strong_rand_bytes(length) |> Base.url_encode64() |> binary_part(0, length)
  end

  # Single file mode
  defp left(%{"length" => length}) do
    length |> to_string()
  end

  # Multi file mode
  defp left(%{"files" => files}) do
    Enum.map(files, & &1["length"]) |> Enum.sum() |> to_string()
  end

  # The peers value may be a string consisting of multiples of 6 bytes.
  # First 4 bytes are the IP address and last 2 bytes are the port number.
  # All in network (big endian) notation.
  defp peers_from_binary(binary) do
    binary |> :binary.bin_to_list() |> Enum.chunk_every(6) |> Enum.map(&peer_from_binary/1)
  end

  defp peer_from_binary(binary) do
    ip = Enum.slice(binary, 0, 4) |> List.to_tuple() |> :inet_parse.ntoa()
    port_bytes = Enum.slice(binary, 4, 2)
    port = (Enum.fetch!(port_bytes, 0) <<< 8) + Enum.fetch!(port_bytes, 1)

    {ip, port}
  end
end
