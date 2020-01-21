defmodule Bittorrent do
  @port 6881
  require Logger
  alias Bittorrent.{Torrent, Piece, Downloader}

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
      peer_id: generate_peer_id(),
      info_sha: info_hash(torrent["info"]),
      files: [file],
      pieces: pieces,
      piece_size: piece_size,
      output_path: output_path
    }

    Logger.info("Downloading #{Enum.at(torrent_info.files, 0).path} (#{length(pieces)} pieces)")

    torrent_info = Torrent.update_with_tracker_info(torrent_info, @port)

    # {:ok, socket} = :gen_tcp.listen(@port, [:binary, packet: 4, active: false, reuseaddr: true])

    {:ok, _process_id} = Downloader.start_link(torrent_info)
    # :sys.trace(process_id, true)

    Downloader.start_peer_downloaders()

    Process.sleep(5 * 60 * 1000)

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

  defp piece_shas_from_binary(binary) do
    binary |> :binary.bin_to_list() |> Enum.chunk_every(20) |> Enum.map(&to_string/1)
  end

  defp prepare_output(output_path) do
    # File.rm_rf!(output_path)
    File.mkdir_p!(output_path)
    File.mkdir_p!(Path.join([output_path, Downloader.in_progress_path()]))
  end
end
