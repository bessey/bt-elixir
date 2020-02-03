defmodule Bittorrent do
  @port 6881
  require Logger
  alias Bittorrent.{Torrent, TorrentFile, Client}

  @moduledoc """
  BitTorrent File Downloader.
  """

  @doc """
  Download the given Torrent to the given directory.
  """
  def download(file_path, output_path) do
    # :observer.start()
    prepare_output(output_path)

    torrent_file_info = File.read!(file_path) |> TorrentFile.extract_info()

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

    children = [
      %{
        id: Client,
        start: {Client, :start_link, [torrent_info]}
      }
    ]

    # Now we start the supervisor with the children and a strategy
    {:ok, client_pid} = Supervisor.start_link(children, strategy: :one_for_one)

    exit_when_process_exits(client_pid)
  end

  defp generate_peer_id() do
    size = 20
    :crypto.strong_rand_bytes(size) |> Base.url_encode64() |> binary_part(0, size)
  end

  defp prepare_output(output_path) do
    File.mkdir_p!(output_path)
    File.mkdir_p!(Path.join([output_path, Client.in_progress_path()]))
  end

  defp exit_when_process_exits(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, _, _, _} ->
        IO.puts("Torrent complete!")
    end
  end
end
