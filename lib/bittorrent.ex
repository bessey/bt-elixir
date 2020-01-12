defmodule Bittorrent do
  @port 6881
  use Bitwise, only_operators: true
  require Logger
  alias Bittorrent.{PeerCommunication, Torrent, Piece, Downloader}

  @moduledoc """
  BitTorrent File Downloader.
  """

  @doc """
  Download the given Torrent to the given directory.
  """
  def download(file_path, output_path) do
    prepare_output(output_path)

    torrent = File.read!(file_path) |> Bento.decode!()

    HTTPoison.start()

    peer_id = generate_peer_id()
    info_sha = info_hash(torrent["info"])

    piece_size = torrent["info"]["piece length"]

    # Hardcoded for single file mode for now
    file = %Bittorrent.File{
      path: torrent["info"]["name"],
      size: torrent["info"]["length"]
    }

    pieces =
      torrent["info"]["pieces"]
      |> piece_shas_from_binary
      |> Piece.from_shas(file.size, piece_size)

    torrent_info = %Torrent{
      announce: torrent["announce"],
      info_sha: info_sha,
      files: [file],
      pieces: pieces,
      piece_size: piece_size,
      output_path: output_path
    }

    response = Torrent.fetch_info_from_tracker(torrent_info, peer_id, @port)
    peers = peers_from_binary(response["peers"])

    # {:ok, socket} = :gen_tcp.listen(@port, [:binary, packet: 4, active: false, reuseaddr: true])

    {:ok, _process_id} = Downloader.start_link(torrent_info)
    # :sys.trace(process_id, true)

    Enum.shuffle(peers)
    |> Enum.slice(0..4)
    |> Enum.map(fn peer ->
      Task.async(fn ->
        case PeerCommunication.connect_to_peer(peer, torrent_info, peer_id) do
          {:error, error} ->
            IO.puts(error)

          {:ok, peer, socket} ->
            PeerCommunication.receive_loop(peer, torrent_info, socket)
        end
      end)
    end)
    |> Enum.map(fn task -> Task.await(task, :infinity) end)

    nil
  end

  defp info_hash(info) do
    bencoded = Bento.encode!(info)
    :crypto.hash(:sha, bencoded)
  end

  defp generate_peer_id() do
    size = 20
    :crypto.strong_rand_bytes(size) |> Base.url_encode64() |> binary_part(0, size)
  end

  # The peers value may be a string consisting of multiples of 6 bytes.
  # First 4 bytes are the IP address and last 2 bytes are the port number.
  # All in network (big endian) notation.
  defp peers_from_binary(binary) do
    binary |> :binary.bin_to_list() |> Enum.chunk_every(6) |> Enum.map(&peer_from_binary/1)
  end

  defp piece_shas_from_binary(binary) do
    binary |> :binary.bin_to_list() |> Enum.chunk_every(20) |> Enum.map(&to_string/1)
  end

  defp peer_from_binary(binary) do
    ip = Enum.slice(binary, 0, 4) |> List.to_tuple() |> :inet_parse.ntoa()
    port_bytes = Enum.slice(binary, 4, 2)
    port = (Enum.fetch!(port_bytes, 0) <<< 8) + Enum.fetch!(port_bytes, 1)

    {ip, port}
  end

  defp prepare_output(output_path) do
    # File.rm_rf!(output_path)
    File.mkdir_p!(output_path)
    File.mkdir_p!(Path.join([output_path, Downloader.in_progress_path()]))
  end
end
