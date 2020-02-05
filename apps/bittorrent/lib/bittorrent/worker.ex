defmodule Bittorrent.Worker do
  @port 6881
  require Logger
  alias Bittorrent.{Torrent, TorrentFile, Client}

  use GenServer

  @moduledoc """
  BitTorrent File Downloader.
  """
  # Client

  def start_link(_state) do
    GenServer.start_link(__MODULE__, nil)
  end

  # Server

  @impl true
  def init(_state) do
    {:ok, Task.async(fn ->
      download(
        "/Users/matt/Dev/bt-elixir/apps/bittorrent/test/archlinux-2020.01.01-x86_64.iso.torrent",
        "/Users/matt/Dev/bt-elixir/apps/bittorrent/test/output/_pieces"
      )
    end)}
  end


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
    File.mkdir_p!(Bittorrent.Piece.in_progress_path(output_path))
  end

  defp exit_when_process_exits(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, _, _, _} ->
        IO.puts("Torrent complete!")
    end
  end
end
