defmodule Bittorrent do
  @port 6881
  require Logger
  alias Bittorrent.{Torrent, TorrentFile, Downloader}

  @moduledoc """
  BitTorrent File Downloader.
  """

  @doc """
  Download the given Torrent to the given directory.
  """
  def download(file_path, output_path) do
    prepare_output(output_path)

    torrent_file_info = File.read!(file_path) |> TorrentFile.extract_info()

    HTTPoison.start()

    torrent_info = %Torrent{
      announce: torrent_file_info.announce,
      info_sha: torrent_file_info.info_hash,
      files: torrent_file_info.files,
      pieces: torrent_file_info.pieces,
      piece_size: torrent_file_info.piece_size,
      peer_id: generate_peer_id(),
      output_path: output_path
    }

    Logger.info(
      "Downloading #{Enum.at(torrent_info.files, 0).path} (#{length(torrent_info.pieces)} pieces)"
    )

    torrent_info = Torrent.update_with_tracker_info(torrent_info, @port)

    # {:ok, socket} = :gen_tcp.listen(@port, [:binary, packet: 4, active: false, reuseaddr: true])

    {:ok, _process_id} = Downloader.start_link(torrent_info)
    # :sys.trace(process_id, true)

    Downloader.start_peer_downloaders()

    Process.sleep(5 * 60 * 1000)

    nil
  end

  defp generate_peer_id() do
    size = 20
    :crypto.strong_rand_bytes(size) |> Base.url_encode64() |> binary_part(0, size)
  end

  defp prepare_output(output_path) do
    File.mkdir_p!(output_path)
    File.mkdir_p!(Path.join([output_path, Downloader.in_progress_path()]))
  end
end
